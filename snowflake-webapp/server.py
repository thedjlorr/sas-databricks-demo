"""NMAC Collections back end (Snowflake via SNOWLIB).

Serves the static pages in this folder and runs the SAS actions in
sas/05_snowflake_webapp_actions.sas on Viya through the Compute REST API.
It reuses the Viya plumbing (token from .env, CA bundle, compute session) of
webapp/server.py, so the token stays on the server and never reaches the browser.
Snowflake credentials are not handled here at all: SNOWLIB is a caslib on the
tenant and Viya holds its credentials.

Run from the repo root:
    python snowflake-webapp/server.py
then open http://127.0.0.1:4174
"""
import importlib.util
import os
import threading
from pathlib import Path

import uvicorn
from fastapi import FastAPI
from fastapi.responses import JSONResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel

HERE = Path(__file__).resolve().parent
REPO = HERE.parent

# Load the Databricks app's server module under another name (this file is also called "server").
_spec = importlib.util.spec_from_file_location("viya_bridge", REPO / "webapp" / "server.py")
vb = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(vb)
vb.SAS_ACTIONS = REPO / "sas" / "05_snowflake_webapp_actions.sas"

ViyaError = vb.ViyaError
SCORE_TABLES = (
    "web_result", "web_kpi", "web_tier", "web_tier_live", "web_bands", "web_product", "web_heat",
    "web_dealer", "web_work", "web_work_n", "web_fc", "web_imp",
)

app = FastAPI(title="NMAC Collections back end")
_cache = {}  # INFORMATION_SCHEMA takes about 30 seconds, so the table list is kept until refreshed
_cache_lock = threading.Lock()


class ColumnsBody(BaseModel):
    table: str


class WritebackBody(BaseModel):
    confirm: bool = False


@app.exception_handler(ViyaError)
def viya_error(_request, exc):
    return JSONResponse({"ok": False, "error": str(exc)}, status_code=exc.status)


@app.get("/api/status")
def status():
    return vb.status()


@app.post("/api/check")
def check():
    data = vb.run_sas("%sf_check")["web_result"]
    return {"ok": True, **data}


@app.post("/api/tables")
def tables(refresh: int = 0):
    with _cache_lock:
        if refresh or "tables" not in _cache:
            _cache["tables"] = vb.run_sas("%sf_tables")["web_result"]
        return {"ok": True, **_cache["tables"]}


@app.post("/api/columns")
def columns(body: ColumnsBody):
    tbl = vb.ident(body.table, "table")
    data = vb.run_sas(f"%sf_columns(tbl={tbl})")["web_result"]
    return {"ok": True, "table": tbl, **data}


@app.post("/api/load")
def load():
    data = vb.run_sas("%sf_load")["web_result"]
    return {"ok": True, **data}


@app.post("/api/score")
def score():
    res = vb.run_sas("%sf_score()", SCORE_TABLES)
    return {"ok": True, "tables": res}


@app.post("/api/forecast")
def forecast():
    res = vb.run_sas("%sf_forecast", ("web_result", "web_ts"))
    return {"ok": True, "tables": res}


@app.post("/api/writeback_status")
def writeback_status():
    """Read-only: does COLL_SCORES exist in Snowflake yet."""
    data = vb.run_sas("%sf_wb_status")["web_result"]
    return {"ok": True, **data}


@app.post("/api/writeback")
def writeback(body: WritebackBody):
    """Create RND_DB.SEFORD.COLL_SCORES in Snowflake. Refuses unless the caller confirms."""
    if not body.confirm:
        raise ViyaError("Write-back needs explicit confirmation.", 400)
    data = vb.run_sas("%sf_writeback")["web_result"]
    return {"ok": True, **data}


# Static pages last so /api routes win.
app.mount("/", StaticFiles(directory=HERE, html=True), name="static")

if __name__ == "__main__":
    port = int(os.environ.get("PORT", "4174"))
    print(f"NMAC Collections on http://127.0.0.1:{port}  (Viya: {vb.base_url()})")
    uvicorn.run(app, host="127.0.0.1", port=port, log_level="warning")
