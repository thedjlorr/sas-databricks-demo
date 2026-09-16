# Viya Bridge web app

A lightweight concept UI for the Databricks Modeling Demo. It is intentionally frontend-only: it demonstrates the SAS perspective and keeps credentials out of the browser.

## Run locally

From this folder, use any static web server. For example:

```powershell
python -m http.server 4173
```

Then open `http://localhost:4173`.

## Current slice

- Switch between SAS/ACCESS to Spark, JDBC, and native CAS action recipes.
- Edit connection and table settings, then generate SAS code.
- Copy or download the generated `.sas` file.
- Simulate a Viya handshake and browse a sample data catalog.
- Filter available assets by name.

The real Viya integration should be added behind a server-side API. Tokens, auth domains, and tenant URLs should never be sent directly from this UI.
