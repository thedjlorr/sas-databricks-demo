# Databricks Modeling Demo (MCP) — Project Instructions

<!-- Bootstrapped from sas-mcp-forecasting's process/starter kit
     (2026-09-02). That repo's CLAUDE.md accumulated a large amount of
     empirical detail specific to its MFG demand-sensing dataset and its
     Visual Forecasting pipeline builds (project ids, WAPE numbers, node
     settings). None of that is reusable here — it belonged to a
     different dataset and possibly a different product area — so it was
     deliberately left out rather than copied. What's kept below is the
     genuinely dataset-agnostic process, conventions and tooling. Sections
     marked TODO are for this project specifically. -->

## What this is

**Live Databricks connection validation (2026-09-08):** This demo connects to a Databricks workspace and loads customer/financial/loan datasets into a SAS CAS library (DB_DEMO) for analysis and modeling via SAS Viya.

**Data source**: Databricks, accessed via SAS/ACCESS® Interface to Spark (`LIBNAME ... SPARK`), landing into a CAS caslib (DB_DEMO) on verde-viya.mtes-tt.unx.sas.com. Connection tested and confirmed working.

**Available tables in Databricks default schema:**
- CUSTOMER_PROFILE (customer master)
- FINANCIAL_TRANSACTIONS (transaction-level data)
- HMEQ (home equity line of credit data; good for classification/credit modeling)
- AUTOLOAN_1 (auto loan dataset)
- LOAN_DATA_SET_CSV (general loan data)
- STATE_EXP (state-level aggregates)
- Plus 15+ additional tables: sensor data, machine learning datasets, scalable test sets

**Modeling scope**: Candidate approach is classification/credit risk modeling on HMEQ or AUTOLOAN_1 datasets; alternatively time-series forecasting on FINANCIAL_TRANSACTIONS or scaled ML benchmarking on SCALATABLE* tables. Pick this before the next step — it determines whether sas/02_data_readiness.sas stays (time-series path) or gets replaced (classification/ML path).

- This repo's process pattern (config / code / judgment, see below) still applies regardless of which modeling approach is chosen.

## Environment

| Item | Value |
|---|---|
| Viya tenant | `https://verde-viya.mtes-tt.unx.sas.com` (same tenant as `sas-mcp-forecasting`) |
| CAS server | `cas-shared-default` — verify still current; not re-checked for this project |
| User | the signed-in contributor's own identity. Caslib visibility and project access are per-identity — run the playbook-style identity check (below) before assuming access to any caslib. |
| Personal caslib | `CASUSER` of the signed-in user |
| MCP compute context | **TODO** — `sas-mcp-forecasting` pins the SAS Visual Forecasting compute context, which only makes sense if this project ends up doing VF forecasting. For anything else, the default/SAS Studio compute context is more appropriate — check what the MCP connector is actually using. |
| Local Python | `requirements.txt`-equivalent not yet created here; see `sas-mcp-forecasting/requirements.txt` for the working set (`fastapi`, `uvicorn`, `pydantic`, `swat`, `pandas`, `numpy`, `requests`, `python-dotenv`, `pypdf`) if this project ends up needing a local app or SWAT fallback. |
| Databricks workspace | **TODO** — host, SQL warehouse or cluster HTTP path, catalog/schema. Fill into `sas/01_load_databricks_to_caslib.sas` once known. |
| SAS Content folder | `/Demo/Databricks_Modeling_Demo` (not yet created on the tenant — run `starter/new_project.py ... --push` from `sas-mcp-forecasting`, or push manually, when ready to mirror this repo there) |

## Two ways to run SAS code — use in this order

### 1. SAS MCP server (default)

The `claude.ai SAS MCP connector` is authenticated as whoever registered
it in their claude.ai account — it does **not** read `.env`. Key tools:
`execute_sas_code` (persistent shared compute session; `fresh_session=true`
to start clean), `list_caslibs` / `list_castables` / `get_castable_columns`
/ `get_castable_info` / `get_castable_data` (inspect before writing code),
`query_data` / `upload_data` / `upload_inline_data` / `promote_table_to_memory`
(data movement), `submit_batch_job` / `get_job_status` / `get_job_log`
(anything that can run past ~3 minutes — `execute_sas_code` aborts after
300s of silence even though the SAS keeps running server-side),
`reset_compute_session` (if wedged).

### 2. Direct SWAT / REST from local Python (fallback + automation)

`.env` (gitignored, copy from `.env.example`) holds a live OAuth token,
the CAS HTTP URL and the CA-cert path. Use when the MCP context is timing
out, for bulk profiling, or for scripts that must run outside a chat
session.

```python
import os
from dotenv import dotenv_values
import swat
env = dotenv_values(".env")
os.environ["CAS_CLIENT_SSL_CA_LIST"] = env["CAS_CLIENT_SSL_CA_LIST"]
s = swat.CAS(env["SAS_VIYA_URL"], password=env["SAS_VIYA_TOKEN"],
             ssl_ca_list=env["CAS_CLIENT_SSL_CA_LIST"])
```

The cert path may contain a space — do not `source .env` in bash; load it
with `python-dotenv` or a quoted value. REST base:
`https://verde-viya.mtes-tt.unx.sas.com` + `/compute`, `/casManagement`,
`/jobExecution`, `/files`, `/reports` etc., `Authorization: Bearer <token>`,
`verify=<cert path>`.

## Credential guardrails (non-negotiable)

- `.env` is gitignored and must stay that way. Never commit, zip, print,
  log, or paste its contents (including into SAS code, MCP tool calls, or
  chat output). `.env.example` holds placeholders only.
- Never write the Viya token, or a Databricks personal access token, into
  generated SAS code — read secrets from the environment or an authinfo
  file, never a literal. See the Auth note in
  `sas/01_load_databricks_to_caslib.sas`.
- If a real credential ever lands in a tracked file, move it out, restore
  the placeholder, and tell the user to consider rotating it.

## Data on the tenant

**TODO** — once the Databricks source and target caslib are confirmed:
working caslib/table names, schema (columns, types, grain), and — if this
ends up being a forecasting use case — time ID/interval, hierarchy,
target accumulation/missing rule, independents and where their future
values come from. Follow the readiness-check step
(`sas/02_data_readiness.sas`) for the time-series case; for a
non-time-series use case, write an equivalent readiness check (row
counts, key uniqueness, missing rates, class balance) before modeling.

## Visual Forecasting / Model Studio (reference only — not yet decided)

`sas/03_build_vf_project.sas` was copied over unchanged from
`sas-mcp-forecasting` — it is a REST-based Model Studio **forecasting**
project builder (roles, hierarchy, pipelines, run, read results) and only
applies if this demo turns out to need forecasting pipelines. It carries
no project ids or dataset-specific settings; those all lived in the
source repo's CLAUDE.md and were intentionally not copied here since they
described a different dataset. If the modeling scope turns out to be
forecasting, read `sas-mcp-forecasting/CLAUDE.md`'s "Model Studio / Visual
Forecasting projects" section for the REST API mechanics (how to create a
project, set variable roles, build a hierarchy, add pipelines from
templates, run and read the comparison table) — that knowledge is
generic to the API, not to the MFG dataset, and is worth reusing rather
than rediscovering. If the scope turns out to be something else (ML
Pipeline Automation, a hand-written CAS procedure), this file is dead
weight — delete it once that's clear.

## SAS coding conventions

- **CAS first.** Do not use `caslib _all_ assign;` (floods the log) — use
  `libname casuser cas caslib=casuser;` / `libname DB_DEMO cas caslib=DB_DEMO;`.
  Terminate sessions you start (`cas mysess terminate;`) unless a later
  call needs them; `quit;` before `terminate` if a PROC is left open.
- **Whole programs are one keyword-parameter macro** (`%macro x(p=default…);
  … %mend; %x()`) so `%if/%do` blocks work and config stays local; values
  written by `call symputx(..., 'G')` must be declared `%global` (a `%let`
  inside the macro would shadow them). Never put `;` inside `%put` text.
- **Process programs run from SAS Content**, once pushed there, not
  inline:
  ```sas
  filename src filesrvc folderpath='/Demo/Databricks_Modeling_Demo/sas' filename='<file>.sas';
  options nosource; %include src; options source;
  ```
  Push local files first (Files API `PUT /files/files/{id}/content` with
  `If-Match` ETag — `upload_file` creates a *new* file each time and
  ignores the filename). Do not use `options nonotes` — it also hides a
  program's own result-line NOTEs.
- **CAS/compute boundary.** Raw tables stay in CAS; heavy work (distinct,
  group-by, accumulation) runs there via FedSQL, CAS DATA step or CAS
  actions. Only small aggregates cross to compute WORK — for ordered
  single-threaded logic (`dif()`, lag, leading/trailing detection) and
  `call symputx` into macro variables, which a multithreaded CAS DATA
  step cannot do.
- **PROC TSMODEL / ATSM** (time-series specific — applies only if this
  ends up a forecasting use case): `outobj=` names the object in the
  program, not the class; selection spec is `ss.Open(n); ss.AddFrom(diagnose);
  ss.Close();`; trailing missing target weeks are trimmed, not forecast,
  with `lead=0`; FedSQL addresses caslibs, not librefs. See
  `sas-mcp-forecasting/CLAUDE.md` for the full skeleton and gotcha list if
  needed.
- Macro variables and WORK tables persist across MCP `execute_sas_code`
  calls — name them explicitly and `%symdel` / `proc delete` when done, or
  use `fresh_session=true`.

## Referencing SAS documentation for the right version

Full method in `docs/sas-documentation-lookup.md`; tool in
`starter/sasdoc.py`. Know the tenant release first (`&sysviyaversion`),
map the doc edition to it (never assume the `v_NNN` counter), fetch the
PDF with a browser User-Agent. The method was verified against the
`vfcdc/vfug` (Visual Forecasting) docset — if the modeling scope changes
to something else, find the matching docset id (e.g. Visual Statistics,
Visual Data Mining and Machine Learning, SAS/ACCESS Interface to Spark)
before quoting a setting from memory.

## The repeatable process (inherited pattern)

Keep three layers separate, same as `sas-mcp-forecasting`:

1. **Dataset-specific → config file** (`projects/databricks_demo.yml`):
   source/working tables, schema/roles, horizon or target definition
   (once the modeling type is chosen). A new dataset = a new config, no
   new code.
2. **Reusable → code and tenant assets**: readiness checks, project/model
   builders, results extraction to standard names, batch re-run code.
   Everything reads roles from the config — never hard-coded column names.
3. **Judgment → checklist** (`notes/databricks_demo_decisions.md`):
   record each non-obvious choice and why; this is where the demo story
   comes from.

Naming: no versions, dates, or "test" in tenant asset names. `project_id`
(= `project.id` in the yml, `databricks_demo`) ties the yml, notes, SAS
macro parameters and output-table prefix together.

## Repository layout (what's actually here)

```
sas-databricks-demo/
├── CLAUDE.md
├── .env.example / .gitignore          # copy .env.example -> .env, fill in, never commit
├── projects/
│   └── databricks_demo.yml            # TODO: fill in once source + modeling scope are known
├── notes/
│   └── databricks_demo_decisions.md   # decision checklist, mostly pending
├── sas/
│   ├── macros/
│   │   └── viya_rest.sas              # %viya_http / %viya_json / %viya_scalar / %viya_wait
│   ├── 01_load_databricks_to_caslib.sas  # PLACEHOLDER: Databricks/Spark connection + load into CAS
│   ├── 02_data_readiness.sas          # time-series readiness check (generic, config-driven) — applies if forecasting
│   └── 03_build_vf_project.sas        # Model Studio VF project builder (reference only, see above)
├── templates/
│   └── README.md                      # from sas-mcp-forecasting; empty of this project's own templates so far
├── docs/
│   ├── playbook.md                    # sas-mcp-forecasting's VF forecasting runbook — reference only until scope is decided
│   ├── lessons-learned.md             # ditto — the *why* behind that runbook's rules
│   └── sas-documentation-lookup.md    # generic doc-lookup method (docset id will need to change if scope isn't VF)
└── starter/
    ├── sasdoc.py                      # doc-lookup CLI, generic
    └── vf_nn_templates.py             # VF neural-network template factory — only relevant if scope is VF forecasting
```

Not present yet (from the source repo, add only if actually needed):
`README.md` (team onboarding), `requirements.txt`, `app/` (the Planner's
Monday demo app — specific to the MFG dataset's screens), `starter/new_project.py`
and `starter/make_claude_template.py` (bootstrapping tools for spinning up
*another* project from this one — copy from `sas-mcp-forecasting/starter/`
if that's ever needed), `docs/slides/` (no deck yet).

SAS Content mirror: not yet pushed. When ready, either re-run
`sas-mcp-forecasting/starter/new_project.py ... --push` (uses that repo's
`.env` admin token) or push manually; keep local and Content in the same
shape once it exists.

## Writing style for anything a customer or colleague will read

- Plain punctuation only. No em-dashes, en-dashes, middots, ellipsis
  characters or Unicode minus. Use commas, full stops, colons and
  parentheses.
- Standard business terms. No writerly metaphors (spine, staircase,
  frame, knee, cliff-edge, booby-trapped, encore, guardrails).
- Every figure in a customer document is a verified run figure with a log
  behind it, or it is labelled as an estimate on the slide.

## Working style

- State what you're about to run, run it, then summarise the log and
  results — don't paste 200-line logs unless asked.
- When a run fails, show the `ERROR:` lines and the fix; don't retry the
  identical code blindly.
- Prefer verifying against the live tenant over reasoning from memory
  (column names, intervals, available action sets, Spark/Databricks
  connection syntax — none of the Spark LIBNAME options above have been
  run against the live tenant yet).
- Ask before: writing to any caslib other than `CASUSER` or this
  project's own working caslib/tables, deleting or promoting global
  tables, publishing models or reports, or running anything that scans
  all caslibs.
