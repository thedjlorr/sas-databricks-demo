/*--------------------------------------------------------------------------
  04_webapp_actions.sas
  Project : Databricks Modeling Demo (MCP)  (web app back end)
  Purpose : The SAS actions behind the buttons in webapp/ (Viya Bridge).
            webapp/server.py prepends this file to a job and then calls one
            macro. Each macro leaves its answer in WORK.WEB_RESULT (and
            WORK.WEB_IMP for the model), which the server reads back.
  Runs in : Viya compute session (SAS Studio compute context) + CAS

  Auth    : The Databricks personal access token is read at run time from
            /Users/<you>/My Folder/databricks_token.txt, exactly as in
            99_test_databricks_connection.sas. It is never written in this
            program and logging of resolved macro text is switched off
            while the LIBNAME is assigned.

  Scope   : Every table written by these macros goes to the signed-in
            user's CASUSER caslib and is named WEB_<something>. Nothing is
            written to Databricks. DB_DEMO is not touched.
--------------------------------------------------------------------------*/

%macro web_connect(libref=dbx);
%local _pw _opts;
filename _tok filesrvc folderpath="/Users/&sysuserid/My Folder" filename="databricks_token.txt";
%if not %sysfunc(fexist(_tok)) %then %do;
   %put ERROR: [web] Token file databricks_token.txt not found in My Folder.;
   filename _tok clear;
   %return;
%end;
data _null_;
   infile _tok obs=1 truncover;
   input line $char512.;
   call symputx('_pw', strip(compress(line,'0D0A09'x)), 'L');
run;
filename _tok clear;
%let _opts = %sysfunc(getoption(mprint)) %sysfunc(getoption(symbolgen)) %sysfunc(getoption(mlogic));
options nomprint nosymbolgen nomlogic;
libname &libref spark platform=databricks
   server="adb-2401595702726378.18.azuredatabricks.net"
   schema="default"
   httpPath="sql/protocolv1/o/2401595702726378/0619-124631-x9a7aboi"
   properties='EnableArrow=0;'
   port=443
   user=token
   password="%superq(_pw)";
%let _pw = ;
options &_opts;
%mend web_connect;

%macro web_cas;
cas webs;
libname casuser cas caslib="casuser" sessref=webs;
%mend web_cas;

/* List the Databricks tables and their column counts */
%macro web_tables;
%web_connect()
%if &syslibrc ne 0 %then %do;
   %put ERROR: [web] Databricks connection failed, check the token in databricks_token.txt.;
   %return;
%end;
proc sql;
   create table work.web_result as
   select memname as name length=64, count(*) as cols
   from dictionary.columns where libname = 'DBX'
   group by memname order by memname;
quit;
libname dbx clear;
%mend web_tables;

/* Copy one Databricks table into CASUSER as a promoted table */
%macro web_load(src=, tgt=);
%web_connect()
%if &syslibrc ne 0 %then %do;
   %put ERROR: [web] Databricks connection failed, check the token in databricks_token.txt.;
   %return;
%end;
%web_cas
proc casutil incaslib="casuser"; droptable casdata="&tgt" quiet; quit;
data casuser.&tgt (promote=yes); set dbx.&src; run;
libname dbx clear;
proc sql noprint; select count(*) into :_n trimmed from casuser.&tgt; quit;
data work.web_result; length source $64 target $64; source="&src"; target="&tgt"; rows=&_n; run;
%mend web_load;

/* Column profile of a CASUSER table: rows, missing, min, max, mean */
%macro web_profile(tbl=);
%web_cas
%if not %sysfunc(exist(casuser.&tbl)) %then %do;
   %put ERROR: [web] Table &tbl is not loaded in CASUSER, load it first.;
   %return;
%end;
ods exclude all;
proc cas;
   simple.summary / table={caslib="casuser", name="&tbl"},
      casout={caslib="casuser", name="&tbl._SUM", replace=true};
quit;
ods exclude none;
proc sql;
   create table work.web_result as
   select _Column_ as column length=64, _NObs_ as nobs, _NMiss_ as nmiss,
          _Min_ as min, _Max_ as max, _Mean_ as mean
   from casuser.&tbl._SUM;
quit;
%mend web_profile;

/* Inner join of three loaded tables on a shared key, keeping one copy of each column */
%macro web_join(a=, b=, c=, key=PRIMARY_KEY, out=WEB_BASE);
%local ua ub uc bcols ccols;
%let ua=%upcase(&a); %let ub=%upcase(&b); %let uc=%upcase(&c);
%web_cas
proc sql noprint;
   select cats('b."',name,'"') into :bcols separated by ', ' from dictionary.columns
      where libname='CASUSER' and memname="&ub"
        and upcase(name) not in (select upcase(name) from dictionary.columns where libname='CASUSER' and memname="&ua");
   select cats('c."',name,'"') into :ccols separated by ', ' from dictionary.columns
      where libname='CASUSER' and memname="&uc"
        and upcase(name) not in (select upcase(name) from dictionary.columns
                                 where libname='CASUSER' and (memname="&ua" or memname="&ub"));
quit;
proc cas; table.dropTable / caslib="casuser" name="&out" quiet=true; quit;
proc fedsql sessref=webs;
   create table casuser."&out" {options replace=true} as
   select a.*, &bcols, &ccols
   from casuser."&a" a
        inner join casuser."&b" b on a."&key"=b."&key"
        inner join casuser."&c" c on a."&key"=c."&key";
quit;
proc cas; table.promote / caslib="casuser" name="&out"; quit;
proc sql noprint;
   select count(*) into :_n trimmed from casuser.&out;
   select count(*) into :_c trimmed from dictionary.columns where libname='CASUSER' and memname=upcase("&out");
quit;
data work.web_result; length target $64; target="&out"; rows=&_n; cols=&_c; run;
%mend web_join;

/* Gradient boosting on the joined table. Rows with PRIMARY_KEY ending 0-6 train, 7-9 validate. */
%macro web_model(tbl=WEB_BASE, target=coll, event=Y, scores=WEB_SCORES);
%local nums noms ut;
%let ut=%upcase(&target);
%web_cas
proc cas; table.dropTable / caslib="casuser" name="&tbl._P" quiet=true; quit;
data casuser.&tbl._P;
   set casuser.&tbl;
   length _role $1;
   _role = ifc(mod(PRIMARY_KEY,10)<7,'T','V');
run;
proc sql noprint;
   select name into :nums separated by ' ' from dictionary.columns
      where libname='CASUSER' and memname=upcase("&tbl._P") and type='num'
        and upcase(name) not in ('CUSTOMER_RK','PRIMARY_KEY','ACCOUNT_NO','SNAPSHOT_DATE');
   select name into :noms separated by ' ' from dictionary.columns
      where libname='CASUSER' and memname=upcase("&tbl._P") and type='char'
        and upcase(name) ne "&ut" and upcase(name) ne '_ROLE';
quit;
proc cas; table.dropTable / caslib="casuser" name="&scores" quiet=true; quit;
ods exclude all;
ods output VariableImportance=work.web_imp;
proc gradboost data=casuser.&tbl._P ntrees=100 seed=42;
   partition rolevar=_role(train='T' validate='V');
   target &target / level=nominal;
   input &nums / level=interval;
   input &noms / level=nominal;
   output out=casuser.&scores copyvars=(PRIMARY_KEY &target _role);
run;
data casuser.&scores._V; set casuser.&scores; where _role='V'; run;
ods output ROCInfo=work.web_roc;
proc assess data=casuser.&scores._V;
   input P_&target.&event;
   target &target / level=nominal event="&event";
run;
ods exclude none;
proc cas; table.promote / caslib="casuser" name="&scores"; quit;
proc sql noprint;
   select count(*) into :_nt trimmed from casuser.&tbl._P where _role='T' and not missing(&target);
   select count(*) into :_nv trimmed from casuser.&tbl._P where _role='V' and not missing(&target);
quit;
proc sql;
   create table work.web_result as
   select 'Gradient boosting' as model length=40,
          &_nt as n_train, &_nv as n_valid,
          max(C) as auc, max(Sensitivity - FPR) as ks,
          max(case when round(CutOff,0.01)=0.5 then (FP+FN)/(TP+FP+FN+TN) else . end) as misclass
   from work.web_roc;
quit;
%mend web_model;

/* Save customer scores (customer, account, key, target, risk score) as a promoted table and a .sashdat file */
%macro web_save(base=WEB_BASE, scores=WEB_SCORES, out=WEB_CUSTOMER_RISK_SCORES);
%web_cas
proc cas; table.dropTable / caslib="casuser" name="&out" quiet=true; quit;
proc fedsql sessref=webs;
   create table casuser."&out" {options replace=true} as
   select b."CUSTOMER_RK", b."account_no", b."PRIMARY_KEY", b."coll",
          s."P_collY" as "risk_score", s."_role" as "split"
   from casuser."&base" b inner join casuser."&scores" s on b."PRIMARY_KEY"=s."PRIMARY_KEY";
quit;
proc cas; table.promote / caslib="casuser" name="&out"; quit;
proc casutil incaslib="casuser" outcaslib="casuser";
   save casdata="&out" casout="%lowcase(&out).sashdat" replace;
quit;
proc sql noprint; select count(*) into :_n trimmed from casuser.&out; quit;
data work.web_result; length target $64 file $80; target="&out"; file="%lowcase(&out).sashdat"; rows=&_n; run;
%mend web_save;
