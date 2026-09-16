# Databricks Modeling Demo (MCP) — decision checklist

Config: `projects/databricks_demo.yml`. Each row is a judgment call the process
cannot automate; record the choice and the reason so the demo story and
the config stay in sync. Mark rows **decided** with a date; leave the
rationale even when it is short.

Rows 2-15 below were inherited from `sas-mcp-forecasting`'s forecasting
checklist and assume a Visual Forecasting use case. Rows 0-1 are the two
decisions that actually block progress right now; resolve them first —
they determine whether the rest of this table even applies.

| # | Decision | Status | Choice | Rationale / notes |
|---|---|---|---|---|
| 0 | Modeling scope | pending | | Forecasting (reuse the VF process) vs. something else (classification/regression via ML Pipeline Automation, or a hand-written CAS procedure). Blocks rows 2+. |
| 1 | Databricks connection details | decided (2026-09-08) | adb-2401595702726378 · default schema · token auth via DATABRICKS_AUTH | Verified via SAS MCP test program (sas/99_test_databricks_connection.sas). Available tables: CUSTOMER_PROFILE, FINANCIAL_TRANSACTIONS, HMEQ, AUTOLOAN_1, LOAN_DATA_SET_CSV, STATE_EXP, plus 15+ additional (sensor data, ML test sets). 
| 1b | Working copy location | decided | `DB_DEMO` via `target_caslib=` | Dedicated CAS library for Databricks demo assets. Confirm it is visible to this project's MCP connector identity. |
| 2 | Time interval / seasonality | pending | | Confirmed by the readiness check (gaps, weekday) |
| 3 | Target | pending | | One target per project in pass 1 |
| 4 | Missing target interpretation | pending | MISSING (pass 1) | Readiness: are missings leading / trailing (horizon rows) / interior? |
| 5 | Hierarchy order | pending | | Readiness: series count through each level; a level that adds no series is an attribute |
| 6 | Reconciliation | pending | middle-out at <level> | Where is the signal strongest vs. leaf sparsity? |
| 7 | Leading indicators as drivers | pending | | Only legitimate if future values are genuinely known at forecast time |
| 8 | Drivers (independents) | pending | | Accumulation rule; future values source; used in auto-generated models? |
| 9 | Horizon / holdback | pending | 12 / 0 (pass 1) | Re-run with holdback 8–12 before quoting accuracy |
| 10 | Comparison metric | pending | MAPE (provider default) | Compare pipelines on WAPE |
| 11 | Intermittent series treatment | pending | | Readiness: ADI > 1.32 count; all-zero series |
| 12 | Pipelines for pass 1 | pending | Auto-forecasting, Hierarchical Forecasting, Regression | Stock templates first; own template later |
| 13 | Model Studio project name | pending | "Databricks Modeling Demo (MCP)" | Pattern `<Business area> - <Target> Forecast (MCP)`; no version/date/"test" |
| 14 | Duplicate rows per series-period | pending | | Readiness: identical copies vs. different records → dedupe vs. accumulate |
| 15 | Series length / new-series waves | pending | | Readiness: short-series count; late starters |

## Pass 1 outcome

_(fill after the first build: project id, pipelines, comparison table on WAPE, one-paragraph reading, caveats)_

## Open questions for the business owner
- 
