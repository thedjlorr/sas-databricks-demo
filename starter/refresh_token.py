"""Renew the SAS Viya access token and write it into this repo's .env.

    python starter/refresh_token.py

Writes SAS_VIYA_TOKEN in the repo .env (gitignored). The web app server
(webapp/server.py) re-reads .env on every request, so no restart is needed.

Viya rotates the refresh token on every use, so exactly one copy can be live.
It is kept OUTSIDE the repo, in ~/.viya/<host>.refresh_token (override with
VIYA_TOKEN_STORE), so it can never be committed. The new copy is saved
before anything else is written, so a failure later cannot lose it.

First run, or if the stored refresh token is gone or expired: the script
prints the SASLogon authorization URL. Sign in with your own account in the
browser, tick openid and uaa.user, and paste the code shown afterwards
(or pass --code <code>). The script never handles your password.

If a refresh token from the earlier standalone refresh_token.py is found in
Downloads, it is migrated into the store and the old file is removed.

Settings (all optional, read from .env): SAS_VIYA_URL (host), VIYA_CLIENT_ID,
VIYA_CLIENT_SECRET (defaults api.client / api.secret, the tenant's standard
client), WEBAPP_CA_BUNDLE or CAS_CLIENT_SSL_CA_LIST (CA file for TLS).
"""

from __future__ import annotations

import argparse
import base64
import sys
import time
from pathlib import Path
from urllib.parse import quote, urlparse

import requests
from dotenv import dotenv_values, set_key

REPO = Path(__file__).resolve().parent.parent
ENV_PATH = REPO / ".env"
DEFAULT_HOST = "verde-viya.mtes-tt.unx.sas.com"
LEGACY_STORE = Path.home() / "Downloads" / "refresh_token.txt"


def settings() -> dict:
    return dict(dotenv_values(ENV_PATH)) if ENV_PATH.exists() else {}


def host_of(cfg: dict) -> str:
    return urlparse(cfg.get("SAS_VIYA_URL") or "").netloc or DEFAULT_HOST


def store_path(cfg: dict) -> Path:
    import os

    custom = os.environ.get("VIYA_TOKEN_STORE", "").strip()
    return Path(custom) if custom else Path.home() / ".viya" / f"{host_of(cfg)}.refresh_token"


def ca_bundle(cfg: dict, insecure: bool):
    for key in ("WEBAPP_CA_BUNDLE", "CAS_CLIENT_SSL_CA_LIST"):
        path = cfg.get(key)
        if path and Path(path).is_file():
            return path
    if insecure:
        import urllib3

        urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)
        print("WARNING: no CA file found, TLS verification is OFF for this run (--insecure).")
        return False
    sys.exit(
        "No CA file found. Set WEBAPP_CA_BUNDLE (or CAS_CLIENT_SSL_CA_LIST) in .env to a CA file that exists, "
        "or re-run with --insecure to skip TLS verification for the sign-in only."
    )


def token_request(cfg: dict, verify, data: dict) -> dict:
    client = f"{cfg.get('VIYA_CLIENT_ID') or 'api.client'}:{cfg.get('VIYA_CLIENT_SECRET') or 'api.secret'}"
    basic = base64.b64encode(client.encode("ascii")).decode("ascii")
    resp = requests.post(
        f"https://{host_of(cfg)}/SASLogon/oauth/token",
        headers={"Accept": "application/json", "Content-Type": "application/x-www-form-urlencoded", "Authorization": f"Basic {basic}"},
        data=data,
        verify=verify,
        timeout=60,
    )
    if resp.status_code in (400, 401):
        raise SystemExit("Viya rejected the refresh token or code (expired or already used). Re-run with a fresh sign-in: delete the store file or pass --code.")
    resp.raise_for_status()
    return resp.json()


def retry_on_lock(fn, *args, attempts: int = 6, delay: float = 0.5):
    # OneDrive or Defender can briefly hold a file open, which fails a replace with "access denied".
    for attempt in range(1, attempts + 1):
        try:
            return fn(*args)
        except PermissionError:
            if attempt == attempts:
                raise
            time.sleep(delay)


def write_text(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--code", help="One-time SASLogon authorization code (only needed when no refresh token is stored).")
    parser.add_argument("--insecure", action="store_true", help="Skip TLS verification if no CA file is configured.")
    args = parser.parse_args()

    cfg = settings()
    store = store_path(cfg)
    verify = ca_bundle(cfg, args.insecure)

    refresh, source = "", ""
    if store.is_file() and store.read_text().strip():
        refresh, source = store.read_text().strip(), "store"
    elif LEGACY_STORE.is_file() and LEGACY_STORE.read_text().strip():
        refresh, source = LEGACY_STORE.read_text().strip(), "legacy"

    if refresh:
        body = token_request(cfg, verify, {"grant_type": "refresh_token", "refresh_token": refresh})
    else:
        code = args.code
        if not code:
            client_id = cfg.get("VIYA_CLIENT_ID") or "api.client"
            print(f"No refresh token stored. Sign in at this URL (tick openid and uaa.user), then paste the code shown:\n")
            print(f"  https://{host_of(cfg)}/SASLogon/oauth/authorize?client_id={quote(client_id)}&response_type=code\n")
            code = input("Authorization code: ").strip()
        if not code:
            raise SystemExit("No authorization code entered.")
        body = token_request(cfg, verify, {"grant_type": "authorization_code", "code": code.strip()})

    # 1. Save the rotated refresh token first, so it cannot be lost.
    new_refresh = body.get("refresh_token", refresh)
    if new_refresh:
        retry_on_lock(write_text, store, new_refresh)
    # 2. Then the access token into the repo .env.
    if not ENV_PATH.exists():
        ENV_PATH.touch()
    retry_on_lock(set_key, str(ENV_PATH), "SAS_VIYA_TOKEN", body["access_token"])
    # 3. Remove the legacy copy, it now holds a rotated-away value.
    if source == "legacy":
        LEGACY_STORE.unlink()
        print(f"Migrated the refresh token from {LEGACY_STORE} and removed that file.")

    print(f"SAS_VIYA_TOKEN updated in {ENV_PATH}")
    print(f"Refresh token kept outside the repo in {store}")


if __name__ == "__main__":
    main()
