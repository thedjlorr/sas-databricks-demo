/*--------------------------------------------------------------------------
  00_create_db_demo_caslib.sas
  Project : Databricks Modeling Demo (MCP)  (process step 0)
  Purpose : Create the DB_DEMO caslib as a global CAS data connector to the
            Databricks schema, so CAS can see the Databricks tables without
            routing through compute. Re-runnable: drops DB_DEMO first.

  Auth    : The Databricks personal access token is read at run time from a
            one-line text file in your private SAS Content "My Folder"
            (default /Users/<you>/My Folder/databricks_token.txt), exactly as
            in 99_test_databricks_connection.sas. It is never written in this
            program, and logging of resolved macro text is switched off while
            the caslib is defined. See the header of that program for the
            one-time setup.

  Notes   : DB_DEMO is a Spark-source caslib: tables are read from
            Databricks. Do not use it as the target of promoted CAS tables
            (see 01_load_databricks_to_caslib.sas); use CASUSER or a PATH
            caslib for that.
            The shared DBSPARK caslib on the tenant is a different caslib
            and is not changed here.
  Runs in : SAS Studio or MCP execute_sas_code
--------------------------------------------------------------------------*/

%macro create_db_demo_caslib(
   caslib        = DB_DEMO,
   dbx_server    = adb-2401595702726378.18.azuredatabricks.net,
   dbx_http_path = sql/protocolv1/o/2401595702726378/0619-124631-x9a7aboi,
   dbx_schema    = default,
   dbx_port      = 443,
   token_folder  = /Users/&sysuserid/My Folder,
   token_name    = databricks_token.txt
);

%local _pw _opts;

filename _tok filesrvc folderpath="&token_folder" filename="&token_name";
%if not %sysfunc(fexist(_tok)) %then %do;
   %put ERROR: [caslib] Token file not found: &token_folder/&token_name;
   filename _tok clear;
   %return;
%end;

data _null_;
   infile _tok obs=1 truncover;
   input line $char512.;
   call symputx('_pw', strip(compress(line, '0D0A09'x)), 'L');
run;
filename _tok clear;

cas mysess;

/* A global caslib cannot be removed with the CASLIB statement DROP option */
proc cas;
   table.dropCaslib / caslib="&caslib" quiet=true;
quit;

%let _opts = %sysfunc(getoption(mprint)) %sysfunc(getoption(symbolgen)) %sysfunc(getoption(mlogic));
options nomprint nosymbolgen nomlogic;

caslib &caslib datasource=(srctype="spark" platform="databricks"
   server="&dbx_server" port=&dbx_port httpPath="&dbx_http_path"
   schema="&dbx_schema" username="token" password="%superq(_pw)")
   global;

%let _pw = ;
options &_opts;

proc cas;
   table.fileInfo / caslib="&caslib";
quit;

cas mysess terminate;
%mend create_db_demo_caslib;

%create_db_demo_caslib()
