/*--------------------------------------------------------------------------
  99_test_databricks_connection.sas
  Purpose : Test direct Databricks connection via SAS/ACCESS Spark
            List available tables and preview data
  Runs in : SAS Studio or MCP execute_sas_code

  Auth    : The Databricks personal access token is read at run time from a
            one-line text file in your private SAS Content "My Folder"
            (default /Users/<you>/My Folder/databricks_token.txt). It is
            never written in this program, never echoed to the log, and the
            macro variable that holds it is cleared as soon as the LIBNAME
            is assigned. (The compute server runs in lockdown with no user
            home directory, so a file-system path does not work here.)

            One-time setup (do this yourself, in SAS Studio):
              1. Explorer > SAS Content > Users > <you> > My Folder.
              2. New file > databricks_token.txt, containing only the token
                 (one line, no quotes, no spaces). Save.
              3. Keep it in My Folder only. Do not put it in a shared
                 folder, a caslib, or this repo.
            To use a different location, pass token_folder= / token_name=.
--------------------------------------------------------------------------*/

%macro test_databricks_connection(
   libref       = db_test,
   dbx_server   = adb-2401595702726378.18.azuredatabricks.net,
   dbx_http_path= sql/protocolv1/o/2401595702726378/0619-124631-x9a7aboi,
   dbx_schema   = default,
   dbx_port     = 443,
   token_folder = /Users/&sysuserid/My Folder,
   token_name   = databricks_token.txt,
   preview_table= sales_weekly
);

%local _dbx_pw _opts;

/* 1. Read the token file. Fail early with a clear message if it is missing. */
filename _dbxtok filesrvc folderpath="&token_folder" filename="&token_name";
%if not %sysfunc(fexist(_dbxtok)) %then %do;
   %put ERROR: [test] Token file not found: &token_folder/&token_name - see the Auth note in the program header.;
   filename _dbxtok clear;
   %return;
%end;

data _null_;
   infile _dbxtok obs=1 truncover;
   input line $char512.;
   line = strip(compress(line, '0D0A09'x));
   if line = '' then put 'ERROR: [test] Token file is empty.';
   else call symputx('_dbx_pw', line, 'L');
run;
filename _dbxtok clear;

%if %superq(_dbx_pw) = %then %return;

/* 2. Assign the LIBNAME with logging of resolved macro text switched off,
      so the token cannot appear in the log via MPRINT or SYMBOLGEN. */
%let _opts = %sysfunc(getoption(mprint)) %sysfunc(getoption(symbolgen)) %sysfunc(getoption(mlogic));
options nomprint nosymbolgen nomlogic;

libname &libref spark
   platform=databricks
   server="&dbx_server"
   schema="&dbx_schema"
   httpPath="&dbx_http_path"
   properties='EnableArrow=0;'
   port=&dbx_port
   user=token
   password="%superq(_dbx_pw)";

%let _dbx_pw = ;
options &_opts;

%if &syslibrc ne 0 %then %do;
   %put ERROR: [test] Databricks LIBNAME failed, syslibrc=&syslibrc - check the token and the cluster state.;
   %return;
%end;
%put NOTE: [test] Databricks LIBNAME &libref assigned.;

/* 3. List available tables in the Databricks schema */
proc sql;
   create table work.db_tables as
   select memname from dictionary.tables where libname = "%upcase(&libref)";
quit;

title "Tables accessible via &libref (Databricks &dbx_schema schema)";
proc print data=work.db_tables;
run;

/* 4. Preview the first 10 rows of one table, if it exists */
%if %sysfunc(exist(&libref..&preview_table)) %then %do;
   title "First 10 rows of &preview_table";
   proc sql outobs=10;
      select * from &libref..&preview_table;
   quit;
%end;
%else %put NOTE: [test] Table &preview_table not found in &libref - preview skipped.;

title;
%put NOTE: [test] Connection test complete.;

%mend;
%test_databricks_connection()
