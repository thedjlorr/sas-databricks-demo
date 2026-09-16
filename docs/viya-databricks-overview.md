# Viya and Databricks: what this project is demonstrating

This project is a concept and demo for connecting Databricks to SAS Viya with a clear and practical data movement pattern.

## The business problem

Modern teams often keep operational and analytical data in Databricks, while SAS users want to run analytics, governance checks, forecasting, and model work in Viya. The problem is not whether the two systems can connect. The harder question is how to connect them in a way that is secure, understandable, and aligned with the customer workflow.

## The pattern in this project

The project shows a simple architecture:

- Databricks is the source platform
- SAS Viya becomes the analytics and model platform
- the connection is established through a supported SAS-to-Databricks method
- data is loaded into a CAS library so SAS can work with it efficiently

This is meant to mimic the real-world pattern customers often ask for when they want a lakehouse + analytics stack without leaving their Databricks data in place.

## Why CAS matters

CAS is the analytical engine used by Viya. Once data is in a CAS library, the project can:

- profile tables
- review missing values and key coverage
- check duplicates and data quality
- prepare a modeling-ready dataset
- feed the data into SAS analytical workflows

The project is not trying to do all of that yet. It is first establishing the connection and the load path.

## Connection styles demonstrated

The UI and project materials show a few realistic connection routes:

- SAS/ACCESS to Spark
- JDBC-based access
- native CAS route patterns

The user can compare the generated SAS code for each approach and see how the connection contract changes between methods.

## Why the project keeps credentials out of the browser

A key design rule is that the browser should never hold a real token or secret. In a real deployment, the actual credentials should be resolved on the SAS compute server or through secure enterprise auth patterns.

This protects users and allows a cleaner separation between:

- browser UI configuration
- compute-side access to secure resources
- CAS loading and processing

## What comes next

This repo is a foundation for the following stages:

1. verify the connection to the live Databricks workspace
2. load sample tables into a CAS library
3. run readiness checks for completeness, uniqueness, and quality
4. prepare a modeling path for a selected business problem

The project is deliberately framed as a demo and a concept, not as a finished production deployment.

## In one sentence

This project demonstrates how SAS Viya can connect to Databricks data, land it into CAS, and prepare the analytics workflow without exposing credentials or burying the data-hand-off logic in a black box.
