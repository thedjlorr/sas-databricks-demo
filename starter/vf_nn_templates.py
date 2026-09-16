"""vf_nn_templates.py — compose configured single-node Visual Forecasting
pipelines, save them as reusable pipeline templates ("<prefix> - ...") and
export their JSON.

    python starter/vf_nn_templates.py --caslib DB_DEMO --table MFG_DEMAND_SENSING_DEMO
        [--ml-template 4942334c-...] [--rnn-template 08e9e142-...] [--prefix "MCP"] [--out templates]

Method: take a template prototype, keep one Modeling node (or swap in a
component template's prototype under the same id), POST to a throwaway
project (;version=3), PUT the live component's componentProperties with
the chosen settings, verify, save as template, re-instantiate once to
confirm persistence, delete the throwaway. Idempotent by template name;
retries dropped connections. Edit SPECS to change the set or settings.
Uses the admin token in .env (throwaway project creation + templates).
"""
import argparse
ap = argparse.ArgumentParser()
ap.add_argument("--caslib", required=True); ap.add_argument("--table", required=True)
ap.add_argument("--cas-server", default="cas-shared-default")
ap.add_argument("--ml-template", default="4942334c-7d37-4cc9-aaf9-9c7d9ac53bfa", help="pipeline template whose prototype supplies Panel NN / Stacked / Multistage nodes")
ap.add_argument("--rnn-template", default="08e9e142-94e1-414f-86a3-aa662cc0d9ec", help="custom RNN component template id (blank to skip)")
ap.add_argument("--prefix", default="MCP"); ap.add_argument("--out", default=r"templates")
ap.add_argument("--env", default=r".env")
ARGS = ap.parse_args()
import requests, json, time, copy, pathlib
_orig = {m: getattr(requests, m) for m in ("get", "post", "put", "delete")}
def _retry(method):
    def call(*a, **k):
        for attempt in range(5):
            try:
                return _orig[method](*a, **k)
            except (requests.exceptions.ConnectionError, requests.exceptions.ChunkedEncodingError, requests.exceptions.ReadTimeout) as e:
                print(f"      [retry {attempt+1}/5 on {method}] {type(e).__name__}"); time.sleep(10 * (attempt + 1))
        return _orig[method](*a, **k)
    return call
for _m in _orig: setattr(requests, _m, _retry(_m))
from dotenv import dotenv_values
env = dotenv_values(ARGS.env)
base = "https://verde-viya.mtes-tt.unx.sas.com"; V = env["CAS_CLIENT_SSL_CA_LIST"]
TOK = env["SAS_VIYA_TOKEN"]; H = {"Authorization": f"Bearer {TOK}", "Accept": "application/json"}
P3 = "application/vnd.sas.analytics.pipeline+json;version=3"
ML = ARGS.ml_template; RNN = ARGS.rnn_template
OUT = pathlib.Path(r"c:\SAS\MCP_Forecasting\templates")

proto = requests.get(f"{base}/analyticsGateway/pipelineTemplates/{ML}", headers=H, verify=V, timeout=60).json()["prototype"]
rnn = requests.get(f"{base}/analyticsGateway/componentTemplates/{RNN}", headers=H, verify=V, timeout=60).json()["prototype"] if RNN else None

def single(proto, keep_name, new_name, replace_with=None, edit=None, node_name=None):
    """One-Modeling-node pipeline. node_name renames the kept node (rule: node name = model +
    the settings that distinguish it, never the stock template name - duplicates across
    pipelines are indistinguishable in node results, logs and the Job Execution list)."""
    p = copy.deepcopy(proto); p["name"] = new_name; p["description"] = new_name; p.pop("id", None)
    removed, keep_id = set(), None
    for lane in p["swimLanes"]:
        if lane["name"] == "Modeling":
            for cid, c in list(lane["components"].items()):
                if c.get("name") == keep_name: keep_id = cid
                else: removed.add(cid); del lane["components"][cid]
            if replace_with is not None:
                nc = copy.deepcopy(replace_with); nc["id"] = keep_id; lane["components"] = {keep_id: nc}
            if node_name:
                lane["components"][keep_id]["name"] = node_name
            if edit:
                edit(lane["components"][keep_id])
    p["connections"] = {k: v for k, v in p["connections"].items() if v.get("from") not in removed and v.get("to") not in removed}
    return p

def nn_edit(holdout=12, tries=5, neurons=20, act="Tanh", autotune=False, trend="None"):
    def f(c):
        cp = c["componentProperties"]
        # fresh components keep the settings at top level; run components wrap them in _backendArgs
        a = cp["_backendArgs"] if "_backendArgs" in cp else cp
        # each node type has a slightly different tree: update only what exists
        fg = a.get("featureGeneration"); mg = a.get("modelGeneration", {}); ms = a.get("modelSelection")
        if isinstance(fg, dict):
            for k, v in {"lagYNumber": 4, "lagXNumber": 4, "esmY": True, "seasonalDummy": True, "trendVariable": trend}.items():
                if k in fg: fg[k] = v
        if isinstance(mg.get("initialization"), dict):
            for k, v in {"numHiddenLayers": 1, "hidden1Neurons": neurons, "hidden1ActFxn": act}.items():
                if k in mg["initialization"]: mg["initialization"][k] = v
        if isinstance(mg.get("training"), dict):
            for k, v in {"numTries": tries, "maxIterations": 500, "earlyStopping": True}.items():
                if k in mg["training"]: mg["training"][k] = v
        if isinstance(mg.get("autotune"), dict):
            mg["autotune"]["autotuneEnabled"] = autotune
            if autotune: mg["autotune"].update({"maxIterations": 5, "maxTime": 30})
        if isinstance(ms, dict) and "holdoutSampleSize" in ms: ms["holdoutSampleSize"] = holdout
        print("      edited keys:", "fg" if fg else "", list(mg.keys()), "ms" if ms else "")
    return f

def rnn_edit(c):
    p = c["componentProperties"]; p["_holdoutSampleSize"] = 12

P = ARGS.prefix
# (stock node to keep, pipeline/template name, node name, replacement prototype, settings edit)
SPECS = [
    ("Panel Series Neural Network", f"{P} - NN Panel Series (holdout 12, 5 tries)",     "Panel NN (holdout 12, 5 tries)",      None, nn_edit()),
    ("Panel Series Neural Network", f"{P} - NN Panel Series (autotune)",                "Panel NN (autotune)",                 None, nn_edit(autotune=True)),
    ("Stacked Model (NN + TS)",     f"{P} - NN Stacked NN+TS (holdout 12, 5 tries)",    "Stacked NN+TS (holdout 12, 5 tries)", None, nn_edit()),
    ("Multistage Model",            f"{P} - NN Multistage (defaults)",                  "Multistage NN (defaults)",            None, None),
    *([("Panel Series Neural Network", f"{P} - RNN Forecasting (custom node, holdout 12)", "RNN LSTM/ESM/ARIMAX (holdout 12)", rnn, rnn_edit)] if rnn else []),
]

# throwaway project
for i in requests.get(f"{base}/analyticsGateway/projects", headers=H, verify=V, timeout=60, params={"limit":500}).json()["items"]:
    if i["name"].startswith(f"zz {P}"): requests.delete(f"{base}/analyticsGateway/projects/{i['id']}", headers=H, verify=V, timeout=60)
body = {"name":f"zz {P} template factory (delete me)","description":"compose NN templates","projectType":"forecasting",
 "dataUri":f"/dataTables/dataSources/cas~fs~{ARGS.cas_server}~fs~{ARGS.caslib}/tables/{ARGS.table}","dataServerName":ARGS.cas_server,
 "dataMediaType":"application/vnd.sas.data.table","dataLabel":ARGS.table,
 "providerSpecificProperties":{"lead":"12","back":"0","confidenceLimit":"0.05","comparisonMetric":"MAPE","allowNegative":"false","outlierLowerBound":"70","outlierUpperBound":"300","almostFlatMethod":"STD_SLOPE","almostFlatAbsoluteTolerance":"0.005","almostFlatRelativeTolerance":"0.05","computeContextUri":"","createdFromExternalForecasts":"false","annotation":""}}
r = requests.post(f"{base}/analyticsGateway/projects", headers={**H,"Content-Type":"application/vnd.sas.analytics.project+json","Accept":"application/vnd.sas.analytics.project+json"}, json=body, verify=V, timeout=60)
pid = r.json()["id"]; print("factory project", pid); time.sleep(8)

# remove any earlier "MCP - " templates so names stay unique
existing = {t["name"]: t["id"] for t in requests.get(f"{base}/analyticsGateway/pipelineTemplates", headers=H, verify=V, timeout=60, params={"limit":500}).json()["items"] if t["name"].startswith(f"{P} - ")}
print("existing MCP templates:", existing)

CT = "application/vnd.sas.analytics.component+json"
def modeling_component_id(plid):
    full = requests.get(f"{base}/analyticsPipelines/pipelines/{plid}", headers={**H,"Accept":"application/vnd.sas.analytics.pipeline+json"}, verify=V, timeout=60).json()
    return next(cid for lane in full["swimLanes"] if lane["name"]=="Modeling" for cid in lane["components"])
def get_comp(cid):
    r = requests.get(f"{base}/analyticsComponents/components/{cid}", headers={**H,"Accept":CT}, verify=V, timeout=60)
    return r.json(), r.headers.get("ETag")
def summarize(cp):
    if "_backendArgs" in cp or "modelGeneration" in cp:
        a = cp["_backendArgs"] if "_backendArgs" in cp else cp
        mg = a.get("modelGeneration", {}); g = lambda d, *ks: (d.get(ks[0]) if len(ks) == 1 else g(d.get(ks[0], {}) or {}, *ks[1:])) if isinstance(d, dict) else None
        return {"holdout": g(a, "modelSelection", "holdoutSampleSize"), "tries": g(mg, "training", "numTries"), "neurons": g(mg, "initialization", "hidden1Neurons"), "act": g(mg, "initialization", "hidden1ActFxn"), "autotune": g(mg, "autotune", "autotuneEnabled"), "esmY": g(a, "featureGeneration", "esmY"), "keys": sorted(mg.keys())}
    return {"_holdoutSampleSize": cp.get("_holdoutSampleSize"), "_nlayer": cp.get("_nlayer"), "_maxepochs": cp.get("_maxepochs")}
def configure(cid, edit, node_name=None):
    comp, et = get_comp(cid)
    if edit: edit(comp)                           # edits comp["componentProperties"] in place
    if node_name: comp["name"] = node_name        # the live component's name is what the template prototype inherits
    r = requests.put(f"{base}/analyticsComponents/components/{cid}", headers={"Authorization":f"Bearer {TOK}","Content-Type":CT,"Accept":CT,"If-Match":et}, data=json.dumps(comp).encode(), verify=V, timeout=60)
    return r.status_code

results = []
for keep, name, node_name, repl, edit in SPECS:
    if name in existing:
        tid = existing[name]; print(f"{name:48} already saved -> {tid} (skipped)")
        tj = requests.get(f"{base}/analyticsGateway/pipelineTemplates/{tid}", headers=H, verify=V, timeout=60).json()
        fn = OUT / ("pipeline_" + name.replace(f"{P} - ", "").lower().replace(" ", "_").replace("(", "").replace(")", "").replace(",", "").replace("+", "plus") + ".json")
        fn.write_text(json.dumps(tj, indent=1), encoding="utf-8"); results.append((name, tid, fn.name)); continue
    p = single(proto, keep, name, repl, None, node_name)   # compose without settings (prototypes carry no componentProperties)
    r = requests.post(f"{base}/analyticsGateway/projects/{pid}/pipelines", headers={"Authorization":f"Bearer {TOK}","Content-Type":P3,"Accept":P3}, data=json.dumps(p).encode(), verify=V, timeout=120)
    if not r.ok: print("compose", name, "->", r.status_code, r.json().get("message")); continue
    pl = r.json(); mod = modeling_component_id(pl["id"])
    put_rc = configure(mod, edit, node_name) if (edit or node_name) else "-"
    comp, _ = get_comp(mod); chk = summarize(comp.get("componentProperties", {}))
    # save as template
    full3 = requests.get(f"{base}/analyticsGateway/projects/{pid}/pipelines/{pl['id']}", headers={**H,"Accept":P3}, verify=V, timeout=60).json()
    body_t = {**full3, "name": name, "description": name + " — composed by vf_nn_templates.py"}
    t = requests.post(f"{base}/analyticsGateway/pipelineTemplates?application=forecasting", headers={"Authorization":f"Bearer {TOK}","Content-Type":P3,"Accept":"application/vnd.sas.analytics.pipeline.template+json"}, data=json.dumps(body_t).encode(), verify=V, timeout=120)
    tid = t.json().get("id") if t.ok else None
    print(f"{name:48} pipeline {r.status_code} | PUT {put_rc} | settings {chk} | template {t.status_code} {tid}")
    if tid:
        # does the saved template carry the settings? instantiate it and read the live component
        raw = requests.get(f"{base}/analyticsGateway/pipelineTemplates/{tid}", headers=H, verify=V, timeout=60).text
        i0 = raw.find('"prototype":') + len('"prototype":'); depth=0; instr=False; esc=False; pr=None
        for k in range(i0, len(raw)):
            ch = raw[k]
            if instr:
                if esc: esc=False
                elif ch=="\\": esc=True
                elif ch=='"': instr=False
            else:
                if ch=='"': instr=True
                elif ch=='{': depth+=1
                elif ch=='}':
                    depth-=1
                    if depth==0: pr = raw[i0:k+1]; break
        r2 = requests.post(f"{base}/analyticsGateway/projects/{pid}/pipelines", headers={"Authorization":f"Bearer {TOK}","Content-Type":P3,"Accept":P3}, data=(pr[:-1] + ',"name":"' + name + ' [check]"}').encode(), verify=V, timeout=120)
        if r2.ok:
            c2, _ = get_comp(modeling_component_id(r2.json()["id"]))
            print(f"{'':48} re-instantiated from template -> settings {summarize(c2.get('componentProperties', {}))}")
        tj = requests.get(f"{base}/analyticsGateway/pipelineTemplates/{tid}", headers=H, verify=V, timeout=60).json()
        fn = OUT / ("pipeline_" + name.replace(f"{P} - ", "").lower().replace(" ", "_").replace("(", "").replace(")", "").replace(",", "").replace("+", "plus") + ".json")
        fn.write_text(json.dumps(tj, indent=1), encoding="utf-8")
        results.append((name, tid, fn.name))
print("\ndelete factory project ->", requests.delete(f"{base}/analyticsGateway/projects/{pid}", headers=H, verify=V, timeout=60).status_code)
print("\nTEMPLATES:")
for name, tid, fn in results: print(f"  {tid}  {name}  -> templates/{fn}")
print("\nadd_templates=" + " ".join(t for _, t, _ in results))
print("add_names=%str(" + "|".join(n for n, _, _ in results) + ")")
