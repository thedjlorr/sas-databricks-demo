# Web app concept

## Purpose

Viya Bridge is the interaction layer for the Databricks Modeling Demo. Its job is to make the SAS connection model understandable and useful before a live Viya tenant is wired in.

The first screen follows the real workflow:

1. Choose a connection route: SAS/ACCESS to Spark, JDBC, or a CAS action.
2. Set the connection and destination parameters.
3. Generate reviewable SAS code without exposing credentials.
4. Test the handoff to Viya.
5. Browse the data assets that are available in the working CAS library.

## Next capabilities

- **Secure Viya gateway:** a small backend that exchanges a user session for a short-lived Viya connection and runs approved operations.
- **Schema inspector:** click a table to see columns, types, sample rows, missingness, and key candidates.
- **Readiness report:** run reusable checks for row counts, duplicate keys, date coverage, missing targets, and future-driver availability.
- **SAS run console:** submit a generated program, stream the log, and preserve the result as a named artifact.
- **Modeling handoff:** choose a target and time variable, then produce the project YAML and readiness inputs used by the SAS programs in this repo.
- **Connection recipes:** save named templates for Spark, JDBC, or CAS with auth domains only, never raw tokens.
- **Explain the bridge:** show the same operation as SAS code, REST calls, and CAS actions so the demo teaches the architecture as well as performing it.

## Integration boundary

The browser should call a server-side API such as `/api/viya/catalog` and `/api/viya/run`. The server owns OAuth, certificates, auth domains, input validation, and allow-listed SAS programs. The browser can preview generated code, but it should not execute arbitrary SAS submitted by an untrusted user.

## Design direction

The app uses a quiet workbench layout with a warm paper surface, sage operational status, coral actions, and a monospace layer for code and connection metadata. It is designed to feel like a technical instrument rather than a marketing landing page.
