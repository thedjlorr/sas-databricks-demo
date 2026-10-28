// SAS shown under each tab. Excerpts of sas/05_snowflake_webapp_actions.sas and sas/06_nmac_auto_data.sas, the programs the live buttons run.
window.SAS_CODE = {
  connect: `cas mysess;
proc cas;
  table.caslibInfo / caslib="SNOWLIB";
  /* query runs INSIDE Snowflake */
  fedSql.execDirect / query="
    select * from connection to SNOWLIB
      (select cast(current_version() as varchar(40)), cast(current_user() as varchar(60)),
              cast(current_role() as varchar(60)), cast(current_warehouse() as varchar(60)),
              to_char(current_timestamp(), 'HH24:MI:SS'))";
quit;`,

  load: `proc cas;
  /* Snowflake -> CAS (serial LoadTable, SAS Data Connector to Snowflake) */
  table.loadTable / caslib="SNOWLIB" path="NMAC_AUTO_LOANS",
      casout={caslib="casuser", name="WEB_SF_LOANS", promote=true};
  table.loadTable / caslib="SNOWLIB" path="NMAC_AUTO_SNAPSHOT",
      casout={caslib="casuser", name="WEB_SF_SNAPSHOT", promote=true};
  /* counts computed by Snowflake before any data returns to SAS */
  fedSql.execDirect / query='
    select * from connection to SNOWLIB
      (select count(*) as sf_loans, count(distinct "customer_id") as sf_customers,
              sum("balance_current") as sf_balance
         from RND_DB.SEFORD.NMAC_AUTO_LOANS)';
quit;`,

  score: `/* Train on past snapshots with a known 12-month outcome, split by CUSTOMER (70/30),
   score the live book at 30 Sep 2026. Dealer, state and model are not inputs. */
proc gradboost data=casuser.WEB_SF_ALL ntrees=120 learningrate=0.08 maxdepth=4 seed=42;
  partition rolevar=_role(train='T' validate='V');
  target default_12m / level=nominal;
  input age income amount_financed term credit_score apr monthly_payment ltv dti pti
        mob balance dpd n30_12m max_dpd_6m contacts_90d promise_to_pay broken_promise
        autopay payment_ratio / level=interval;
  input product brand employment home_ownership / level=nominal;
  output out=casuser.WEB_SF_SCORED copyvars=(_all_);
run;
/* bands on the live book: Low 60%, Medium 25%, High 10%, Very High 5% of loans by PD */
EL = PD * balance * &lgd;   /* LGD is an assumption (50%), not a modelled value */`,

  tier: `proc cas;
  /* model vs actual on held-out customers, by credit tier */
  fedSql.execDirect / query="
    select credit_tier, count(*) as loans, avg(default_12m) as actual_rate, avg(PD) as avg_pd
    from casuser.WEB_SF_VALID group by credit_tier"
    casout={name="WEB_TIER" caslib="CASUSER" replace=true};
quit;`,

  forecast12: `/* 12-month default curve for the live book: cumulative q = 1-(1-PD)^(m/12) */
data casuser.WEB_SF_FCM;
  set casuser.WEB_SF_LIVE(keep=risk_band PD);
  do m = 1 to 12;
    exp_defaults = (1-(1-PD)**(m/12)) - (1-(1-PD)**((m-1)/12));
    output;
  end;
run;`,

  ets: `/* ETS: four exponential smoothing models compete, lowest RMSE wins, 95% limits (alpha=0.05) */
%macro ets;
  %let list=linear damptrend addseasonal addwinters;
  %do k=1 %to 4; %let m=%scan(&list,&k);
    proc esm data=work.web_hist lead=3 outfor=work.f_&m print=none;
      id date interval=month;
      forecast rate / model=&m alpha=0.05;
    run;
    proc sql;
      create table work.s_&m as
      select "&m" as model, sqrt(mean(error**2)) as rmse
      from work.f_&m where not missing(error);
    quit;
  %end;
%mend;
%ets
/* outfor holds ACTUAL, PREDICT, LOWER (95% LCL) and UPPER (95% UCL) */`,

  heatmap: `proc cas;
  fedSql.execDirect / query="
    select credit_tier, dpd_group, avg(PD) as avg_pd, count(*) as loans
    from casuser.WEB_SF_LIVE group by credit_tier, dpd_group"
    casout={name="WEB_HEAT" caslib="CASUSER" replace=true};
quit;`,

  drivers: `ods output VariableImportance=work.web_imp;
proc gradboost data=casuser.WEB_SF_ALL ...;   /* same model as the Score step */
run;`,

  dealer: `proc cas;
  fedSql.execDirect / query="
    select dealer_id, count(*) as loans, sum(balance) as balance, avg(PD) as avg_pd,
           sum(EL) as expected_loss, avg(delinq_30) as delinq_rate
    from casuser.WEB_SF_LIVE group by dealer_id"
    casout={name="WEB_DEALER_ALL" caslib="CASUSER" replace=true};
quit;
proc sql outobs=10; create table work.web_dealer as
  select * from work.web_dealer_all order by expected_loss desc; quit;`,

  worklist: `proc cas;
  /* customers with a loan 30+ days past due, ranked by expected loss */
  fedSql.execDirect / query="
    select customer_id, count(*) as loans, max(PD) as max_pd, sum(balance) as balance,
           sum(EL) as expected_loss, max(dpd) as max_dpd
    from casuser.WEB_SF_LIVE where delinq_30 = 1 group by customer_id"
    casout={name="WEB_WORK_ALL" caslib="CASUSER" replace=true};
quit;`,

  writeback: `proc cas;
  /* new table in Snowflake: one row per live loan with its score */
  table.save / table={caslib="casuser", name="WEB_SF_SCORES_OUT"},
      caslib="SNOWLIB", name="NMAC_AUTO_SCORES", replace=true;
  /* Snowflake counts what it received */
  fedSql.execDirect / query='
    select * from connection to SNOWLIB
      (select count(*) as sf_rows, avg("PD") as sf_avg_pd, sum("EXPECTED_LOSS") as sf_el
         from RND_DB.SEFORD.NMAC_AUTO_SCORES)';
quit;`
};
