# NMAC Collections on Viya and Snowflake (demo app)

Two modes.

- **Static**: open `index.html` in a browser. Deck figures and the real Snowflake table list.
- **Live**: `python snowflake-webapp/server.py`, then open http://127.0.0.1:4174. The badge shows `Live: <your id>` when Viya answers. Renew an expired token first with `python starter/refresh_token.py`. Needs the packages in `webapp/requirements.txt`.

## How the app connects to SNOWLIB

Browser -> `server.py` (Viya token from `.env`, never sent to the browser) -> Compute REST job on Viya -> `sas/05_snowflake_webapp_actions.sas` -> CAS -> `SNOWLIB` caslib -> Snowflake. Snowflake credentials are held by the caslib on the tenant, so this app never handles them.

| Button | What runs |
|---|---|
| Architecture: Test SNOWLIB connection | Pass-through query, Snowflake returns its version, user, role, warehouse and clock |
| Architecture: Load the loan tables into Viya | Loads NMAC_AUTO_LOANS and NMAC_AUTO_SNAPSHOT into CASUSER; Snowflake counts loans and customers for comparison |
| Snowflake data: Refresh from Snowflake | Reads INFORMATION_SCHEMA (about 30 seconds); clicking a table also reads its columns |
| Report tabs: Score in Viya now | Gradient boosting PD model, risk bands, and the tier, band, heatmap, dealer, worklist, outlook and driver tables |

Everything written goes to your CASUSER as `WEB_SF_*`. Nothing is written to Snowflake.

## Data and model

Synthetic NMAC-style auto loan book (8,853 loans, 7,500 customers, 60 dealers) in three Snowflake tables, built by `sas/06_nmac_auto_data.sas`. A gradient boosting model trained on past snapshots scores the live book at 30 Sep 2026. It is split by customer and gets a validation AUC of about 0.80, with predicted default rates matching actual by credit tier. The ETS forecast runs on the 36 months in `NMAC_AUTO_MONTHLY`. Expected loss uses an assumed 50% loss given default. Write-back creates `NMAC_AUTO_SCORES` (not written yet).

Tabs: Snowflake data, Architecture (with the write-back panel), Portfolio overview, 12-month outlook, ETS forecast, Risk heatmap, Risk drivers, Dealer view, Collector worklist.

## Where things come from

- `static_data.js`: saved results of `%sf_score` and `%sf_forecast` (27 Oct 2026), shown when the server is not running. `data.js`: Snowflake table list and architecture. `code.js`: the SAS shown under each tab.
- `assets/nissan_logo.png`: the Nissan logo supplied by the user (143 px wide, replace with a larger file if one is available).
