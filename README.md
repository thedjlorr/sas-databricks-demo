# SAS Viya + Databricks Demo

This project is a working demo for connecting Databricks data to SAS Viya and landing that data into a CAS library for exploration, profiling, and downstream modeling.

## What this project is doing

The goal is to show a realistic pattern for data movement between a lakehouse platform and a SAS analytic environment:

- Databricks holds the source data and catalog
- SAS Viya reads the data through a supported connection pattern
- the data lands in a CAS library such as `DB_DEMO`
- the data is then profiled, validated, and prepared for modeling or analytics workflows

This project demonstrates the SAS perspective on that connection, including a lightweight web UI that generates SAS code and shows the shape of the flow.

## Why this matters

Many customers want to keep their raw data in Databricks while using SAS Viya for analytics, scoring, forecasting, or model development. The challenge is not only connectivity, but also making the connection clear, governable, and safe.

This repo is focused on the connection design and data handoff:

- keep credentials out of browser code
- generate SAS connection recipes from a UI
- show how a Databricks table can be staged in CAS
- prepare for readiness checks, profiling, and model development

## Architecture

The concept is:

1. Databricks stores data in tables or a lakehouse schema.
2. SAS connects to the Databricks endpoint using supported methods such as SAS/ACCESS to Spark, JDBC, or native CAS patterns.
3. The data is loaded into a CAS library used for analytics and data prep.
4. The project can then run profiling checks or model-ready workflows.

A common flow looks like this:

```text
Databricks table
      ↓
SAS compute session
      ↓
CAS library (for example: DB_DEMO)
      ↓
Readiness checks / modeling / reporting
```

## Included in the repo

- `webapp/` - a small front-end concept UI showing a Databricks-to-Viya connection flow
- `sas/` - SAS code for loading data and data readiness checks
- `projects/` - project-level metadata and configuration
- `notes/` - decision log and design rationale
- `docs/` - supporting documentation and project notes

## Security note

This repo intentionally keeps secrets out of the browser and out of generated SAS code. The production pattern is to resolve credentials through the SAS server or a secure auth configuration, not by hard-coding tokens into UI or code.

## How to run the web app locally

From the project root:

```powershell
cd webapp
python -m http.server 4173
```

Then open:

```text
http://localhost:4173/
```

## Practical use cases

This setup is useful for scenarios such as:

- loading Databricks data into CAS for analysis
- profiling and validating tables before modeling
- preparing a lakehouse dataset for SAS ML or forecasting workflows
- demonstrating a secure architecture between Databricks and SAS Viya

## Notes

This is a demo-focused project and intentionally keeps some configuration placeholders in place. The goal is to make the architecture easy to understand and to provide a practical starting point for connected analytics work.

## Related links

- GitHub repo: https://github.com/thedjlorr/sas-databricks-demo
- web app: http://localhost:4173/

