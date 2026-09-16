# templates/

Exported Model Studio pipeline templates, version-controlled so the
process is portable to another Viya tenant. Each `pipeline_*.json` is the
full template document (`GET /analyticsGateway/pipelineTemplates/{id}`)
including the `prototype` with the configured node settings.

## Saved on the tenant (recreated 2026-08-28) — instantiate with `add_templates=`

| Template id | Name | Node name (stock node) and settings |
|---|---|---|
| `e08cf376-57ff-418a-8bc4-0a3566d81424` | MCP - NN Panel Series (holdout 12, 5 tries) | **Panel NN (holdout 12, 5 tries)** (Panel Series Neural Network): dep/indep lags 4, ESM input, weekly seasonal dummies, 1 hidden layer × 20 tanh, 5 tries, max 500 iters, holdout 12 |
| `436884f0-afbd-4523-837d-340bb4f495c9` | MCP - NN Panel Series (autotune) | **Panel NN (autotune)**: as above + autotune on (5 iterations, 30 min cap) |
| `060cd1c4-b96a-47cb-b2c8-a2700fe90636` | MCP - NN Stacked NN+TS (holdout 12, 5 tries) | **Stacked NN+TS (holdout 12, 5 tries)** (Stacked Model (NN + TS)): same features/training as Panel; no autotune block on this node |
| `989bff9c-1ca2-41e9-8163-f6b1dfcfa961` | MCP - NN Multistage (defaults) | **Multistage NN (defaults)** (Multistage Model), stock defaults |
| `861ad38b-a279-44e4-b858-789cf5d9ac43` | MCP - RNN Forecasting (custom node, holdout 12) | **RNN LSTM/ESM/ARIMAX (holdout 12)** (Jessica Curtis's custom RNN Forecasting ASTM node: ADAM, 3 layers × 10, 100 epochs, ESM/ARIMAX fallback), holdout 12 |
| `106b624e-6cae-49c7-8eff-607e368acfa7` | MCP - Neural Networks | **all four NN nodes in one pipeline** — Panel NN (holdout 12, 5 tries), Stacked NN+TS (holdout 12, 5 tries), Multistage NN (defaults), RNN LSTM/ESM/ARIMAX (holdout 12) → one Model Comparison. Review view: the pipeline's Model Comparison results list the four side by side. Composed from Jim's "Machine Learning" prototype + the custom RNN component template; autotune deliberately left out. `pipeline_nn_combined.json` |

**Instantiating a template: keep the prototype `id` (2026-08-28).** `POST
…/projects/{p}/pipelines` with the template's `prototype` object *including
its `id`* makes the gateway clone the saved prototype pipeline — node
settings included. Strip the `id` and the gateway builds the pipeline from
the JSON alone: same nodes, same names, **stock settings** (holdout 0, 0
tries, 10 neurons; the custom RNN node arrives with no properties at all).
The SAS builder and the factory keep the id (they post the raw prototype
text); the day's Python probes popped it and produced an hour of false
"template lost its settings" diagnoses. Always read a node's settings back
after instantiating.

**Node naming rule (2026-08-28):** node name = model + the settings that
distinguish it; pipeline name = `MCP - ` + the same idea. Never leave the
stock node name when the same node type appears in more than one pipeline
of a project — node results, node logs and the Job Execution list
(`Analytics "<node name>" Component`) show only the node name, so two
"Panel Series Neural Network" nodes are indistinguishable there. Results
themselves are keyed by component id, so a rename never invalidates a run.

**A saved template cannot be edited in place — recreate it (2026-08-28).**
`PUT /analyticsGateway/pipelineTemplates/{id}` updates metadata only
(name/description; the prototype is ignored under every media type).
The transfer pair (`transferExport` → edit the `v=1:`+base64+zlib content
→ `transferImportUpdate`) *does* rewrite the prototype, but the transfer
content carries no `derivedFrom` links, so the rebuilt components lose
their link to the component template and every instantiation of the
template then fails with HTTP 500 — that is how the 2026-08-27 set was
broken and had to be recreated (ids changed). To change anything in a
template: edit `SPECS` in `starter/vf_nn_templates.py`, delete the old
template (`DELETE …/pipelineTemplates/{id}`, `Accept: */*`), re-run the
factory, and update the ids in `projects/*.yml`, `CLAUDE.md`,
`docs/playbook.md`, `app/server.py` and this file. Node *names* and settings both travel
into a template (saved from a fresh or a run pipeline — the combined
template was saved from a configured, unrun pipeline and re-instantiates
correctly when the prototype `id` is kept, see below). Renaming a node in
a live pipeline stays a plain component `PUT`
(`starter/vf_template_rename_node.py --project …`).

All five are single-modelling-node pipelines (Data → node → Model
Comparison → Output) so each method gets its own row in the project's
pipeline comparison.

## Which ones to use (MFG evidence, 2026-08-27)

| Template | WAPE in-sample / holdback 8 | Verdict |
|---|---|---|
| MCP - RNN Forecasting (custom node, holdout 12) | 1.73 % / 2.75 % | **use** — champion; per-series LSTM vs ESM/ARIMAX pick on a 12-week holdout, so check how many series chose the LSTM |
| MCP - NN Stacked NN+TS (holdout 12, 5 tries) | 5.67 % / 5.78 % | use as confirmation — did not beat Regression (3.94 % / 4.12 %) |
| MCP - NN Panel Series (holdout 12, 5 tries) | 5.79 % / 6.05 % | use as confirmation — same |
| MCP - NN Panel Series (autotune) | never finished (> 2 h, cancelled) | **not in batch runs**; experiment only |
| MCP - NN Multistage (defaults) | 32 % / 32 % | **do not use as is** — stages need configuring against the hierarchy |
| MCP - Neural Networks (combined) | 1.73 % in-sample (its champion = the RNN node; inside: RNN 1.91, Stacked 6.11, Panel 6.28, Multistage 35.9 % MAPE) | **use for review** — one pipeline, one Model Comparison listing all NN nodes; the project table shows only its champion, so keep the per-model pipelines for the ranking |

Reasoning and settings detail: `docs/lessons-learned.md` §J.

## How they were made

`starter/vf_nn_templates.py` (from the scratch script used on
2026-08-27): take a template's `prototype`, keep one Modeling node (or
swap in a component template's prototype under the same id), POST it to
a throwaway project with `;version=3` media types, `PUT` the live
component's `componentProperties` with the chosen settings, verify,
`POST /analyticsGateway/pipelineTemplates?application=forecasting` with
the pipeline JSON, re-instantiate once to confirm the settings persisted,
delete the throwaway. Idempotent by template name; retries on dropped
connections.

## Re-import on another tenant

`POST /analyticsGateway/pipelineTemplates` (importPipelineTemplate) with
the JSON; component templates referenced inside (e.g. the custom RNN
node) must exist there first (`POST /analyticsGateway/componentTemplates`).

Mirrored at SAS Content `/Demo/MCP_Forecasting/templates`.
