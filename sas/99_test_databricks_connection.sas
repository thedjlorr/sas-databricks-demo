/*--------------------------------------------------------------------------
  99_test_databricks_connection.sas
  Purpose : Test direct Databricks connection via SAS/ACCESS Spark
            List available tables and preview data
  Runs in : SAS Studio or MCP execute_sas_code
--------------------------------------------------------------------------*/

/* Direct connection to Databricks */
libname db_test spark 
   platform=databricks 
   server='adb-2401595702726378.18.azuredatabricks.net' 
   schema='default' 
   httpPath="sql/protocolv1/o/2401595702726378/0619-124631-x9a7aboi" 
   properties='EnableArrow=0;' 
   port=443 
   user=token 
   password=dapi6b9698427bc4d357c9ae0b5cd5da50c5-3;

%put NOTE: [test] Attempting Databricks connection via Spark LIBNAME...;

/* Test 1: List available tables in Databricks */
title "Available Tables in Databricks (default schema)";
proc sql;
   select * from DICTIONARY.TABLES where libname='DB_TEST';
quit;

%put NOTE: [test] Listing tables complete.;

/* Test 2: Try to access common tables */
%macro check_table(table_name);
  %put NOTE: [test] Checking table: &table_name;
  proc sql;
    select count(*) as row_count, 
           calculated row_count as 'Row Count' label='Row Count'
    from db_test.&table_name;
  quit;
%mend;

/* Preview tables if they exist */
proc sql;
  create table work.db_tables as
  select memname from dictionary.tables where libname='DB_TEST';
quit;

proc print data=work.db_tables;
  title "Tables accessible via db_test library";
run;

/* Test 3: If sales_weekly exists, preview first 10 rows */
proc sql;
  select * from db_test.sales_weekly fetch first 10 rows;
quit;

title;
%put NOTE: [test] Connection test complete.;
