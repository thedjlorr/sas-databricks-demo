# Lessons learned — MCP_Forecasting, 26 Aug 2026

What cost time, what it taught, and the rule that now prevents it. Grouped
by where the rule lives. Each rule already appears in CLAUDE.md or the
playbook; this file is the reasoning behind them, so they are not cargo-
culted or dropped later.

## A. Identity and data access

**What happened.** The MCP connector could not see the source caslib
`P_JESC` although the `.env` token could. Two hours of ACL archaeology
before finding the real difference: the `.env` identity is a CAS
superuser (SASAdministrators), the connector's identity is not, and the
caslib's `*` grant evidently does not take effect for ordinary identities.

**Rules.** Probe with the identity that will run the code
(`builtins.userInfo` through the MCP), not with an admin token. When a
source is invisible, copy it into a caslib both can see, promoted *and*
saved, and treat the source as read-only. Ask before writing to any
caslib other than `CASUSER` and the project's working caslib.

## B. Process shape

**What happened.** The first readiness program was a block of global
`%let`s plus a parameterless macro; Ross asked for keyword parameters.
The first builder was going to be Python; SAS with `oauth_bearer=
sas_services` turned out simpler *and* token-free. Names drifted
(`cfg_slug`, `work_caslib`) until renamed to `project_id`, `in_/out_`.

**Rules.** One keyword-parameter macro per program, defaults mirroring the
yml, commas at line ends; libraries in `sas/macros/` define only, steps in
`sas/` run. Three layers — config (yml), reusable code, judgment
(decisions note) — and nothing dataset-specific in code. SAS for REST on
Viya: the compute session is already authenticated. Mirror the repo on
SAS Content and run everything from there via `filesrvc` + `%include`.

## C. SAS gotchas that each cost a run

| Gotcha | Rule |
|---|---|
| `%put` text containing `;` splits the statement | never put `;` inside `%put` text |
| `%if` nested in open code | wrap whole programs in a macro |
| `%let x=` inside a macro before `call symputx(...,'G')` | declare `%global` for symputx targets, or don't pre-`%let` |
| helper did `%global &into` while caller had `%local into` | helpers only `%global` a name that doesn't exist yet |
| `options nonotes` hides the program's own `NOTE: […]` result lines | use `nosource`, never `nonotes` |
| PROC HTTP `headerout=` to an unassigned fileref errors *after* the request succeeded — orphaned project | always `filename x temp;` first; the helper does |
| ETag values contain `"` | `"If-Match"=%tslit(&etag)` |
| bare `/` in a `%if` comparison | `= %str(/)` |
| FedSQL types a formatted date column as DATE | compare with `date '2026-01-25'` literal built in a macro var (macros don't resolve inside single quotes) |
| a failed step leaves the shared MCP compute session in syntax-check mode | `fresh_session=true` after any error |
| PROC HTTP without a body sends `form-urlencoded` → 415 | send an explicit `Content-Type` on body-less POST/PUT |
| SAS character variables cap at 32,767 | fine for the ~23 KB VF templates; measure JSON sizes before assuming |
| JSON libname table names are not guessable (`ITEMS_CELLS`, not `ROWS_ITEMS`) | inspect `dictionary.tables where libname='JC'` first |
| CATX 200-char buffer truncated a 7-column key | `select count(*) from (select distinct …)` for cardinality |

## D. MCP operational limits

**What happened.** Interactive `execute_sas_code` aborts after 300 s of
silence; twice it cut the builder mid-run, and once it hung for 90 minutes
on a two-line snippet. The SAS kept running server-side, so the tenant
was left in a half-built state each time.

**Rules.** Interactive calls only for steps that finish in ~1 min. Anything
longer — builds, model runs — goes through `submit_batch_job` and is
polled (`GET /jobExecution/jobs/{id}`); read its log via the job's
`logLocation` file. Builders get a `wait_for_job=0` fire-and-return mode.
After any timeout, check the tenant state via REST before re-running.

## E. Learning undocumented REST APIs

**What happened.** `analyticsGateway`/`forecastingGateway` serve no API
docs. Five throwaway projects and ~12 failed POST variants to find the
create contract, the variable/hierarchy PUT shapes, and the pipeline-from-
template body.

**Rules that worked.**
- Use an existing object as the answer key: GET it, change only the
  fields you mean to change, PUT it back with `If-Match`.
- Probe on throwaway objects named `zz … (delete me)`; delete at the end
  of the same run; sweep leftovers at the start of the next.
- Read error messages literally — "missing policy" and "Unsupported
  Representation Version 2" each pointed straight at the fix once the
  media-type version was right (`;version=3`).
- When a body must be the server's own object (template prototype), copy
  it byte-for-byte and append the override key; JSON parsers keep the
  last duplicate key.
- Write every confirmed contract into CLAUDE.md immediately, with the
  media types and the failure modes, so it is never rediscovered.

## F. Visual Forecasting specifics worth remembering

- Create needs `providerSpecificProperties` or the project lands in
  `creatingProviderError`; ~10 s later the provider has built the data
  definition and detected the time interval.
- BY vars need `role=byVar` **and** the hierarchy `varList`; the
  hierarchy is pre-created (PUT, not POST); `reconciliationLevel` is
  reset by the data load — set it afterwards.
- Every project comes with "Pipeline 1" (Auto-forecasting); rename with a
  JSON patch. Extra pipelines: POST the template prototype with
  `;version=3`.
- Comparison metrics: WAPE for cross-pipeline comparison; WMAPE misleads.
  Reconciliation level did not change the comparison numbers.
- On MFG, forcing the drivers in (Regression pipeline) beat Auto-
  forecasting: WAPE 3.94 % vs 5.48 % in-sample, 4.12 % vs 5.48 % with an
  8-week holdback. Jessica Curtis's custom RNN node halves that again
  (1.73 % / 2.75 %) — but it is also the model that degrades most out of
  sample, so it is the one to scrutinise per series.
- **`back` (holdback) is silently ignored at create time.** Every project
  starts with back=0 whatever `providerSpecificProperties` said — the
  first "holdback" project reproduced the in-sample numbers to the
  decimal, which is how it was noticed. Apply it after the load:
  `GET /forecastingGateway/projects/{id}/settings` → edit → `PUT` with
  `If-Match` (media type `…forecasting.project.settings+json`, 428
  without the ETag). The service enforces **back < horizon** (400 "must
  be less than"), so a 12-week horizon allows at most 11 weeks of
  holdback. Same lesson as reconciliationLevel: verify every setting by
  reading it back after the load.
- Renaming a *project* is a `PUT` of the full project document with
  `If-Match` (`PATCH` on `/analyticsGateway/projects/{id}` is 405);
  renaming a *pipeline* is a JSON patch. Different resources, different
  contracts.
- The Panel Series NN "autotune" option did not honour its 30-minute
  cap: the pipeline job was still running after two hours while every
  other pipeline finished in under a minute. Treat autotune as an
  offline experiment, never as part of a run-all batch, and always give
  `%viya_wait` a `max_wait`.
- Multistage Model with stock defaults produced WAPE 32 % (5× worse than
  naive) on this data. Node defaults are not a safe baseline for every
  node — check WMASE (> 1 = worse than naive) before reading anything
  else.
- Pipelines can be *composed*: edit a template's `prototype` (drop nodes
  and their connections, swap in another component template's prototype
  under the same component id), POST it, then configure the live
  components. Three layers of node settings exist and are easy to
  confuse: a **template prototype** has none; a **fresh component** has
  them at the top level of `componentProperties`; a **run component**
  wraps them in `_backendArgs`. `saveAsTemplate` turns a configured
  pipeline into a reusable template — that is how "our own templates"
  are made, not by hand-writing pipeline JSON.
- The placement endpoint (`POST …/pipelines/{id}/components`,
  `place.component.request`) rejected every body shape tried; composing
  prototypes made it unnecessary.

- **Cancelling a pipeline job can lock the whole project (found
  2026-08-28).** After the autotune job was killed with
  `DELETE /jobExecution/jobs/{id}`, the project kept
  `providerSpecificProperties.dataStatus="invalid"` while its data
  definition still reported `valid`. Consequences: the gateway withholds
  the `run` link from the project and every pipeline, and Model Studio
  opens the project **read-only for its owner** (everything viewable,
  including node results; nothing editable, no lock/share flag set,
  no stuck job). Nothing else differed from the editable projects. Fix:
  `GET` the project, set `dataStatus` to `valid`, `PUT` it back with
  `If-Match` → 200; the `run` links return and the UI unlocks on the
  next open. Rule: after any job cancel, read `dataStatus` and reset
  it; when a Model Studio project looks locked, diff its document
  against an editable one before hunting for locks.

- **Stock node names duplicate across pipelines (2026-08-28).** Composing
  one-node pipelines from a template keeps the template's node name, so
  two projects ended up with several "Panel Series Neural Network" nodes
  whose results, logs and job-list entries could not be told apart. Node
  name = model + distinguishing settings, set in the template so
  instantiation carries it (`starter/vf_nn_templates.py` SPECS). A
  rename is a `PUT` of the component with `If-Match` and does not
  invalidate results (keyed by component id).
- **Templates cannot be edited in place — and the transfer route silently
  breaks them (2026-08-28).** `PUT /analyticsGateway/pipelineTemplates/{id}`
  is metadata-only (200, revision bumps, prototype ignored; `;version=3`
  → 415). `transferExport` → edit the `v=1:`+base64+zlib content →
  `transferImportUpdate` does rewrite the prototype and reads back fine,
  but the transfer content has no `derivedFrom` links (component →
  component template), so every later instantiation of that template
  fails with HTTP 500 — the five MCP templates were broken this way for
  about an hour and recreated with new ids. Diagnosis that found it: the
  pre-rewrite JSON from git instantiated (201), the server copy did not;
  the only difference was the missing `derivedFrom` link, and grafting
  the links back into the posted JSON made it instantiate again. Rule:
  change a template by editing `starter/vf_nn_templates.py`, deleting and
  recreating; never through the transfer pair.
- **Keep the prototype `id` when instantiating a template (2026-08-28).**
  `POST …/pipelines` with the template `prototype` *including its `id`*
  → the gateway clones the saved prototype pipeline, settings included.
  With the `id` stripped it builds from the JSON alone: right nodes,
  right names, **stock settings** (holdout 0, 0 tries, 10 neurons; the
  custom RNN node with no properties at all) — and no error, so it looks
  like "the template lost its settings". The builder and the factory
  post the raw prototype text (id kept), which is why every project
  built by them has the configured nodes; the day's Python probes
  popped the id and produced an hour of wrong diagnoses (including a
  retracted claim that templates saved from *run* pipelines lose their
  settings — they don't, that probe had popped the id too). Rule: after
  any instantiation, read one node's settings back before trusting it.
- **Composing a multi-node pipeline (2026-08-28).** Adding a node to a
  *saved-template* prototype fails with a bare 500; adding one to Jim's
  "Machine Learning" prototype (`4942334c…`, three modelling nodes) works
  — the RNN component-template prototype with a fresh uuid, wired Data →
  node → Model Comparison, → 201 with four nodes. Configure the fresh
  nodes by `PUT` (same edits as the factory), name them, save as
  template *then* run. Result "MCP - Neural Networks": the in-pipeline
  Model Comparison lists all four (RNN 1.91, Stacked 6.11, Panel 6.28,
  Multistage 35.9 % MAPE) and its champion equals the single RNN
  pipeline (1.73 % WAPE) — the combined view costs nothing in accuracy,
  only visibility of the losers in the project-level table.

## G. Data readiness earned its keep

Four decisions were settled by the readiness output rather than guessed:
missing = horizon rows (not zeros), duplicates are real records (sum
them), Region/Plant are attributes, regressors cover the horizon. Keep
the program at its current size; extend only when a new dataset shows a
class of problem it misses.

## H. Documentation versions

**What happened.** The first Visual Forecasting guide I found and quoted
was the 2023.04 edition; the tenant runs LTS 2026.03. Ross caught it.
The Help Center's `v_NNN` collection numbers are opaque, the HTML pages
are unreachable to a non-browser client, and the PDF API refuses requests
without a browser user-agent — so "search, click, read" doesn't transfer
to an agent.

**Rules.** Know the tenant release before reading docs; map `v_NNN` to
editions by reading PDF covers, never by assumption; fetch PDFs with a
browser UA; save the extract with the edition in the file name; cite the
edition. Tool: `starter/sasdoc.py`; method: `docs/sas-documentation-
lookup.md`. Communities articles drift from the product — confirm against
the guide.

## I. Working together

Discuss design before building; pointed capability questions deserve
evidence from the live tenant, not assumptions. Keep every artifact
parameterised so a mid-stream change (CASUSER -> PUBLIC -> DB_DEMO) is a
one-line edit. Reuse the POC 1/2 deck template for anything visual rather
than inventing a design. Record decisions with reasons as they are made.

## J. Neural-network nodes — what worked, what didn't, how to run them next time

Evidence: MFG demand sensing, 533 weekly series, 123 observed weeks, six
macro drivers; main project in-sample and a validation project with an
8-week project holdback (2026-08-27). Settings names are in
`docs/reference-vf-nn-node-properties-2026.03.txt`; the guide text is in
`docs/reference-vf-modeling-nodes-2026.03.txt`.

**What is on the tenant (LTS 2026.03).** Stock: Panel Series Neural
Network (`forecasting-modeling-nn-1`), Stacked Model NN + TS
(`-stacked-nn-ts-1`), Multistage Model (`-multistage-1`), plus the
Distributed Open Source Code node for Python/R. Custom (Jessica Curtis):
"RNN Forecasting ASTM" — a **SAS-code component** (`code_Language:
text/vnd.sas.source.sas`, PROC TSMODEL underneath) whose settings are
flat `_name` properties. That is the proof that a custom TSMODEL node
is a SAS program plus a validation model (the property form) — the
route for our own "demand sensing with leading indicators" node.

**Results, ranked (WAPE in-sample / holdback 8).**
RNN 1.73 / 2.75 · Regression 3.94 / 4.12 · Auto 5.48 / 5.48 · Stacked
5.67 / 5.78 · Panel 5.79 / 6.05 · Hierarchical 5.85 / 5.92 · Machine
Learning (defaults) 6.08 / 5.99 · Multistage (defaults) 32.0 / 32.2.

**Lessons.**

1. **Feed-forward NNs did not beat a regression with the same drivers.**
   Tuning the Panel/Stacked nodes (ESM forecast as input, dependent and
   driver lags 4, weekly seasonal dummies, 1 × 20 tanh, 5 tries, 500
   iterations, holdout 12) moved WAPE from 6.08 % to 5.7–5.8 %: the
   settings matter far less than the model family. With ~120 points per
   series and drivers that are identical for every series in a week,
   there is little for a panel network to learn that a regression with
   the drivers does not already capture. Try Regression first; treat the
   feed-forward nodes as a confirmation, not a hope.
2. **The RNN node is not "an RNN" — it is a per-series selection.** Its
   properties include `_esmInclude=true`, `_arimaxInclude=true`,
   `_selectionCriteria=MAPE` and `_holdoutSampleSize=12`: for every
   series it fits an LSTM (`_rnntype=LSTM`, `_nlayer=3`, `_nneuronh=10`,
   `_maxepochs=100`, `_warmupepochs=20`, ADAM, `_normalize=STD`) *and*
   ESM/ARIMAX, then keeps the best on the last 12 weeks. Its 1.73 % is
   therefore partly a "best of three on holdout" effect, and it is the
   model that loses most when weeks are withheld (+1.0 point vs +0.2 for
   Regression). Before quoting it: read the node's OUTSTAT/OUTMODELINFO
   to see how many series actually chose the LSTM, and look at the
   2025-start series (5–9 weeks) where an LSTM has nothing to learn from.
3. **Node holdout ≠ project holdback.** `holdoutSampleSize` on a node
   only steers that node's model selection; the comparison table's
   statistics come from the project's `back`. Comparing a node with
   holdout 12 against nodes with no holdout in a `back=0` project is not
   like for like. For an honest ranking, build the validation project
   with `back` set (and remember back < horizon) and read the
   comparison there.
4. **Autotune is not batch-safe.** Panel NN with `autotuneEnabled`
   (5 iterations, `maxTime` 30 min) was still running after two hours
   and had to be cancelled; every other node finished in 15–60 s. If
   autotune is wanted, run it alone, off the critical path, and never in
   a `run_pipelines=all` batch. The Stacked node has no autotune block
   at all — tolerate missing keys when applying settings.
5. **Defaults are not a baseline for every node.** Multistage with stock
   defaults gave WMASE 4.8 (five times worse than naive). Its settings
   are two feature-extraction stages (`_fx1Model`/`_fx2Model` ∈ TSMODEL,
   REGRESSION, NEURALNET; `_stg1HighLvlNum`/`_stg1LowLvlNum` hierarchy
   levels; `_regByLvlNum*`) that must be aligned with the hierarchy —
   not investigated further; dropped. Check WMASE first on any new node:
   > 1 means worse than naive, look for a configuration error before
   reading anything else.
6. **One node per pipeline.** The project comparison shows only each
   pipeline's champion, so a three-node "Machine Learning" pipeline
   hides two of its results. Single-node pipelines (Data → node → Model
   Comparison → Output) put every method on its own row, and at 15–60 s
   per node the extra pipelines are free.
7. **Settings live in three places** (template prototype: none; fresh
   component: top-level `featureGeneration / modelGeneration /
   modelSelection`; run component: the same wrapped in `_backendArgs`;
   custom nodes: flat `_x`). Configure the *live* component with a PUT,
   verify with a GET, then `saveAsTemplate`; re-instantiate once and
   read the settings back — that proves the template is complete.
   `starter/vf_nn_templates.py` does exactly this and is resumable when
   the tenant drops connections.
8. **Guide first, articles second.** The 2026.03 guide says Panel NN
   supports 0–2 hidden layers and LBFGS/SGD; older community articles
   quote different limits. `python starter\sasdoc.py match vfcdc vfug
   <release>` finds the matching edition.

**Recommended NN pass for the next dataset** (after Regression and Auto
are in): instantiate `MCP - NN Panel Series (holdout 12, 5 tries)`,
`MCP - NN Stacked NN+TS (holdout 12, 5 tries)` and `MCP - RNN
Forecasting (custom node, holdout 12)` (`templates/README.md`) into the
holdback project, run all in batch, read WAPE and WMASE, then decide
whether the network story is worth the explanation cost. Skip Multistage
and autotune unless there is time to configure them properly.

## K. Where the champion lives (no score code — verified 2026-08-27)

Visual Forecasting produces no DS2/ASTORE. The champion is per-series
model choices + estimates; "scoring" is re-running the champion pipeline.

1. **Node program.** `GET /analyticsComponents/components/{id}` → field
   `code` = the full PROC TSMODEL program the node ran (bound to the
   project caslib and `_backendArgs`); also filed as
   `<componentId>_vf_code.sas` in the Files service; run log and job are
   links on the component (`rel=log`, `rel=job`). UI: node → *Download
   SAS code*. A re-run script, not a portable scorer.
2. **Fitted models and outputs.** Caslib `Analytics_Project_<projectId>`
   (`/cas/data/apps/projects/forecasting-<id>/`). Tables are prefixed by
   the first 8 hex of the component id: `<XXXXXXXX>.OUTMODELINFO`
   (which model each series chose — the per-series RNN check),
   `.OUTSELECT`, `.OUTSTAT`, `.OUTFOR`, `.OUTSUM`, `.OUTLOG`; NN nodes
   add `.NNOUTMODEL` (weights) and `.NNOUTMODELINFO`; the hierarchical
   node writes `.L0…L5.*` per level; comparison nodes `.OUTCOMPARISON`.
   Map component id → pipeline via `GET …/pipelines/{pl}` (`;version=3`)
   Modeling lane. This is the source for `30_extract_results`.
3. **Operational re-scoring.** `GET /forecastingGateway/projects/{id}/batch/new-iteration?type=sas`
   returns `%vf_new_iteration(host, username, password, projectId,
   outputCaslib, outputTable)`: token → `PUT …/dataState?scope=input`
   → check `championPipelineDirty` → run champion pipeline → output
   table. UI: project → *Download batch code*. Step 40 should reuse the
   endpoints with `oauth_bearer=sas_services`, never a password.

Open with SAS: is there a supported export of a VF champion as a
portable artifact (ASTORE for NN nodes, model specs for TSMODEL) for
Model Manager, or is batch re-run the intended deployment? Is the
component `code` field a stable contract?

## L. Demand-sensing build (2026-08-27) — what it took to add two signals

**What happened.** Adding the order book and an event calendar to the
process was one prep program, a 4-line builder change, a rolling-origin
program and a third project — about three hours, most of it spent on
five traps that each cost a run:

| Trap | Symptom | Rule |
|---|---|---|
| An unbalanced double quote inside a macro definition (`prxchange("s/,"key":"[^"]*"//", …)`) | the `%include` "succeeds", nothing after it runs, no ERROR; the log ends in "quoted string … more than 262 bytes" notes | JSON patterns go in **single** quotes; a `%put NOTE: sentinel` after every include in batch code |
| Open-code `%if … %then %macro();` as an autorun | `ERROR: Expected %DO not found`, rest of the file skipped | wrap the autorun in a one-line macro (`%macro x_autorun; %if … %then %do; %x() %end; %mend; %x_autorun`) |
| FedSQL with a SAS libref (`inlib.table`) | "caslib INLIB does not exist" | FedSQL names **caslibs**; keep `&in_caslib..&in_table` for FedSQL and librefs for DATA steps |
| `outobj=(outfor=…)` in PROC TSMODEL | "No matching output table binding found for object of" | the key is the **object name** you declared (`of`), not the class |
| Trailing missing target with `lead=0` | the series is trimmed at the last non-missing week; no forecasts | mask the target after the origin and set `lead=` so the driver rows beyond it are used (that is how the VF horizon rows work too) |
| `selspec.Open()` / `diagnose.GetSelectSpec` | "Open requires 1 argument" / "does not support GETSELECTSPEC" | `ss.Open(10); ss.AddFrom(dg); ss.Close();` |
| 39-character output names | CAS accepts them, PROC SQL/`table.fetch` cannot read them; a promote can fail with "Invalid option name PROMOTE" | prefix + name ≤ 32 characters (`roll_stats`, `mfg_ds_readiness_*`) |
| A leakage test whose counts are blank | "test passed" printed after the step that should have filled the counts failed | test for blank/zero counts first and fail loudly |
| `%let origin_d = %sysfunc(inputn(…)) - 56;` | the macro variable holds the *text* `24131 - 56`; pasted into `(Date - &origin_d)` the sign flips and every lead is wrong, silently | `%eval()` any arithmetic you store in a macro variable |
| A plain `SET` over the JSON engine's per-component tables | `group` truncated to the first table's length, so `if group = 'modeling'` matched one node | declare lengths before the SET; better, keep every component and let the OUTFOR file list decide |
| `caslib prj path="/cas/data/apps/projects/…"` | "path is not in the allowlist" | the project caslib already exists: `incaslib="Analytics_Project_<id>"` |
| A failed custom node's `_OUTLOG` | not saved to the project caslib; only the wrapper's "OUTFOR table does not have any observation" survives | reproduce with the node's own `code` on a subset, or vary the inputs (events out → order book out) |
| Comparison-table WAPE vs leaf-level holdback WAPE | RNN 2.75 % on the table, 14 % with +12 % bias on the node's OUTFOR over the eight held-back weeks | score OUTFOR by lead yourself (`30_extract_results`) before quoting a champion; the table's region and level are still to be confirmed |

**What worked first time.** Two-stage `Orders_known` (actual within the
known window, ESM forecast beyond) per origin; the rolling-origin design
(stack one copy per origin, mask the target, one TSMODEL run per stage);
the per-variable `indep_accumulate=` list in the builder; the readiness
program on a prepared table with `exo_table=` blank.

**Result that matters.** Over 8 origins the order book cut weeks 1–4
WAPE from 6.8 % to 4.0 % and did nothing beyond week 4 — the sensing
horizon from the literature, reproduced. Quote the front of the horizon
only; never the whole 12 weeks.
