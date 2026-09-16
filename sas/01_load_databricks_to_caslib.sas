/*--------------------------------------------------------------------------
  01_load_databricks_to_caslib.sas
  Project : Databricks Modeling Demo (MCP)  (process step 1)
  Purpose : Connect to a Databricks workspace via SAS/ACCESS Interface to
            Spark and load a table into a CAS caslib as a PROMOTED
            (global) table, optionally saved to disk so it survives a CAS
            restart. Mirrors the "copy working data into a caslib the MCP
            connector can see" pattern from sas-mcp-forecasting's
            01_copy_*_to_caslib.sas, but the source is Databricks/Spark
            instead of another caslib.

   STATUS  : Connection endpoint values below reflect the current
                  Databricks cluster. Update them when the cluster changes.
                  The access token is deliberately not stored in this file.

  Auth    : SAS/ACCESS to Spark against Databricks typically authenticates
            with UID="token" and PWD=<personal access token>. NEVER hard-
            code the token here. Options, in order of preference:
              (a) an authinfo/netrc file readable only by the SAS session
                  user (AUTHDOMAIN= on the LIBNAME statement), or
              (b) a macro variable populated from a Viya-side secret store
                  at session start (not from this repo's local .env — that
                  file is for the local SWAT/REST fallback only and is
                  never read by code running in the compute/CAS session).
            Whichever is chosen, record the mechanism in
            notes/databricks_demo_decisions.md once decided.

  Config  : keyword parameters of %load_from_databricks. No defaults are
            meaningful yet (see STATUS) — fill them in, or override per
            call, once the workspace details are known.
  Runs in : SAS Studio or MCP execute_sas_code (compute + CAS)
--------------------------------------------------------------------------*/

%macro load_from_databricks(
   /* --- Databricks / Spark connection --- */
   dbx_server       = adb-2401595702726378.18.azuredatabricks.net, /* no https:// */
   dbx_port         = 443,
   dbx_http_path    = sql/protocolv1/o/2401595702726378/0619-124631-x9a7aboi,
   dbx_schema       = default,
   dbx_authdomain   = DATABRICKS_AUTH,          /* authinfo AUTHDOMAIN= entry; token from authinfo or .env */
   dbx_properties   = EnableArrow=0,

   /* --- source table + destination in CAS --- */
   source_table     = CUSTOMER_PROFILE,         /* table/view in the Databricks schema (override per call if needed) */
   target_caslib    = DB_DEMO,                  /* where the promoted copy goes */
   target_table     = CUSTOMER_PROFILE,         /* name of the promoted CAS table */
   save_to_disk     = 1                           /* 1 = also write a .sashdat file */
);

cas mysess;
libname tgt cas caslib="&target_caslib" sessref=mysess;

/* Compute-side connection to Databricks via SAS/ACCESS Interface to Spark.
   PROPERTIES= syntax verified against active Databricks workspace;
   EnableArrow=0 required to avoid binary/timestamp compatibility issues. */
libname dbx spark platform=databricks
   server="&dbx_server"
   port=&dbx_port
   schema="&dbx_schema"
   user="token"
   authdomain="&dbx_authdomain"
   httpPath="&dbx_http_path"
   properties="&dbx_properties"
;

/* 0. Drop any previous promoted copy so the run is repeatable */
proc casutil incaslib="&target_caslib";
   droptable casdata="&target_table" quiet;
quit;

/* 1. Read from Spark, write into CAS, promoted to global scope.
      NOTE: this is a single-pass DATA step copy across engines, not a
      parallel CAS load — fine for a demo-sized table; for a large table,
      check whether the tenant has a CAS data connector for Spark/
      Databricks configured (a caslib of the appropriate source type),
      which would let CAS read it directly instead of routing through
      compute. */
data tgt.&target_table (promote=yes);
   set dbx.&source_table;
run;

/* 2. Persist to disk so it survives a CAS restart */
%if &save_to_disk %then %do;
proc casutil incaslib="&target_caslib" outcaslib="&target_caslib";
   save casdata="&target_table" casout="%lowcase(&target_table).sashdat" replace;
quit;
%end;

/* 3. Verify */
proc cas;
   table.tableInfo caslib="&target_caslib" name="&target_table";
   %if &save_to_disk %then %do;
   table.fileInfo  caslib="&target_caslib" path="%lowcase(&target_table).sashdat";
   %end;
run;
quit;

%put NOTE: [load] Databricks &dbx_server..&dbx_schema..&source_table -> &target_caslib..&target_table (promoted%sysfunc(ifc(&save_to_disk,%str( + saved),)));

libname dbx clear;
cas mysess terminate;
%mend load_from_databricks;

/* Do not autorun until dbx_authdomain is configured (or pass it as an
   override). Update the endpoint defaults above when the cluster changes. */
/* %load_from_databricks() */
