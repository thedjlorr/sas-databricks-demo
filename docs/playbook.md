# Forecasting process playbook — running it for a new dataset

This is the runbook. It assumes the process assets in this repo (and their
mirror on SAS Content `/Demo/MCP_Forecasting`) already exist. For the *why*
behind each rule see `docs/lessons-learned.md`.

Time budget for a new dataset, once the data is visible: **about half a
day**, most of it the decisions, not the code.

## 0. Before touching data (15 min)

1. **Identity check.** Run this through the MCP connector and note the groups:
   ```sas
   cas s; proc cas; builtins.userInfo; run; quit; cas s terminate;
   ```
   The connector's CAS identity is your own, and it can differ from the
   identity behind `.env` (Ross's connector identity lacked
   `SASAdministrators`), so it may not see every caslib. Anything the
   process must read has to be visible to **this** identity. Each
   contributor runs this check once; do not assume a colleague's result.
2. **Caslib visibility.** `list_castables` on the source caslib via the
   MCP. If it says "caslib does not exist", plan a promoted copy into a
   caslib the connector *can* see (`DB_DEMO` for this demo) - that is
   step 01, and someone with visibility (SAS Studio) runs it.
3. **Content folder.** Everything runs from `/Demo/MCP_Forecasting/sas`
   via `filesrvc`. New programs are pushed there before they are run;
   keep local and Content in the same shape.
4. **Documentation for this release.** Note `&sysviyaversion` and, before
   quoting any node setting or default, use the matching guide edition:
   `python starter\sasdoc.py match vfcdc vfug <release>` then `section`/
   `grep`. Method and version map: `docs/sas-documentation-lookup.md`.
5. **Name the project** by the pattern
   `<Business area> - <Target> Forecast (MCP)`. No versions, dates or
   "test" in names. Choose the `project_id` slug (e.g. `retail_sku`).

## 1. Config and checklist (30 min)

1. Copy `projects/mfg_demand.yml` → `projects/<slug>.yml`. Fill: source
   and working tables, time ID / interval / seasonality, target with
   accumulation and missing rule, BY vars in hierarchy order, independents
   and where their future values come from, horizon/holdback/metric.
2. Copy `notes/mfg_demand_decisions.md` → `notes/<slug>_decisions.md`.
   Keep the 13 decision rows; mark everything *pending* until the
   readiness check has run. Add the open questions for the business owner.
3. Rule: change the yml first, then the macro defaults (or pass overrides
   in the call). The SAS programs do not read the yml; their keyword
   defaults mirror it.

## 2. Working copy — `01_copy_*.sas` (10 min)

```sas
%copy_to_caslib(source_caslib=P_XXX, target_caslib=DB_DEMO,
                demand_table=<T>, exo_file=<file>.sashdat, exo_table=<E>)
```
Promoted **and** saved to disk (survives a CAS restart). Run in SAS Studio
if the source is invisible to the connector; verify afterwards with
`list_castables` / `get_castable_info` through the MCP.

## 3. Data readiness — `02_data_readiness.sas` (20 min + reading)

Submit as a **batch job** (`submit_batch_job`), not interactively:
```sas
%let vf_skip_autorun = 1;   /* if the file gains an autorun switch */
filename src filesrvc folderpath='/Demo/MCP_Forecasting/sas' filename='02_data_readiness.sas';
%include src;
%data_readiness(project_id=<slug>, in_caslib=DB_DEMO, in_table=<T>, exo_table=<E>,
                time_id=<col>, interval_days=7, horizon=12, target=<y>,
                by_vars=<a b c>, independents=<x1 x2 ...>, exo_date_var=<col>, exo_date_is_char=1)
```
Read the verdict and, for each WARN, write the decision into the
checklist. The findings that mattered on MFG and will recur:
- **forecast origin** = last observed target week — rows after it are
  horizon rows (missing target, populated drivers) → `MISSING`, not zero;
- **duplicate rows per series-week** → BY vars are not a key; decide
  `accumulate=` deliberately (TOTAL for volumes);
- **levels that add no series** (Region/Plant on MFG) → attributes, not
  hierarchy levels;
- **future regressor coverage** ≥ horizon, in-table or from an external
  file; short-series and intermittency counts → template choice.

## 4. Build the Model Studio project — `03_build_vf_project.sas` (10 min + 6 min run)

Batch job, `if_exists=replace` for the first build:
```sas
%let vf_skip_autorun = 1;
filename src filesrvc folderpath='/Demo/MCP_Forecasting/sas' filename='03_build_vf_project.sas';
%include src;
%build_vf_project(project_id=<slug>, project_name=%str(<Area> - <Target> Forecast (MCP)),
                  in_caslib=DB_DEMO, in_table=<T>, target=<y>, by_vars=<a b c>, reconciliation_level=<i>,
                  independents=<x1 x2 ...>, horizon=12, back=0,
                  add_templates=forecasting-hierarchical-1 forecasting-regression-2,
                  add_names=%str(Hierarchical Forecasting|Regression),
                  if_exists=replace, run_pipelines=all, wait_for_job=1, max_wait=900)
```
It creates the project, sets roles, hierarchy (reconciliation level
re-applied after the data load), loads data, renames "Pipeline 1" to
Auto-forecasting, adds the template pipelines, runs them all and prints
the comparison. Take `VF_PROJECT_ID` from the log into the yml.

Afterwards: `if_exists=reuse, run_pipelines=none` prints the comparison
without running; `reuse` also adds any pipeline not yet present.

## 4b. Neural-network pass (optional, 15 min + 5 min run)

Only after Regression and Auto-forecasting have run. Add the three
templates that earned their place on MFG (`templates/README.md`):
`add_templates=e08cf376-… 060cd1c4-… 861ad38b-…` (Panel, Stacked, RNN),
one node per pipeline, into the **holdback** project so the comparison is
out-of-sample, `run_pipelines=all` in batch. Read WAPE for the ranking
and WMASE for sanity (> 1 = worse than naive → configuration problem).
Expect: feed-forward nodes ≈ Regression; the RNN node may win, but it is
a per-series pick among LSTM/ESM/ARIMAX on its own holdout — check how
many series chose the LSTM before making it the headline. Leave
Multistage and autotune out of batch runs (see lessons-learned §J).
**Node names:** every modelling node is named model + distinguishing
settings (`Panel NN (holdout 12, 5 tries)`, `RNN LSTM/ESM/ARIMAX
(holdout 12)`), never the stock name, and the pipeline is `MCP - ` +
the same idea. The MCP templates already carry these names; if you add
a stock or third-party template whose node type already exists in the
project (e.g. Jim's "Machine Learning" adds a second Panel NN), rename
its nodes right after instantiation (`starter/vf_template_rename_node.py
--project … --pipeline … --old … --new …`). Reason: node results, logs
and the job list show only the node name.
**Review view:** add `106b624e-…` "MCP - Neural Networks" (all four NN
nodes → one Model Comparison) to the *main* project when someone wants
to compare the NN nodes on one screen; keep the per-model pipelines in
the holdback project for the ranking, because the project table shows
only a pipeline's champion. Instantiate templates with the prototype
`id` kept (the builder does) — without it the nodes come with stock
settings and no error.

## 4c. Demand-sensing pass (optional, 30 min + 10 min batch)

Only when the data carries a signal that is genuinely known ahead of the
target (an order book, customer schedules) or an event calendar. It is a
second *instance* of the process on the same working table, not new code:

1. **Config**: `projects/<slug>_sensing.yml` (copy `mfg_demand_sensing.yml`)
   with `sensing:` — origin = last observed − holdback, `known_weeks`
   (order-to-ship lead), the events CSV. Record the "known N weeks ahead"
   assumption in the decisions note; only customer order snapshots prove it.
2. **Prep** — `sas/04_prep_sensing_signals.sas` in batch: `Orders_known`
   (actual ≤ origin + N, stage-1 ESM forecast beyond), `Event_<type>_pre/_post`
   from `projects/<slug>_events.csv`, row grain preserved, leakage test
   (fails the job if any row after the known window carries an actual
   order). Output `<caslib>.<slug>_sensing_input`, promoted + saved.
3. **Readiness** on the prepared table (`in_table=`, `exo_table=` blank,
   `out_prefix=` short — SAS table names cap at 32 characters).
4. **Build** a third project with the builder: same everything as the
   holdback project except `in_table=` and `independents=` (+ a per-variable
   `indep_accumulate=` list: `Orders_known` TOTAL, event flags AVERAGE).
   Pipelines: Auto, Regression (the sensing test), the RNN template
   (its ARIMAX branch uses the drivers), Demand Classification for the
   specialties. `if_exists=replace`, batch, `max_wait=1500`.
5. **Rolling-origin test** — `sas/35_rolling_origin.sas` in batch: PROC
   TSMODEL, 8 weekly origins, macro-only vs macro + orders + events,
   WAPE by lead bucket 1–4 / 5–8 / 9–12. This is the sensing claim;
   quote gains on weeks 1–8 only. MFG: 6.8 % → 4.0 % on weeks 1–4,
   nothing beyond week 4.
6. **Extract** — `sas/30_extract_results.sas`: project `<HEX8>.OUTFOR`
   tables → `<prefix>outfor` + WAPE by lead bucket per pipeline; compare
   with the macro-only holdback project's numbers (same holdback, same
   BY vars) so the delta is attributable to the signals.

## 5. Read the results honestly (15 min)

- Compare pipelines on **WAPE**. WMAPE is inflated by low-volume series
  and is computed at the reconciliation level for hierarchical pipelines.
- `back=0` gives in-sample fit. **Before quoting accuracy**, build a
  second project with a holdback (`project_name=<name> holdback N (MCP)`,
  `back=N`, same everything else) and read the same table. `back` must be
  **less than** `horizon` (the service rejects 12/12), and it only takes
  effect through the settings PUT the builder does after the load — check
  the `holdback (back) after settings PUT` NOTE in the log. Keep the main
  project in-sample for the forecast view.
- Record the pass in the decisions note (table + one-paragraph reading).

## 6. Deck (1–2 h)

`docs/slides/<slug>-training.html` from the POC 1/2 template: copy the
chrome verbatim from `poc2-build-approach.html`, author slides with its
classes. Push to Content `docs/slides/`; publish as an artifact with the
wrappers stripped. Keep the honest caveats on the slides.

## 7. Close out (10 min)

Update CLAUDE.md's status block (project id, pipeline ids, results,
ids that were replaced), the decisions note, and the memory status file.
Delete any `zz … (delete me)` probe projects.

## Bootstrapping a *new repo* from this one

Use the kit — it does the copying and keeps the generic programs single-
sourced:

```powershell
python starter\new_project.py --slug <slug> --name "<Area> - <Target> Forecast (MCP)" `
    --target C:\SAS\<NewRepo> --content-folder /Demo/<NewRepo> --push
```

Copied unchanged: `sas/macros/viya_rest.sas`, `sas/02_data_readiness.sas`,
`sas/03_build_vf_project.sas`, `templates/README.md`, `docs/playbook.md`,
`docs/lessons-learned.md`, `.gitignore`, `.env.example`. Instantiated
from templates: `CLAUDE.md` (two `TODO` sections to write), `projects/
<slug>.yml`, `notes/<slug>_decisions.md`, `sas/01_copy_<slug>_to_caslib.sas`
(defaults to edit). `--push` creates the Content tree and uploads. See
`starter/README.md`.
