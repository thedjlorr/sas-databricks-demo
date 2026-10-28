"""Viya Bridge back end.

Serves the static pages in this folder and runs the SAS actions in
sas/04_webapp_actions.sas on Viya through the Compute REST API. The Viya
token lives only in the repo's .env (gitignored) and is never sent to the
browser. The Databricks token is read by SAS from My Folder, not by this
server.

Run from the repo root or from webapp/:
    python webapp/server.py
then open http://127.0.0.1:4173
"""
import os
import re
import threading
import time
from pathlib import Path
from urllib.parse import urlparse

import requests
import uvicorn
from dotenv import dotenv_values
from fastapi import FastAPI
from fastapi.responses import JSONResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel

HERE = Path(__file__).resolve().parent
REPO = HERE.parent
SAS_ACTIONS = REPO / "sas" / "04_webapp_actions.sas"
DEFAULT_BASE = "https://verde-viya.mtes-tt.unx.sas.com"
DEFAULT_CONTEXT = "SAS Studio compute context"
IDENT = re.compile(r"^[A-Za-z_][A-Za-z0-9_]{0,31}$")
DONE_STATES = {"completed", "warning", "error", "failed", "canceled"}


class ViyaError(Exception):
    """A problem to show the user as-is (status code, message)."""

    def __init__(self, message, status=502):
        super().__init__(message)
        self.status = status


def env():
    # Read on every call so a refreshed token in .env is picked up without a restart.
    cfg = dict(dotenv_values(REPO / ".env"))
    for key in ("WEBAPP_CA_BUNDLE", "WEBAPP_COMPUTE_CONTEXT"):  # optional overrides from the shell
        if os.environ.get(key):
            cfg[key] = os.environ[key]
    return cfg


def base_url():
    url = env().get("SAS_VIYA_URL") or DEFAULT_BASE
    parts = urlparse(url)
    return f"{parts.scheme}://{parts.netloc}" if parts.netloc else DEFAULT_BASE


def verify_arg():
    cfg = env()
    for key in ("WEBAPP_CA_BUNDLE", "CAS_CLIENT_SSL_CA_LIST"):
        path = cfg.get(key)
        if path and Path(path).is_file():
            return path
    return True


def viya(method, path, **kwargs):
    token = env().get("SAS_VIYA_TOKEN")
    if not token or token.startswith("paste-"):
        raise ViyaError("No Viya token in .env. Add SAS_VIYA_TOKEN and try again.", 401)
    headers = {"Authorization": f"Bearer {token}", "Accept": "application/json"}
    headers.update(kwargs.pop("headers", {}))
    try:
        resp = requests.request(
            method, base_url() + path, headers=headers, verify=verify_arg(), timeout=kwargs.pop("timeout", 60), **kwargs
        )
    except requests.exceptions.SSLError:
        raise ViyaError(
            "TLS certificate check failed. Set CAS_CLIENT_SSL_CA_LIST (or WEBAPP_CA_BUNDLE) in .env to a CA file that exists.", 502
        )
    except requests.exceptions.RequestException as exc:
        raise ViyaError(f"Could not reach Viya: {type(exc).__name__}", 502)
    if resp.status_code == 401:
        raise ViyaError("Viya rejected the token in .env (401). Get a fresh token and update SAS_VIYA_TOKEN.", 401)
    return resp


_lock = threading.Lock()
_session = {"id": None}


def new_session():
    wanted = env().get("WEBAPP_COMPUTE_CONTEXT") or DEFAULT_CONTEXT
    resp = viya("GET", "/compute/contexts", params={"limit": 100})
    resp.raise_for_status()
    items = resp.json().get("items", [])
    ctx = next((c for c in items if c.get("name") == wanted), None) or next(
        (c for c in items if "studio" in c.get("name", "").lower()), None
    )
    if not ctx:
        raise ViyaError(f"No compute context named '{wanted}' is available to this user.", 502)
    resp = viya("POST", f"/compute/contexts/{ctx['id']}/sessions", json={})
    if resp.status_code >= 300:
        raise ViyaError(f"Could not start a compute session ({resp.status_code}).", 502)
    _session["id"] = resp.json()["id"]
    _session["context"] = ctx["name"]
    return _session["id"]


def session_id():
    return _session["id"] or new_session()


def read_table(sid, name):
    cols = viya("GET", f"/compute/sessions/{sid}/data/WORK/{name}/columns", params={"limit": 200})
    rows = viya("GET", f"/compute/sessions/{sid}/data/WORK/{name}/rows", params={"limit": 500})
    if cols.status_code >= 300 or rows.status_code >= 300:
        return None
    return {
        "columns": [c["name"] for c in cols.json().get("items", [])],
        "rows": [r.get("cells", []) for r in rows.json().get("items", [])],
    }


def job_log(sid, jid):
    out = []
    start = 0
    while True:
        resp = viya("GET", f"/compute/sessions/{sid}/jobs/{jid}/log", params={"start": start, "limit": 1000})
        if resp.status_code >= 300:
            break
        items = resp.json().get("items", [])
        if not items:
            break
        out.extend(items)
        start += len(items)
        if len(items) < 1000:
            break
    return out


def run_sas(call, tables=("web_result",)):
    """Run the actions file plus one macro call; return the tables it left in WORK."""
    code = SAS_ACTIONS.read_text(encoding="utf-8") + "\n" + call + "\n"
    with _lock:
        for attempt in (1, 2):
            sid = session_id()
            resp = viya("POST", f"/compute/sessions/{sid}/jobs", json={"name": "viya-bridge", "code": code.split("\n")})
            if resp.status_code == 404 and attempt == 1:
                _session["id"] = None  # session expired on the server, start a new one
                continue
            break
        if resp.status_code >= 300:
            raise ViyaError(f"Viya refused the job ({resp.status_code}).", 502)
        jid = resp.json()["id"]
        deadline = time.time() + 600
        state = "running"
        while time.time() < deadline:
            state = viya("GET", f"/compute/sessions/{sid}/jobs/{jid}").json().get("state", "running")
            if state in DONE_STATES:
                break
            time.sleep(1)
        else:
            raise ViyaError("The SAS job did not finish within 10 minutes.", 504)
        log = job_log(sid, jid)
        errors = [i["line"].strip() for i in log if i.get("type") == "error"]
        if state in ("error", "failed") or errors:
            raise ViyaError("SAS reported: " + " | ".join(errors[:4] or ["the job failed, see the SAS log"]), 502)
        result = {}
        for name in tables:
            data = read_table(sid, name)
            if data is not None:
                result[name] = data
        return result


def ident(value, what):
    value = (value or "").strip()
    if not IDENT.match(value):
        raise ViyaError(f"'{value}' is not a valid {what} name (letters, digits, underscore, max 32).", 400)
    return value


def web_name(value, what):
    name = ident(value, what).upper()
    return name if name.startswith("WEB_") else ("WEB_" + name)[:32]


class LoadBody(BaseModel):
    source: str
    target: str | None = None


class TableBody(BaseModel):
    table: str


class JoinBody(BaseModel):
    customer: str
    account: str
    behavior: str
    key: str = "PRIMARY_KEY"
    output: str = "CUSTOMER_RISK_BASE"


class SaveBody(BaseModel):
    table: str
    output: str = "CUSTOMER_RISK_SCORES"


app = FastAPI(title="Viya Bridge back end")


@app.exception_handler(ViyaError)
def viya_error(_request, exc):
    return JSONResponse({"ok": False, "error": str(exc)}, status_code=exc.status)


@app.get("/api/status")
def status(deep: int = 0):
    resp = viya("GET", "/identities/users/@currentUser")
    if resp.status_code >= 300:
        raise ViyaError(f"Viya identity check failed ({resp.status_code}).", 502)
    who = resp.json()
    out = {"ok": True, "user": who.get("id"), "name": who.get("name"), "server": base_url()}
    if deep:
        with _lock:
            session_id()
        out["context"] = _session.get("context")
    return out


@app.post("/api/tables")
def tables():
    data = run_sas("%web_tables")["web_result"]
    return {"ok": True, **data}


@app.post("/api/load")
def load(body: LoadBody):
    src = ident(body.source, "table")
    tgt = web_name(body.target or src, "target")
    data = run_sas(f"%web_load(src={src}, tgt={tgt})")["web_result"]
    return {"ok": True, "target": tgt, **data}


@app.post("/api/profile")
def profile(body: TableBody):
    tbl = web_name(body.table, "table")
    data = run_sas(f"%web_profile(tbl={tbl})")["web_result"]
    return {"ok": True, "table": tbl, **data}


@app.post("/api/join")
def join(body: JoinBody):
    names = [ident(n, "table") for n in (body.customer, body.account, body.behavior)]
    key = ident(body.key, "key")
    out = web_name(body.output, "output")
    loads = "\n".join(f"%web_load(src={n}, tgt={web_name(n, 'table')})" for n in dict.fromkeys(names))
    a, b, c = (web_name(n, "table") for n in names)
    data = run_sas(f"{loads}\n%web_join(a={a}, b={b}, c={c}, key={key}, out={out})")["web_result"]
    return {"ok": True, "target": out, **data}


@app.post("/api/model")
def model(body: TableBody):
    tbl = web_name(body.table, "table")
    res = run_sas(f"%web_model(tbl={tbl})", ("web_result", "web_imp"))
    return {"ok": True, "table": tbl, "metrics": res["web_result"], "importance": res.get("web_imp")}


@app.post("/api/save")
def save(body: SaveBody):
    base = web_name(body.table, "table")
    out = web_name(body.output, "output")
    data = run_sas(f"%web_save(base={base}, out={out})")["web_result"]
    return {"ok": True, **data}


# Static pages last so /api routes win.
app.mount("/", StaticFiles(directory=HERE, html=True), name="static")

if __name__ == "__main__":
    port = int(os.environ.get("PORT", "4173"))
    print(f"Viya Bridge on http://127.0.0.1:{port}  (Viya: {base_url()})")
    uvicorn.run(app, host="127.0.0.1", port=port, log_level="warning")
