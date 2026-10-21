# Viya Bridge web app

A UI for the Databricks Modeling Demo. It runs in two modes.

- **Live mode** (served by `server.py`): the buttons run real SAS on Viya.
- **Demo mode** (pages opened straight from disk, or the server not running): the original front-end-only behaviour, with simulated steps.

## Run live

1. `pip install -r webapp/requirements.txt`
2. In the repo `.env`, set a current `SAS_VIYA_TOKEN` and make `CAS_CLIENT_SSL_CA_LIST` (or `WEBAPP_CA_BUNDLE`) point at a CA file that exists on this machine. Optional: `WEBAPP_COMPUTE_CONTEXT` (default `SAS Studio compute context`).
3. Make sure `databricks_token.txt` in your SAS Content My Folder holds a current Databricks token (one line). SAS reads it at run time, this server never sees it.
4. `python webapp/server.py`, then open `http://127.0.0.1:4173`.

The badge on Connection Studio shows `Live` when the server and Viya both answer. If the token is rejected, the pages say so and keep working in demo mode.

## Renewing the Viya token

The Viya access token lasts about 12 hours. To renew it:

```
python starter/refresh_token.py
```

It writes `SAS_VIYA_TOKEN` in the repo `.env`, and the running server picks it up on the next request. The rotating refresh token is kept outside the repo in `~/.viya/`, so it cannot be committed. The first time, or if the refresh token has expired, the script prints a sign-in URL: sign in with your own account, tick `openid` and `uaa.user`, and paste the code shown. It needs a CA file (`WEBAPP_CA_BUNDLE` or `CAS_CLIENT_SSL_CA_LIST` in `.env`), or `--insecure` to skip TLS verification for the sign-in only.

## What is real in live mode

| Page | Button | What runs |
|---|---|---|
| Connection Studio | Test connection | Identity check and a compute session on Viya |
| Connection Studio | Load into Viya | Copies the chosen Databricks table into `CASUSER.WEB_<name>` (promoted) |
| Connection Studio | Explore readiness checks | Row counts, missing values and ranges per numeric column, in CAS |
| Collection Workflow | Generate join program | Loads the three chosen tables and joins them in CAS on the key into `CASUSER.WEB_<output>` |
| Collection Workflow | Run AutoML | Gradient boosting in CAS on the joined table (target `coll`, event `Y`, 70/30 split on `PRIMARY_KEY`), with validation AUC, KS and misclassification |
| Collection Workflow | Save scored dataset | Writes `CASUSER.WEB_CUSTOMER_RISK_SCORES` and a `.sashdat` copy |

The SAS for every button is in `sas/04_webapp_actions.sas`. Everything is written to the signed-in user's `CASUSER` caslib with a `WEB_` prefix.

## Not wired yet

- **Confirm write-back** does not write to Databricks. In live mode it says so. Writing into the customer's workspace needs an explicit sign-off first.
- **Build VA brief** only drafts text, it does not create a report.
- The model is a single gradient boosting model, not the Model Studio AutoML project. The "05 Live results" panel on the workflow page shows the earlier Model Studio run of 1 Oct 2026 and is labelled as such.
- The model step assumes the joined table has `PRIMARY_KEY` and the `coll` target, which fits the default CUSTOMER_PROFILE, ACCOUNT_SUMMARY and FINANCIAL_TRANSACTIONS tables.

## Current slice

- Switch between SAS/ACCESS to Spark, JDBC, and native CAS action recipes.
- Edit connection and table settings, then generate SAS code.
- Copy or download the generated `.sas` file.
- Simulate a Viya handshake and browse a sample data catalog.
- Filter available assets by name.

Tokens and tenant URLs stay on the server, never in the browser.
