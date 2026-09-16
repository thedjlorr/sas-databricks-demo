/*--------------------------------------------------------------------------
  02_data_readiness.sas
  Project : MCP_Forecasting  (process step 2 — runs for ANY dataset config)
  Purpose : Pre-modelling readiness check for a time-series table.
            Answers, with numbers:
              - is the time ID a clean regular interval? (gaps, weekday)
              - per series: length, duplicate rows per period, missing
                pattern (leading / trailing / interior), zeros,
                intermittency (ADI), late start / early end
              - hierarchy cardinality at each level
              - do future values of the independents cover the horizon?
            Emits PASS / WARN / FAIL lines to the log and two tables:
              <out_caslib>.<prefix>readiness_series   (one row per series)
              <out_caslib>.<prefix>readiness_summary  (metric / value / status)
  Config  : keyword parameters of %data_readiness; the defaults mirror
            projects/mfg_demand.yml. Override per call, e.g.
              %data_readiness(in_caslib=CASUSER, horizon=8)
            Nothing else in the program is dataset-specific.
  Runs in : SAS Studio or MCP execute_sas_code (compute + CAS)
--------------------------------------------------------------------------*/

%macro data_readiness(
   project_id          = mfg_demand,               /* = project.id in projects/<id>.yml */
  in_caslib           = DB_DEMO,
   in_table            = MFG_DEMAND_SENSING_DEMO,
   exo_table           = MFG_WKLY_EXOGENOUS_VBLS,  /* blank = no exogenous table */
  out_caslib          = DB_DEMO,
   out_prefix          = mfg_demand_,
   time_id             = Date,
   interval_days       = 7,                        /* WEEK */
   horizon             = 12,
   target              = SHIPMENT,
   by_vars             = Segment Business_Unit Material Division Customer Region Plant,
   independents        = WTI_Crude_Oil HH_Natural_Gas US_Dlr_Index Jobless_Claims Baltic_Dry_Index Housing_Starts,
   exo_date_var        = Date,
   exo_date_is_char    = 1,
   exo_date_informat   = mmddyy10.,
   min_series_length   = 26,                       /* data_readiness.min_series_length */
   max_missing_share   = 0.5,                      /* data_readiness.max_missing_share */
   require_future_regs = 1,                        /* data_readiness.require_future_regressors */
   adi_intermittent    = 1.32                      /* Syntetos-Boylan ADI cut-off */
);
%local by_csv n_by i lvl cum;
%let by_csv = %sysfunc(translate(%sysfunc(compbl(&by_vars)), %str(,), %str( )));
%let n_by   = %sysfunc(countw(&by_vars));

cas mysess;
libname wrk cas caslib="&in_caslib" sessref=mysess;
libname out cas caslib="&out_caslib"  sessref=mysess;

title "Data readiness - &project_id (&in_caslib..&in_table)";

/*------------------------------------------------------------------------
  1. Time ID: distinct dates, global span, gaps, weekday alignment
------------------------------------------------------------------------*/
proc fedsql sessref=mysess;
  create table "&in_caslib"."_rd_dates" {options replace=true} as
  select distinct &time_id as dt
  from "&in_caslib"."&in_table"
  where &time_id is not null;
quit;

proc sort data=wrk._rd_dates out=work.rd_dates; by dt; run;

data work.rd_dates;
  set work.rd_dates end=eof;
  retain n_gap 0 n_wd_mismatch 0 wd0 min_dt;
  format dt date9.;
  gap = dif(dt);
  if _n_ = 1 then do; wd0 = weekday(dt); min_dt = dt; end;
  if _n_ > 1 and gap ne &interval_days then n_gap + 1;
  if weekday(dt) ne wd0 then n_wd_mismatch + 1;
  if eof then do;
    call symputx('g_first', min_dt, 'G');
    call symputx('g_last',  dt, 'G');
    call symputx('g_nweeks', _n_, 'G');
    call symputx('g_ngaps', n_gap, 'G');
    call symputx('g_nwdmis', n_wd_mismatch, 'G');
    call symputx('g_wd', wd0, 'G');
  end;
run;

%put NOTE: [readiness] time id &time_id: &g_nweeks periods, %sysfunc(putn(&g_first,date9.)) .. %sysfunc(putn(&g_last,date9.)), gaps=&g_ngaps, weekday=&g_wd (mismatches=&g_nwdmis);

/*------------------------------------------------------------------------
  2. Per-series statistics (in CAS via FedSQL)
------------------------------------------------------------------------*/
proc fedsql sessref=mysess;
  create table "&in_caslib"."_rd_series" {options replace=true} as
  select &by_csv,
         count(*)                                              as n_rows,
         count(distinct &time_id)                              as n_dates,
         min(&time_id)                                         as first_dt,
         max(&time_id)                                         as last_dt,
         count(&target)                                        as n_obs,
         sum(case when &target is null then 1 else 0 end)      as n_miss,
         sum(case when &target = 0     then 1 else 0 end)      as n_zero,
         min(case when &target is not null then &time_id end)  as first_obs_dt,
         max(case when &target is not null then &time_id end)  as last_obs_dt,
         sum(&target)                                          as total_val,
         avg(&target)                                          as mean_val
  from "&in_caslib"."&in_table"
  group by &by_csv;
quit;

data work.rd_series;
  set wrk._rd_series;
  format first_dt last_dt first_obs_dt last_obs_dt date9.;
  span_periods   = (last_dt - first_dt) / &interval_days + 1;
  dup_rows       = n_rows - n_dates;                      /* >0: several rows per period */
  implicit_gaps  = span_periods - n_dates;                /* absent periods */
  if n_obs > 0 then do;
    obs_len       = (last_obs_dt - first_obs_dt) / &interval_days + 1;
    leading_miss  = (first_obs_dt - first_dt) / &interval_days;
    trailing_miss = (last_dt - last_obs_dt) / &interval_days;
  end;
  else do; obs_len = 0; leading_miss = n_dates; trailing_miss = 0; end;
  interior_miss  = max(n_miss - leading_miss - trailing_miss, 0);
  miss_share     = n_miss / n_rows;
  nonzero_obs    = n_obs - n_zero;
  if nonzero_obs > 0 then adi = obs_len / nonzero_obs; else adi = .;
  starts_late    = (first_dt > &g_first);
  ends_early     = (last_dt  < &g_last);
  all_missing    = (n_obs = 0);
  all_zero       = (n_obs > 0 and nonzero_obs = 0);
  flag_short     = (obs_len < &min_series_length);
  flag_high_miss = (miss_share > &max_missing_share);
  flag_intermit  = (adi > &adi_intermittent);
  flag_has_gaps  = (implicit_gaps > 0);
  flag_dups      = (dup_rows > 0);
  label n_rows='Rows' n_dates='Periods' n_obs='Non-missing' n_miss='Missing' n_zero='Zeros'
        obs_len='Observed length' leading_miss='Leading missing'
        trailing_miss='Trailing missing' interior_miss='Interior missing'
        miss_share='Missing share' adi='ADI' implicit_gaps='Absent periods'
        dup_rows='Duplicate rows';
run;

/*------------------------------------------------------------------------
  3. Summaries over series
------------------------------------------------------------------------*/
proc means data=work.rd_series n sum mean min p10 p25 median p75 max maxdec=2;
  var n_rows n_dates dup_rows n_obs n_miss n_zero obs_len leading_miss trailing_miss
      interior_miss implicit_gaps miss_share adi;
  title2 "Per-series distribution";
run;

proc sql noprint;
  select count(*), sum(flag_short), sum(flag_high_miss), sum(flag_intermit),
         sum(flag_has_gaps), sum(flag_dups), sum(dup_rows), sum(starts_late), sum(ends_early),
         sum(all_missing), sum(all_zero),
         sum(n_miss), sum(leading_miss), sum(trailing_miss), sum(interior_miss), sum(n_zero),
         min(obs_len), median(obs_len), max(trailing_miss), min(trailing_miss)
    into :s_n, :s_short, :s_highmiss, :s_intermit, :s_gaps, :s_dupseries, :s_duprows, :s_late, :s_early,
         :s_allmiss, :s_allzero,
         :s_miss, :s_lead, :s_trail, :s_interior, :s_zero, :s_minlen, :s_medlen, :s_trailmax, :s_trailmin
  from work.rd_series;
quit;

/* last observed (non-missing) target week across all series: the true
   forecast origin. Rows after it are horizon rows (future regressors). */
proc sql noprint;
  select max(last_obs_dt), sum(last_obs_dt = (select max(last_obs_dt) from work.rd_series))
    into :g_lastobs trimmed, :s_at_origin trimmed
  from work.rd_series;
quit;
%let g_hzrows = %sysevalf((&g_last - &g_lastobs) / &interval_days);
%put NOTE: [readiness] last observed &target week = %sysfunc(putn(&g_lastobs,date9.)) (&s_at_origin of &s_n series end there) - table carries &g_hzrows periods beyond it;

/* in-table future regressor periods: dates beyond the origin where every
   independent is populated */
%if %length(&independents) > 0 %then %do;
  /* FedSQL types a formatted date column as DATE, so compare to a DATE
     literal; macro vars do not resolve inside single quotes, so build the
     quoted literal first */
  %local origin_lit;
  %let origin_lit = %str(%')%sysfunc(putn(&g_lastobs, yymmdd10.))%str(%');
  proc fedsql sessref=mysess;
    create table "&in_caslib"."_rd_intab" {options replace=true} as
    select count(distinct &time_id) as n_future
    from "&in_caslib"."&in_table"
    where &time_id > date &origin_lit
      and %sysfunc(prxchange(s/\s+/ is not null and /, -1, %sysfunc(compbl(&independents)))) is not null
    ;
  quit;
%end;
%global intab_future;            /* written by symputx(...,'G') below */
%let intab_future = 0;
%if %length(&independents) > 0 %then %do;
  data _null_; set wrk._rd_intab; call symputx('intab_future', n_future, 'G'); run;
%end;

%put NOTE: [readiness] series=&s_n  short(<&min_series_length)=&s_short  high-missing(>&max_missing_share)=&s_highmiss  intermittent(ADI>&adi_intermittent)=&s_intermit  with-absent-periods=&s_gaps  with-duplicate-rows=&s_dupseries (rows=&s_duprows)  start-late=&s_late  end-early=&s_early  all-missing=&s_allmiss  all-zero=&s_allzero;
%put NOTE: [readiness] missing &target rows=&s_miss -> leading=&s_lead trailing=&s_trail (per series min=&s_trailmin max=&s_trailmax) interior=&s_interior / zero rows=&s_zero / obs_len min=&s_minlen median=&s_medlen;

/* series with the most duplicate rows, for inspection */
proc sql outobs=10;
  title2 "Series with duplicate rows per period (top 10)";
  select &by_csv, n_rows, n_dates, dup_rows
  from work.rd_series where dup_rows > 0 order by dup_rows desc;
quit;

/*------------------------------------------------------------------------
  4. Hierarchy cardinality: distinct values per level and cumulative series
------------------------------------------------------------------------*/
data work.rd_hier; length level $32 depth distinct_values series_at_level 8; stop; run;
%let cum =;
%do i = 1 %to &n_by;
  %let lvl = %scan(&by_vars, &i);
  %if &i > 1 %then %let cum = &cum,&lvl; %else %let cum = &lvl;
  proc sql noprint;
    select count(distinct &lvl) into :c_lvl trimmed from work.rd_series;
    select count(*) into :c_cum trimmed from (select distinct &cum from work.rd_series);
  quit;
  data work._h; length level $32; level="&lvl"; depth=&i; distinct_values=&c_lvl; series_at_level=&c_cum; run;
  proc append base=work.rd_hier data=work._h force; run;
%end;

proc print data=work.rd_hier noobs label;
  label level='Level (top to leaf)' distinct_values='Distinct values' series_at_level='Series through this level';
  title2 "Hierarchy cardinality";
run;

/*------------------------------------------------------------------------
  5. Independent variables: future-value coverage of the horizon
------------------------------------------------------------------------*/
/* globals: the DATA step below writes them with symputx(...,'G'), so they
   must not be created as macro-local %let variables first */
%global exo_ok exo_future exo_first exo_last exo_gaps exo_nmiss exo_aligned;
%let exo_ok = 0; %let exo_future = 0; %let exo_first = .; %let exo_last = .;
%let exo_gaps = .; %let exo_nmiss = .; %let exo_aligned = .;
%if %length(&exo_table) > 0 %then %do;
  data wrk._rd_exo;                       /* runs in CAS: CAS in, CAS out */
    set wrk.&exo_table;
    %if &exo_date_is_char %then %do;
      dt = input(&exo_date_var, &exo_date_informat);
    %end;
    %else %do;
      dt = &exo_date_var;
    %end;
    keep dt &independents;
  run;

  proc sort data=wrk._rd_exo out=work.rd_exo; by dt; run;

  data work.rd_exo_chk;
    set work.rd_exo end=eof;
    retain n_gap 0 n_future 0 n_miss 0 n_wd_mis 0;
    array x{*} &independents;
    gap = dif(dt);
    if _n_ > 1 and gap ne &interval_days then n_gap + 1;
    if dt > &g_lastobs then n_future + 1;    /* beyond the forecast origin */
    if weekday(dt) ne &g_wd then n_wd_mis + 1;
    do i = 1 to dim(x); if missing(x{i}) then n_miss + 1; end;
    if _n_ = 1 then call symputx('exo_first', dt, 'G');
    if eof then do;
      call symputx('exo_last', dt, 'G');
      call symputx('exo_future', n_future, 'G');
      call symputx('exo_gaps', n_gap, 'G');
      call symputx('exo_nmiss', n_miss, 'G');
      call symputx('exo_aligned', (n_wd_mis = 0), 'G');
    end;
  run;
  %let exo_ok = %eval(&exo_future >= &horizon and &exo_gaps = 0 and &exo_nmiss = 0 and &exo_aligned = 1);
  %put NOTE: [readiness] external regressor table: %sysfunc(putn(&exo_first,date9.)) .. %sysfunc(putn(&exo_last,date9.)), periods beyond origin = &exo_future (horizon &horizon), gaps=&exo_gaps, missing cells=&exo_nmiss, weekday aligned=&exo_aligned;
%end;
%let regs_future = %sysfunc(max(&intab_future, &exo_future));
%let regs_ok = %eval(&regs_future >= &horizon);
%put NOTE: [readiness] future regressor periods available: in-table=&intab_future external=&exo_future -> &regs_future vs horizon &horizon;

/*------------------------------------------------------------------------
  6. Readiness summary table + verdicts
------------------------------------------------------------------------*/
data work.rd_summary;
  length metric $48 value 8 threshold $24 status $4 note $160;
  metric="periods";                 value=&g_nweeks;   threshold="";                       status="INFO"; note="%sysfunc(putn(&g_first,date9.)) .. %sysfunc(putn(&g_last,date9.))"; output;
  metric="time_id gaps";            value=&g_ngaps;    threshold="= 0";                    status=ifc(&g_ngaps=0,"PASS","FAIL"); note="regular &interval_days-day interval"; output;
  metric="weekday mismatches";      value=&g_nwdmis;   threshold="= 0";                    status=ifc(&g_nwdmis=0,"PASS","FAIL"); note="all dates on the same weekday"; output;
  metric="series";                  value=&s_n;        threshold="";                       status="INFO"; note="leaf level = &n_by BY vars"; output;
  metric="series with duplicate rows"; value=&s_dupseries; threshold="";                   status=ifc(&s_dupseries=0,"PASS","WARN"); note="&s_duprows extra rows: BY vars are not a unique key - accumulate=TOTAL is required and must be intended"; output;
  metric="series with absent periods"; value=&s_gaps;  threshold="";                       status=ifc(&s_gaps=0,"PASS","WARN"); note="setmissing decides how gaps are filled"; output;
  metric="short series";            value=&s_short;    threshold="< &min_series_length";   status=ifc(&s_short=0,"PASS","WARN"); note="candidates for higher-level or naive models"; output;
  metric="high-missing series";     value=&s_highmiss; threshold="> &max_missing_share";   status=ifc(&s_highmiss=0,"PASS","WARN"); note=""; output;
  metric="intermittent series";     value=&s_intermit; threshold="ADI > &adi_intermittent"; status=ifc(&s_intermit=0,"PASS","WARN"); note="consider intermittent template / demand classification"; output;
  metric="all-zero series";         value=&s_allzero;  threshold="= 0";                    status=ifc(&s_allzero=0,"PASS","WARN"); note="retire or exclude"; output;
  metric="all-missing series";      value=&s_allmiss;  threshold="= 0";                    status=ifc(&s_allmiss=0,"PASS","FAIL"); note=""; output;
  metric="missing target rows";     value=&s_miss;     threshold="";                       status="INFO"; note="leading=&s_lead trailing=&s_trail (per series &s_trailmin..&s_trailmax) interior=&s_interior"; output;
  metric="forecast origin";         value=&g_lastobs;  threshold="";                       status="INFO"; note="last observed &target week %sysfunc(putn(&g_lastobs,date9.)); &s_at_origin series end there; table has &g_hzrows horizon periods after it"; output;
  metric="late-start series";       value=&s_late;     threshold="";                       status="INFO"; note="new products/customers (start after %sysfunc(putn(&g_first,date9.)))"; output;
  metric="early-end series";        value=&s_early;    threshold="";                       status="INFO"; note="retired series candidates (last row before %sysfunc(putn(&g_last,date9.)))"; output;
  metric="in-table future regressor periods"; value=&intab_future; threshold="";           status="INFO"; note="periods after origin with all independents populated"; output;
  %if %length(&exo_table) > 0 %then %do;
  metric="external future regressor periods"; value=&exo_future; threshold="";             status=ifc(&exo_gaps=0 and &exo_nmiss=0 and &exo_aligned=1,"INFO","WARN"); note="&exo_table: gaps=&exo_gaps missing=&exo_nmiss aligned=&exo_aligned"; output;
  %end;
  metric="future regressor periods"; value=&regs_future; threshold=">= &horizon";          status=ifc(&regs_ok,"PASS",ifc(&require_future_regs,"FAIL","WARN")); note="max(in-table, external) must cover the horizon"; output;
run;

proc print data=work.rd_summary noobs; title2 "Readiness summary"; run;

data _null_;
  set work.rd_summary end=eof;
  retain nfail 0 nwarn 0;
  if status="FAIL" then nfail+1;
  if status="WARN" then nwarn+1;
  if status in ("FAIL","WARN") then put "NOTE: [readiness] " status ": " metric "=" value " (" threshold ") " note;
  if eof then do;
    if nfail>0 then put "NOTE: [readiness] VERDICT: FAIL (" nfail " fail, " nwarn " warn)";
    else if nwarn>0 then put "NOTE: [readiness] VERDICT: PASS WITH WARNINGS (" nwarn " warn)";
    else put "NOTE: [readiness] VERDICT: PASS";
  end;
run;

/*------------------------------------------------------------------------
  7. Persist outputs (promoted) and clean up session tables
------------------------------------------------------------------------*/
proc casutil incaslib="&out_caslib";
  droptable casdata="&out_prefix.readiness_series"  quiet;
  droptable casdata="&out_prefix.readiness_summary" quiet;
quit;
data out.&out_prefix.readiness_series  (promote=yes); set work.rd_series;  run;
data out.&out_prefix.readiness_summary (promote=yes); set work.rd_summary; run;

proc casutil incaslib="&in_caslib";
  droptable casdata="_rd_dates"  quiet;
  droptable casdata="_rd_series" quiet;
  droptable casdata="_rd_exo"    quiet;
  droptable casdata="_rd_intab"  quiet;
quit;

title;
cas mysess terminate;
%mend data_readiness;

/* Run with the defaults (= projects/mfg_demand.yml). To check another
   dataset, pass its values as keyword arguments instead of editing above. */
%data_readiness()
