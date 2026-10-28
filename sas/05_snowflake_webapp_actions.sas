/*--------------------------------------------------------------------------
  05_snowflake_webapp_actions.sas
  Project : NMAC Collections on Viya and Snowflake  (snowflake-webapp/ back end)
  Purpose : The SAS actions behind the live buttons in snowflake-webapp/.
            snowflake-webapp/server.py prepends this file to a job and then
            calls one macro. Each macro leaves its answer in WORK.WEB_* tables,
            which the server reads back.
  Runs in : Viya compute session (SAS Studio compute context) + CAS

  Data    : RND_DB.SEFORD.NMAC_AUTO_LOANS     one row per loan (built by 06_nmac_auto_data.sas)
            RND_DB.SEFORD.NMAC_AUTO_SNAPSHOT  loan features at three past month-ends (with outcome) and 30SEP2026 (live book)
            RND_DB.SEFORD.NMAC_AUTO_MONTHLY   36 months of portfolio delinquency
            All SYNTHETIC. Read through the SNOWLIB caslib.

  Auth    : None in this program. SNOWLIB is a global caslib on the tenant,
            its Snowflake credentials are held by the caslib definition.

  Scope   : Reads RND_DB.SEFORD through SNOWLIB. Everything written to Viya goes to
            the signed-in user's CASUSER caslib and is named WEB_SF_*. The only
            Snowflake write is %sf_writeback, which creates NMAC_AUTO_SCORES.

  Notes   : Pass-through to Snowflake needs cast(... as varchar(n)) on function
            results (unbounded strings fail in FedSQL), and the columns are
            lower case, so queries that name them use single-quoted CASL strings.
            FedSQL on CAS has no ORDER BY: rank small results in WORK.
--------------------------------------------------------------------------*/

/* the compute session is reused between jobs: an earlier error must not leave it in syntax-check mode */
options obs=max nosyntaxcheck;

%macro sf_cas;
cas websf;
libname casuser cas caslib="casuser" sessref=websf;
%mend sf_cas;

/* Prove SNOWLIB answers: version, user, role, warehouse and clock come from Snowflake */
%macro sf_check;
%sf_cas
ods exclude all;
proc cas;
   table.dropTable / caslib="casuser" name="WEB_SF_CHECK" quiet=true;
   fedSql.execDirect / query="select * from connection to SNOWLIB (select cast(current_version() as varchar(40)) as sf_version, cast(current_user() as varchar(60)) as sf_user, cast(current_role() as varchar(60)) as sf_role, cast(current_warehouse() as varchar(60)) as sf_warehouse, to_char(current_timestamp(), 'HH24:MI:SS') as sf_time)",
      casout={caslib="casuser", name="WEB_SF_CHECK", replace=true};
quit;
ods exclude none;
data work.web_result; set casuser.web_sf_check; run;
%mend sf_check;

/* Every base table in the schema with rows, columns and created date, from INFORMATION_SCHEMA */
%macro sf_tables;
%sf_cas
ods exclude all;
proc cas;
   table.dropTable / caslib="casuser" name="WEB_SF_TABLES" quiet=true;
   fedSql.execDirect / query="select * from connection to SNOWLIB (select cast(t.table_name as varchar(128)) as name, t.row_count as row_count, to_char(t.created, 'YYYY-MM-DD') as created, (select count(*) from information_schema.columns c where c.table_schema=t.table_schema and c.table_name=t.table_name) as cols from information_schema.tables t where t.table_schema='SEFORD' and t.table_type='BASE TABLE' order by t.table_name)",
      casout={caslib="casuser", name="WEB_SF_TABLES", replace=true};
quit;
ods exclude none;
data work.web_result; set casuser.web_sf_tables; run;
%mend sf_tables;

/* Column names and types of one table, read through SNOWLIB */
%macro sf_columns(tbl=);
%sf_cas
ods exclude all;
proc cas;
   table.columnInfo result=r / table={caslib="SNOWLIB", name="&tbl"};
   saveresult r.ColumnInfo dataout=work.web_cols;
quit;
ods exclude none;
data work.web_result; set work.web_cols(keep=Column Type); run;
%mend sf_columns;

/* Load the three NMAC_AUTO tables into CASUSER and compare CAS counts with counts computed inside Snowflake */
%macro sf_load;
%local t nm;
%sf_cas
ods exclude all;
proc cas;
   table.dropTable / caslib="casuser" name="WEB_SF_COUNTS" quiet=true;
   fedSql.execDirect / query='select * from connection to SNOWLIB (select count(*) as sf_loans, count(distinct "customer_id") as sf_customers, sum(case when "balance_current" > 0 then 1 else 0 end) as sf_active, sum("balance_current") as sf_balance from RND_DB.SEFORD.NMAC_AUTO_LOANS)',
      casout={caslib="casuser", name="WEB_SF_COUNTS", replace=true};
%do t = 1 %to 3;
   %let nm = %scan(LOANS SNAPSHOT MONTHLY, &t);
   table.dropTable / caslib="casuser" name="WEB_SF_&nm" quiet=true;
   table.loadTable / caslib="SNOWLIB" path="NMAC_AUTO_&nm", casout={caslib="casuser", name="WEB_SF_&nm", promote=true};
%end;
quit;
ods exclude none;
proc sql noprint;
   select count(*) into :_nl trimmed from casuser.WEB_SF_LOANS;
   select count(*) into :_ns trimmed from casuser.WEB_SF_SNAPSHOT;
   select count(*) into :_nm trimmed from casuser.WEB_SF_MONTHLY;
quit;
data work.web_result;
   set casuser.web_sf_counts;
   cas_loans=&_nl; cas_snapshot=&_ns; cas_monthly=&_nm;
run;
%mend sf_load;

/* Aggregate a CAS table with FedSQL and copy the small answer to WORK */
%macro sf_agg(out=, sql=);
proc cas; table.dropTable / caslib="casuser" name="&out" quiet=true; quit;
proc fedsql sessref=websf;
   create table casuser."&out" {options replace=true} as &sql;
quit;
data work.&out; set casuser.&out; run;
%mend sf_agg;

/* Probability of reaching 90+ days past due within 12 months, for every loan.
   Trains on the snapshots with a known outcome (30SEP2024, 31MAR2025, 30SEP2025). State, model and dealer are not model inputs (too many levels for the event count), splits TRAIN/VALIDATE by customer (70/30),
   and scores the live book at 30SEP2026. Then every table the report tabs show.
   LGD is an assumption used for expected loss, not a modelled value. */
%macro sf_score(lgd=0.5);
%local d25 d26 p60 p85 p95;
%let d25=%sysfunc(mdy(9,30,2025));
%let d26=%sysfunc(mdy(9,30,2026));
%sf_cas
ods exclude all;
proc cas; table.dropTable / caslib="casuser" name="WEB_SF_ALL" quiet=true; table.dropTable / caslib="casuser" name="WEB_SF_SCORED" quiet=true; quit;
proc fedsql sessref=websf;
   create table casuser."WEB_SF_ALL" {options replace=true} as
   select l."loan_id", l."customer_id", l."dealer_id", l."state", l."product", l."brand", l."model", l."credit_tier",
          l."employment", l."home_ownership", l."age", l."income", l."amount_financed", l."term", l."credit_score",
          l."apr", l."monthly_payment", l."ltv", l."dti", l."pti",
          s."snapshot_date", s."mob", s."balance", s."dpd", s."dpd_bucket", s."delinq_30", s."n30_12m", s."max_dpd_6m",
          s."contacts_90d", s."promise_to_pay", s."broken_promise", s."autopay", s."payment_ratio", s."default_12m"
   from casuser."WEB_SF_LOANS" l inner join casuser."WEB_SF_SNAPSHOT" s on l."loan_id" = s."loan_id";
quit;
data casuser.WEB_SF_ALL;
   set casuser.WEB_SF_ALL;
   length _role $1;
   if snapshot_date = &d26 then _role = 'S';
   else if mod(input(substr(customer_id,2), best12.), 10) < 7 then _role = 'T';
   else _role = 'V';
run;
ods output VariableImportance=work.web_imp;
proc gradboost data=casuser.WEB_SF_ALL ntrees=120 learningrate=0.08 maxdepth=4 seed=42;
   partition rolevar=_role(train='T' validate='V');
   target default_12m / level=nominal;
   input age income amount_financed term credit_score apr monthly_payment ltv dti pti mob balance dpd n30_12m
         max_dpd_6m contacts_90d promise_to_pay broken_promise autopay payment_ratio / level=interval;
   input product brand employment home_ownership / level=nominal;
   output out=casuser.WEB_SF_SCORED copyvars=(_all_);
run;
ods output ROCInfo=work.web_roc;
proc assess data=casuser.WEB_SF_SCORED(where=(_role='V'));
   input P_default_12m1;
   target default_12m / level=nominal event="1";
run;
ods exclude none;

/* risk bands on the live book: Low 60%, Medium 25%, High 10%, Very High 5% of loans by PD */
proc cas;
   percentile.percentile result=pc / table={caslib="casuser", name="WEB_SF_SCORED", where="_role='S'"}, inputs={"P_default_12m1"}, values={60,85,95};
   saveresult pc.Percentile dataout=work.web_pct;
quit;
data _null_;
   set work.web_pct;
   if round(Pctl)=60 then call symputx('p60', Value, 'L');
   if round(Pctl)=85 then call symputx('p85', Value, 'L');
   if round(Pctl)=95 then call symputx('p95', Value, 'L');
run;
proc cas; table.dropTable / caslib="casuser" name="WEB_SF_LIVE" quiet=true; table.dropTable / caslib="casuser" name="WEB_SF_VALID" quiet=true; quit;
data casuser.WEB_SF_LIVE;
   set casuser.WEB_SF_SCORED;
   where _role = 'S';
   length risk_band $9 dpd_group $7;
   PD = P_default_12m1;
   if PD >= &p95 then risk_band='Very High'; else if PD >= &p85 then risk_band='High';
   else if PD >= &p60 then risk_band='Medium'; else risk_band='Low';
   dpd_group = dpd_bucket;
   EL = PD * balance * &lgd;
run;
data casuser.WEB_SF_VALID;
   set casuser.WEB_SF_SCORED;
   where _role = 'V';
   PD = P_default_12m1;
run;

%sf_agg(out=WEB_KPI, sql=%str(
   select count(*) as loans, count(distinct customer_id) as customers, sum(balance) as balance,
          avg(delinq_30) as delinq_rate, sum(case when delinq_30=1 then balance else 0 end) as delinq_balance,
          sum(case when risk_band in ('High','Very High') then 1 else 0 end) as high_risk_loans,
          sum(case when risk_band in ('High','Very High') then balance else 0 end) as high_risk_balance,
          sum(EL) as expected_loss, avg(PD) as avg_pd, count(distinct dealer_id) as dealers
   from casuser."WEB_SF_LIVE"))
%sf_agg(out=WEB_TIER, sql=%str(
   select credit_tier, count(*) as loans, avg(default_12m) as actual_rate, avg(PD) as avg_pd
   from casuser."WEB_SF_VALID" group by credit_tier))
%sf_agg(out=WEB_TIER_LIVE, sql=%str(
   select credit_tier, count(*) as loans, sum(balance) as balance, avg(PD) as avg_pd, sum(EL) as expected_loss
   from casuser."WEB_SF_LIVE" group by credit_tier))
%sf_agg(out=WEB_BANDS, sql=%str(
   select risk_band, count(*) as loans, sum(balance) as balance, sum(PD) as exp_defaults, sum(EL) as expected_loss, avg(PD) as avg_pd
   from casuser."WEB_SF_LIVE" group by risk_band))
%sf_agg(out=WEB_PRODUCT, sql=%str(
   select product, count(*) as loans, sum(balance) as balance, avg(PD) as avg_pd from casuser."WEB_SF_LIVE" group by product))
%sf_agg(out=WEB_HEAT, sql=%str(
   select credit_tier, dpd_group, avg(PD) as avg_pd, count(*) as loans
   from casuser."WEB_SF_LIVE" group by credit_tier, dpd_group))
%sf_agg(out=WEB_DEALER_ALL, sql=%str(
   select dealer_id, count(*) as loans, sum(balance) as balance, avg(PD) as avg_pd, sum(EL) as expected_loss, avg(delinq_30) as delinq_rate
   from casuser."WEB_SF_LIVE" group by dealer_id))
proc sql outobs=10; create table work.web_dealer as select * from work.web_dealer_all order by expected_loss desc; quit;
%sf_agg(out=WEB_WORK_ALL, sql=%str(
   select customer_id, count(*) as loans, max(PD) as max_pd, sum(balance) as balance, sum(EL) as expected_loss,
          max(dpd) as max_dpd, avg(credit_score) as score, max(state) as state, max(dealer_id) as dealer_id
   from casuser."WEB_SF_LIVE" where delinq_30 = 1 group by customer_id))
proc sql outobs=15; create table work.web_work as select * from work.web_work_all order by expected_loss desc; quit;
proc sql noprint;
   create table work.web_work_n as select count(*) as delinquent_customers, sum(expected_loss) as total_el from work.web_work_all;
quit;

/* 12-month default curve for the live book: cumulative q = 1-(1-PD)^(m/12), monthly defaults are the differences */
proc cas; table.dropTable / caslib="casuser" name="WEB_SF_FCM" quiet=true; quit;
data casuser.WEB_SF_FCM;
   set casuser.WEB_SF_LIVE(keep=risk_band PD balance);
   do m = 1 to 12;
      exp_defaults = (1-(1-PD)**(m/12)) - (1-(1-PD)**((m-1)/12));
      output;
   end;
   keep risk_band m exp_defaults;
run;
%sf_agg(out=WEB_FC, sql=%str(
   select risk_band, m, sum(exp_defaults) as exp_defaults from casuser."WEB_SF_FCM" group by risk_band, m))

proc sql noprint;
   select count(*) into :_nt trimmed from casuser.WEB_SF_ALL where _role='T';
   select count(*) into :_nv trimmed from casuser.WEB_SF_ALL where _role='V';
   create table work.web_result as
   select max(C) as auc, &p60 as cut_p60, &p85 as cut_p85, &p95 as cut_p95, &lgd as lgd, &_nt as n_train, &_nv as n_valid from work.web_roc;
quit;
%mend sf_score;

/* Delinquency-rate forecast with ETS (PROC ESM): 36 months of real monthly history from NMAC_AUTO_MONTHLY,
   3 months ahead, 95% limits. Four ETS models compete, the lowest RMSE wins. */
%macro sf_forecast;
%local best list k m;
%sf_cas
data work.web_hist;
   set casuser.WEB_SF_MONTHLY(keep=month_end delinquency_rate);
   rename month_end=date delinquency_rate=rate;
run;
proc sort data=work.web_hist; by date; run;
%let list=linear damptrend addseasonal addwinters;
%do k=1 %to 4;
   %let m=%scan(&list,&k);
   proc esm data=work.web_hist lead=3 outfor=work.web_f_&m print=none;
      id date interval=month; forecast rate / model=&m alpha=0.05;
   run;
   proc sql; create table work.web_s_&m as select "&m" as model length=12, sqrt(mean(error**2)) as rmse from work.web_f_&m where not missing(error); quit;
%end;
data work.web_sel; set work.web_s_:; run;
proc sort data=work.web_sel; by rmse; run;
data _null_; set work.web_sel(obs=1); call symputx('best', model, 'L'); run;
data work.web_ts;
   set work.web_f_&best;
   length period $7 kind $8;
   period = put(date, yymmd7.);
   kind = ifc(missing(actual), 'forecast', 'history');
   keep period kind actual predict lower upper;
run;
data work.web_result; set work.web_sel(obs=1); run;
%mend sf_forecast;

/* Write the live-book scores back to Snowflake as a NEW table RND_DB.SEFORD.NMAC_AUTO_SCORES, then let Snowflake count it.
   Run %sf_score first. Only this one table is created or replaced, no existing Snowflake table is touched. */
%macro sf_writeback;
%local ts _n;
%sf_cas
%if not %sysfunc(exist(casuser.WEB_SF_LIVE)) %then %do;
   %put ERROR: [web] No scored table yet, run the scoring step first.;
   %return;
%end;
%let ts=%sysfunc(datetime(),e8601dt19.);
proc cas; table.dropTable / caslib="casuser" name="WEB_SF_SCORES_OUT" quiet=true; quit;
data casuser.WEB_SF_SCORES_OUT(keep=LOAN_ID CUSTOMER_ID SNAPSHOT_DATE PD RISK_BAND BALANCE EXPECTED_LOSS SCORED_AT);
   set casuser.WEB_SF_LIVE(rename=(loan_id=LOAN_ID customer_id=CUSTOMER_ID snapshot_date=SNAPSHOT_DATE risk_band=RISK_BAND balance=BALANCE EL=EXPECTED_LOSS));
   length SCORED_AT $19;
   SCORED_AT="&ts";
   format SNAPSHOT_DATE date9.;
run;
proc sql noprint; select count(*) into :_n trimmed from casuser.WEB_SF_SCORES_OUT; quit;
ods exclude all;
proc cas;
   table.dropTable / caslib="casuser" name="WEB_SF_WB" quiet=true;
   table.save / table={caslib="casuser", name="WEB_SF_SCORES_OUT"}, caslib="SNOWLIB", name="NMAC_AUTO_SCORES", replace=true;
   fedSql.execDirect / query='select * from connection to SNOWLIB (select count(*) as sf_rows, count(distinct "LOAN_ID") as sf_loans, avg("PD") as sf_avg_pd, sum("EXPECTED_LOSS") as sf_el from RND_DB.SEFORD.NMAC_AUTO_SCORES)',
      casout={caslib="casuser", name="WEB_SF_WB", replace=true};
quit;
ods exclude none;
data work.web_result;
   set casuser.WEB_SF_WB;
   length target $40 scored_at $19;
   target="RND_DB.SEFORD.NMAC_AUTO_SCORES"; scored_at="&ts"; cas_rows=&_n;
run;
%mend sf_writeback;

/* Read-only: does NMAC_AUTO_SCORES exist in Snowflake, and with how many rows */
%macro sf_wb_status;
%sf_cas
ods exclude all;
proc cas;
   table.dropTable / caslib="casuser" name="WEB_SF_WBS" quiet=true;
   fedSql.execDirect / query="select * from connection to SNOWLIB (select cast(table_name as varchar(64)) as name, row_count as sf_rows, to_char(created, 'YYYY-MM-DD HH24:MI') as created from information_schema.tables where table_schema='SEFORD' and table_name='NMAC_AUTO_SCORES')",
      casout={caslib="casuser", name="WEB_SF_WBS", replace=true};
quit;
ods exclude none;
data work.web_result; set casuser.WEB_SF_WBS; run;
%mend sf_wb_status;
