# SAS Viya + Databricks Demo

This project is a collection demo built with SAS MCP and Claude. It shows how customer, account, and payment data coming from Databricks can move through SAS Viya for preparation, reporting, risk modeling, and operational follow-up.

## Three web experiences

The web experience is organized as three connected screens:

1. **Landing page** (`landing-page.html`) introduces the Databricks-to-Viya architecture and links to the two working screens.
2. **Connection Studio** (`webapp/index.html`) presents the connection options, including SAS/ACCESS to Spark, JDBC, and CAS. Users can configure source and target tables, generate SAS code, copy or download it, test the simulated handoff, and browse available data assets.
3. **Collection Workflow** (`webapp/workflow.html`) guides the customer analytics journey. Users select three tables from the `DB_TEST` library, generate a SAS Studio join program, choose a collection report, run a simulated AutoML flow, save customer risk scores, and approve a write-back request to Databricks.

Together, the screens tell the story from Databricks data to SAS Viya insight: connect, prepare, understand, score, and return the result.

## What this project is doing

The goal is to show a realistic pattern for data movement between a lakehouse platform and a SAS analytic environment:

- Databricks holds the source data and catalog
- SAS Viya reads the data through a supported connection pattern
- the data lands in a CAS library such as `DB_DEMO`
- the data is then profiled, validated, and prepared for modeling or analytics workflows

This project demonstrates the SAS perspective on that connection through lightweight web interfaces that generate SAS code and show the shape of the end-to-end flow.

## Why this matters

Many customers want to keep their raw data in Databricks while using SAS Viya for analytics, scoring, forecasting, or model development. The challenge is not only connectivity, but also making the connection clear, governable, and safe.

This repo is focused on the connection design and data handoff:

- keep credentials out of browser code
- generate SAS connection recipes from a UI
- show how a Databricks table can be staged in CAS
- prepare for readiness checks, profiling, and model development

## Architecture and workflow

The concept is:

1. Databricks stores data in tables or a lakehouse schema.
2. SAS connects to the Databricks endpoint using supported methods such as SAS/ACCESS to Spark, JDBC, or native CAS patterns.
3. The data is loaded into a CAS library used for analytics and data prep.
4. Visual Analytics can present portfolio and collection views.
5. Model Studio can identify a champion model and produce customer risk scores.
6. The saved scores can be prepared for return to Databricks.

A common flow looks like this:

```text
Databricks tables
      ↓
SAS compute session
      ↓
CAS library (`DB_TEST`)
      ↓
SAS Studio join / Visual Analytics / Model Studio
      ↓
Customer risk scores / Databricks write-back
```

## Included in the repo

- `landing-page.html` - overview of the demo architecture and entry points
- `webapp/index.html` - Connection Studio for configuring and previewing SAS connection code
- `webapp/workflow.html` - Collection Workflow for joining data, selecting reports, modeling, and write-back decisions
- `webapp/workflow.css` and `webapp/workflow.js` - styling and interactions for the Collection Workflow
- `sas/` - SAS code for loading data and data readiness checks
- `projects/` - project-level metadata and configuration
- `notes/` - decision log and design rationale
- `docs/` - supporting documentation and project notes

## Security note

This repo intentionally keeps secrets out of the browser and out of generated SAS code. The production pattern is to resolve credentials through the SAS server or a secure auth configuration, not by hard-coding tokens into UI or code.

## How to run the web app locally

From the repository root, start a local static server:

```powershell
cd C:\SAS\sas-databricks-demo
python -m http.server 4173
```

Then use:

```text
http://localhost:4173/landing-page.html
http://localhost:4173/webapp/index.html
http://localhost:4173/webapp/workflow.html
```

## Practical use cases

This setup is useful for scenarios such as:

- loading Databricks data into CAS for analysis
- profiling and validating tables before modeling
- preparing a lakehouse dataset for SAS ML or forecasting workflows
- demonstrating a secure architecture between Databricks and SAS Viya
- prioritizing customer outreach using risk-based collection insights

## Notes

This is a demo-focused project and intentionally keeps some configuration placeholders in place. The goal is to make the architecture easy to understand and to provide a practical starting point for connected analytics work.

## Related links

- GitHub repo: https://github.com/thedjlorr/sas-databricks-demo
- web app: http://localhost:4173/

