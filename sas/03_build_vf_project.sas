/*--------------------------------------------------------------------------
  03_build_vf_project.sas
  Project : MCP_Forecasting  (process step 3 — runs for ANY dataset config)
  Purpose : Create (or reuse) a SAS Visual Forecasting project in Model
            Studio from the dataset config, entirely through REST calls
            made from SAS (PROC HTTP, session identity — no tokens):
              1. create the project on the working CAS table
              2. assign variable roles (dependent / independent / byVar)
              3. set the hierarchy (BY-var order + reconciliation level)
              4. load the project data and check the data definition
              5. pipelines: rename the auto-created "Pipeline 1" and add
                 pipelines from stock templates (idempotent, by name)
              6. run the pipelines (all | first | none), wait for the jobs
              7. print the pipeline comparison (one row per pipeline,
                 champion flagged)
            The provider auto-detects the time ID and interval; project
            settings (lead/back/metric/CL) are passed at create time.

  If a project with the same name already exists (if_exists=):
    reuse   (default) Steps 1-4 are SKIPPED: nothing is created and the
            existing configuration (roles, hierarchy, settings, data) is
            left untouched — even if the parameters passed differ from
            it. Steps 5-7 still run, and are additive/idempotent: a
            pipeline still called "Pipeline 1" is renamed, templates in
            add_templates= whose name is not yet present are added,
            pipelines are (re)run and the comparison printed. Use this to
            add a pipeline to, re-run, or fetch results from an existing
            project; it will NOT apply role/hierarchy/setting changes.
    replace The existing project is DELETED (its pipelines and results
            with it) and rebuilt from scratch through steps 1-6. Use this
            when roles, hierarchy or settings changed in the config.
    fail    Stop with an error; nothing is touched.
  Project identity is by NAME (project_name); ids change on replace, so
  read VF_PROJECT_ID from the log rather than hard-coding it.

  Config  : keyword parameters of %build_vf_project; defaults mirror
            projects/mfg_demand.yml.
  Requires: sas/macros/viya_rest.sas (helper macros), %included below.
  Outputs : macro vars VF_PROJECT_ID, VF_PIPELINE_ID, VF_JOB_STATE (global)
  Runs in : SAS Studio or MCP execute_sas_code
--------------------------------------------------------------------------*/

filename vrest filesrvc folderpath='/Demo/MCP_Forecasting/sas/macros' filename='viya_rest.sas';
%include vrest;

%macro build_vf_project(
   project_id           = mfg_demand,
   project_name         = %str(MFG Demand Sensing - Shipments (MCP)),
   description          = %str(Weekly shipment forecasting for a chemicals manufacturer, built via the SAS MCP process.),
   cas_server           = cas-shared-default,
  in_caslib            = DB_DEMO,
   in_table             = MFG_DEMAND_SENSING_DEMO,
   target               = SHIPMENT,
   target_accumulate    = TOTAL,
   target_missing       = MISSING,
   by_vars              = Segment Business_Unit Material Division Customer,   /* hierarchy top -> leaf */
   reconciliation_level = 2,                        /* 0-based index into by_vars (2 = Material) */
   independents         = WTI_Crude_Oil HH_Natural_Gas US_Dlr_Index Jobless_Claims Baltic_Dry_Index Housing_Starts,
   indep_accumulate     = AVERAGE,                  /* one value, or a list parallel to independents= (e.g. AVERAGE ... TOTAL MAXIMUM) */
   indep_missing        = MISSING,                  /* same rule */
   indep_in_auto_models = YES,                      /* useInSystemGeneratedModels */
   horizon              = 12,                       /* lead */
   back                 = 0,                        /* holdback; must be < horizon (service rule); applied after the load */
   metric               = MAPE,
   confidence_limit     = 0.05,
   allow_negative       = false,
   if_exists            = reuse,                    /* reuse | replace | fail */
   pipeline_name        = Auto-forecasting,         /* rename of the auto-created "Pipeline 1" (blank = keep) */
   add_templates        = forecasting-hierarchical-1 forecasting-regression-2,   /* extra pipelines, by template id */
   add_names            = Hierarchical Forecasting|Regression,                    /* their names, |-separated, same order */
   run_pipelines        = all,                      /* all | first | none */
   wait_for_job         = 1,                        /* 0 = start the jobs and return (MCP idle limit is 5 min) */
   poll_interval        = 15,                       /* seconds */
   max_wait             = 240                       /* seconds per job; keep total < 300 via the MCP connector */
);
%global vf_project_id vf_pipeline_id vf_pipeline_ids vf_job_state vf_job_id vf_dd_id vf_td_id vf_tpl_ok;
%local i v n rc jobid hid existing p3;
%let vf_project_id = ; %let vf_pipeline_id = ; %let vf_job_state = ;
filename body temp; filename vraw temp;

/*------------------------------------------------------------------------
  helper: set one variable's role by GET-patch-PUT (If-Match ETag)
------------------------------------------------------------------------*/
%macro vf_set_role(var, role, agg=, miss=MISSING, sysgen=);
  %local vid;
  %viya_http(path=/forecastingDataDefinition/dataDefinitions/&vf_dd_id/tableDefinitions/&vf_td_id/variables?limit=200, quiet=1)
  %viya_json(lib=jv)
  proc sql noprint; select id into :vid trimmed from jv.items where upcase(name)=upcase("&var"); quit;
  libname jv clear;
  %if %length(&vid) = 0 %then %do; %put ERROR: [vf] variable &var not found in &in_table; %return; %end;
  %viya_http(path=/forecastingDataDefinition/dataDefinitions/&vf_dd_id/tableDefinitions/&vf_td_id/variables/&vid,
             accept=application/vnd.sas.analytics.forecasting.variable+json, out=vraw, quiet=1)
  data _null_;
    infile vraw lrecl=32767 truncover; input line $32767.; file body;
    line = prxchange("s/\x22role\x22:\x22[^\x22]*\x22/\x22role\x22:\x22&role\x22/", 1, line);
    %if %length(&agg) %then %do;
    line = prxchange("s/\x22hierarchyAggregation\x22:\x22[^\x22]*\x22/\x22hierarchyAggregation\x22:\x22&agg\x22/", 1, line);
    line = prxchange("s/\x22timeIntervalAccumulation\x22:\x22[^\x22]*\x22/\x22timeIntervalAccumulation\x22:\x22&agg\x22/", 1, line);
    line = prxchange("s/\x22missingInterpretation\x22:\x22[^\x22]*\x22/\x22missingInterpretation\x22:\x22&miss\x22/", 1, line);
    %end;
    %if %length(&sysgen) %then %do;
    line = prxchange("s/\x22useInSystemGeneratedModels\x22:\x22[^\x22]*\x22/\x22useInSystemGeneratedModels\x22:\x22&sysgen\x22/", 1, line);
    %end;
    put line;
  run;
  %viya_http(method=PUT, path=/forecastingDataDefinition/dataDefinitions/&vf_dd_id/tableDefinitions/&vf_td_id/variables/&vid,
             in=body, in_type=application/vnd.sas.analytics.forecasting.variable+json,
             accept=application/vnd.sas.analytics.forecasting.variable+json, ifmatch=&viya_etag, quiet=1)
  %put NOTE: [vf] role &var = &role %sysfunc(ifc(%length(&agg),(&agg / &miss),)) -> &viya_rc;
%mend vf_set_role;

/*------------------------------------------------------------------------
  1. find or create the project
------------------------------------------------------------------------*/
%viya_http(path=/analyticsGateway/projects?limit=500, quiet=1)
%viya_json(lib=jp)
proc sql noprint; select id into :existing trimmed from jp.items where name="&project_name" and projectType='forecasting'; quit;
libname jp clear;

%if %length(&existing) %then %do;
  %put NOTE: [vf] project "&project_name" exists: &existing (if_exists=&if_exists);
  %if &if_exists = fail %then %do; %put ERROR: [vf] project exists and if_exists=fail; %return; %end;
  %if &if_exists = replace %then %do;
    %viya_http(method=DELETE, path=/analyticsGateway/projects/&existing)
    %let rc = %sysfunc(sleep(5,1));
    %let existing = ;
  %end;
%end;

%if %length(&existing) %then %do;
  /* REUSE: keep the project exactly as it is. Steps 2-4 (roles,
     hierarchy, data load) are skipped — parameters passed to this call
     are NOT applied to an existing project. Continue at step 5. */
  %let vf_project_id = &existing;
  %put NOTE: [vf] reusing project &vf_project_id - configuration unchanged, skipping to pipeline run;
%end;
%else %do;
  data _null_;
    file body;
    put '{"name":"' "&project_name" '","description":"' "&description" '","projectType":"forecasting",'
        '"dataUri":"/dataTables/dataSources/cas~fs~' "&cas_server" '~fs~' "&in_caslib" '/tables/' "&in_table" '",'
        '"dataServerName":"' "&cas_server" '","dataMediaType":"application/vnd.sas.data.table","dataLabel":"' "&in_table" '",'
        '"providerSpecificProperties":{"lead":"' "&horizon" '","back":"' "&back" '","confidenceLimit":"' "&confidence_limit" '",'
        '"comparisonMetric":"' "&metric" '","allowNegative":"' "&allow_negative" '","outlierLowerBound":"70","outlierUpperBound":"300",'
        '"almostFlatMethod":"STD_SLOPE","almostFlatAbsoluteTolerance":"0.005","almostFlatRelativeTolerance":"0.05",'
        '"computeContextUri":"","createdFromExternalForecasts":"false","annotation":""}}';
  run;
  %viya_http(method=POST, path=/analyticsGateway/projects, in=body,
             in_type=application/vnd.sas.analytics.project+json, accept=application/vnd.sas.analytics.project+json, expect=201)
  %if not &viya_ok %then %return;
  %viya_json(lib=jp) %viya_scalar(lib=jp, var=id, into=vf_project_id) libname jp clear;
  %put NOTE: [vf] created project &vf_project_id;
  %let rc = %sysfunc(sleep(10,1));           /* provider builds the data definition */

  /*----------------------------------------------------------------------
    2. variable roles
  ----------------------------------------------------------------------*/
  %viya_http(path=/forecastingGateway/projects/&vf_project_id/dataDefinitions/@current,
             accept=application/vnd.sas.analytics.forecasting.data.definition+json, quiet=1)
  %viya_json(lib=jd) %viya_scalar(lib=jd, var=id, into=vf_dd_id) libname jd clear;
  %viya_http(path=/forecastingDataDefinition/dataDefinitions/&vf_dd_id/tableDefinitions, quiet=1)
  %viya_json(lib=jt)
  proc sql noprint; select id into :vf_td_id trimmed from jt.items where tableClass='INPUT' and tableType='TIMESERIES'; quit;
  libname jt clear;
  %put NOTE: [vf] dataDefinition=&vf_dd_id inputTable=&vf_td_id;

  %vf_set_role(&target, dependent, agg=&target_accumulate, miss=&target_missing)
  /* indep_accumulate / indep_missing: one value for all independents, or a
     parallel list (same order as independents=); a short list falls back to
     its first value for the remaining variables */
  %let n = %sysfunc(countw(&independents));
  %do i = 1 %to &n;
    %let v = %scan(&independents, &i);
    %let ia = %scan(&indep_accumulate, &i); %if %length(&ia) = 0 %then %let ia = %scan(&indep_accumulate, 1);
    %let im = %scan(&indep_missing, &i);    %if %length(&im) = 0 %then %let im = %scan(&indep_missing, 1);
    %vf_set_role(&v, independent, agg=&ia, miss=&im, sysgen=&indep_in_auto_models)
  %end;
  %let n = %sysfunc(countw(&by_vars));
  %do i = 1 %to &n;
    %let v = %scan(&by_vars, &i);
    %vf_set_role(&v, byVar)
  %end;

  /*----------------------------------------------------------------------
    3. hierarchy: the provider pre-creates one; PUT the varList into it
  ----------------------------------------------------------------------*/
  %viya_http(path=/forecastingDataDefinition/dataDefinitions/&vf_dd_id/hierarchies, quiet=1)
  %viya_json(lib=jh) %viya_scalar(lib=jh, table=items, var=id, into=hid) libname jh clear;
  %viya_http(path=/forecastingDataDefinition/dataDefinitions/&vf_dd_id/hierarchies/&hid,
             accept=application/vnd.sas.analytics.forecasting.hierarchy+json, out=vraw, quiet=1)
  data _null_;
    infile vraw lrecl=32767 truncover; input line $32767.; file body;
    length vl $2000;
    vl = '"' || tranwrd(compbl("&by_vars"), ' ', '","') || '"';
    line = prxchange('s/"varList":\[[^\]]*\]/"varList":[' || strip(vl) || ']/', 1, line);
    line = prxchange("s/\x22reconciliationLevel\x22:\d+/\x22reconciliationLevel\x22:&reconciliation_level/", 1, line);
    put line;
  run;
  %viya_http(method=PUT, path=/forecastingDataDefinition/dataDefinitions/&vf_dd_id/hierarchies/&hid, in=body,
             in_type=application/vnd.sas.analytics.forecasting.hierarchy+json,
             accept=application/vnd.sas.analytics.forecasting.hierarchy+json, ifmatch=&viya_etag)
  %put NOTE: [vf] hierarchy = &by_vars (reconcile at level &reconciliation_level);

  /*----------------------------------------------------------------------
    4. load data, check the data definition
  ----------------------------------------------------------------------*/
  %viya_http(method=PUT, path=/forecastingGateway/projects/&vf_project_id/dataState?value=loaded, expect=200 204)
  %let rc = %sysfunc(sleep(5,1));

  /* the load resets reconciliationLevel to 0 — re-apply it afterwards */
  %viya_http(path=/forecastingDataDefinition/dataDefinitions/&vf_dd_id/hierarchies/&hid,
             accept=application/vnd.sas.analytics.forecasting.hierarchy+json, out=vraw, quiet=1)
  data _null_;
    infile vraw lrecl=32767 truncover; input line $32767.; file body;
    line = prxchange("s/\x22reconciliationLevel\x22:\d+/\x22reconciliationLevel\x22:&reconciliation_level/", 1, line);
    put line;
  run;
  %viya_http(method=PUT, path=/forecastingDataDefinition/dataDefinitions/&vf_dd_id/hierarchies/&hid, in=body,
             in_type=application/vnd.sas.analytics.forecasting.hierarchy+json,
             accept=application/vnd.sas.analytics.forecasting.hierarchy+json, ifmatch=&viya_etag, quiet=1)
  %viya_json(lib=jh) %viya_scalar(lib=jh, var=reconciliationLevel, into=vf_recon) libname jh clear;
  %put NOTE: [vf] reconciliationLevel after load = &vf_recon (wanted &reconciliation_level);

  /* the holdback (back) in providerSpecificProperties is NOT honoured at
     create time — the project always starts with back=0. Apply it through
     the settings resource (GET -> edit -> PUT with If-Match). The service
     requires back < horizon (400 otherwise). */
  %if &back > 0 %then %do;
    %if &back >= &horizon %then %put WARNING: [vf] back=&back must be less than horizon=&horizon - the service rejects it, leaving back=0;
    %else %do;
      %viya_http(path=/forecastingGateway/projects/&vf_project_id/settings,
                 accept=application/vnd.sas.forecasting.project.settings+json, out=vraw, quiet=1)
      data _null_;
        infile vraw lrecl=32767 truncover; input line $32767.; file body;
        /* patterns in single quotes: the JSON keys carry double quotes, and an
           unbalanced double quote inside a macro definition swallows the rest
           of the program silently (found 2026-08-27) */
        line = prxchange(cats('s/"back":"\d+"/"back":"', "&back", '"/'), 1, line);
        line = prxchange('s/,"links":\[.*?\]//', 1, line);
        line = prxchange('s/,"(creationTimeStamp|modifiedTimeStamp)":"[^"]*"//', -1, line);
        put line;
      run;
      %viya_http(method=PUT, path=/forecastingGateway/projects/&vf_project_id/settings, in=body,
                 in_type=application/vnd.sas.forecasting.project.settings+json,
                 accept=application/vnd.sas.forecasting.project.settings+json, ifmatch=&viya_etag, expect=200, quiet=1)
      %viya_json(lib=js) %viya_scalar(lib=js, var=back, into=vf_back) libname js clear;
      %put NOTE: [vf] holdback (back) after settings PUT = &vf_back (wanted &back);
    %end;
  %end;

  %viya_http(path=/forecastingGateway/projects/&vf_project_id/dataDefinitions/@current,
             accept=application/vnd.sas.analytics.forecasting.data.definition+json, quiet=1)
  %viya_json(lib=jd)
  title "Data definition status";
  proc print data=jd.status noobs; run;
  proc print data=jd.root noobs; var name caslibName hierarchyForecasting singleTimeSeries inputTablesUpToDate; run;
  title;
  libname jd clear;
%end;

/*------------------------------------------------------------------------
  5. pipelines  (both paths arrive here: freshly created and reused
     projects). A new project has one auto-created pipeline, "Pipeline 1",
     derived from the Auto-forecasting template. Everything here is
     idempotent by pipeline name, so reuse runs are safe.
------------------------------------------------------------------------*/
%let p3 = application/vnd.sas.analytics.pipeline+json%str(;)version=3;   /* the only representation the service accepts */
filename tpl temp;

/* 5a. rename "Pipeline 1" (JSON patch, If-Match) */
%if %length(&pipeline_name) %then %do;
  %viya_http(path=/analyticsGateway/projects/&vf_project_id/pipelines, quiet=1)
  %viya_json(lib=jl)
  %local p1id;
  proc sql noprint; select id into :p1id trimmed from jl.items where name='Pipeline 1'; quit;
  libname jl clear;
  %if %length(&p1id) %then %do;
    %viya_http(path=/analyticsGateway/projects/&vf_project_id/pipelines/&p1id, accept=&p3, out=vraw, quiet=1)
    data _null_; file body; put '[{"op":"replace","path":"/name","value":"' "&pipeline_name" '"}]'; run;
    %viya_http(method=PATCH, path=/analyticsGateway/projects/&vf_project_id/pipelines/&p1id, in=body,
               in_type=application/json-patch+json, accept=&p3, ifmatch=&viya_etag, expect=200, quiet=1)
    %put NOTE: [vf] renamed "Pipeline 1" -> "&pipeline_name" (&viya_rc);
  %end;
%end;

/* 5b. add pipelines from templates: GET the template, cut out its
       balanced "prototype":{...} object, append the name, POST it */
%macro vf_add_pipeline(template=, name=);
  %local exists;
  %viya_http(path=/analyticsGateway/projects/&vf_project_id/pipelines, quiet=1)
  %viya_json(lib=jl)
  proc sql noprint; select id into :exists trimmed from jl.items where name="&name"; quit;
  libname jl clear;
  %if %length(&exists) %then %do; %put NOTE: [vf] pipeline "&name" already exists (&exists) - skipped; %return; %end;
  %viya_http(path=/analyticsGateway/pipelineTemplates/&template, out=tpl, quiet=1)
  %if not &viya_ok %then %do; %put ERROR: [vf] template &template not found; %return; %end;
  /* stream the template byte by byte (no 32,767-char variable), copy the
     balanced "prototype":{...} object to the request file, and append a
     duplicate "name" key before its closing brace (the service keeps the
     last value) */
  %let vf_tpl_ok = 0;
  data _null_;
    infile tpl recfm=n; file body recfm=n;
    length c $1 buf $12;
    retain buf '            ' found 0 started 0 depth 0 instr 0 esc 0 done 0;
    input c $char1.;
    if done then return;
    if not found then do;                       /* look for the 12-char key "prototype": */
      buf = substr(buf, 2) || c;
      if buf = '"prototype":' then found = 1;
      return;
    end;
    if not started then do;                     /* skip to the object's opening brace */
      if c = '{' then do; started = 1; depth = 1; put c $char1.; end;
      return;
    end;
    if instr then do;
      if esc then esc = 0; else if c = '\' then esc = 1; else if c = '"' then instr = 0;
      put c $char1.; return;
    end;
    if c = '"' then instr = 1;
    else if c = '{' then depth + 1;
    else if c = '}' then do;
      depth + (-1);
      if depth = 0 then do;
        put ',"name":"' "&name" '"}';
        done = 1; call symputx('vf_tpl_ok', 1, 'G'); return;
      end;
    end;
    put c $char1.;
  run;
  %if &vf_tpl_ok ne 1 %then %do; %put ERROR: [vf] could not isolate the prototype object in template &template; %return; %end;
  %viya_http(method=POST, path=/analyticsGateway/projects/&vf_project_id/pipelines, in=body, in_type=&p3, accept=&p3, expect=201, quiet=1)
  %put NOTE: [vf] add pipeline "&name" from &template -> &viya_rc;
%mend vf_add_pipeline;

%local nt t nm;
%let nt = %sysfunc(countw(&add_templates, %str( )));
%do i = 1 %to &nt;
  %let t  = %scan(&add_templates, &i, %str( ));
  %let nm = %scan(&add_names, &i, |);
  %if %length(&nm) = 0 %then %let nm = &t;
  %vf_add_pipeline(template=&t, name=&nm)
%end;

/* final pipeline list */
%viya_http(path=/analyticsGateway/projects/&vf_project_id/pipelines, quiet=1)
%viya_json(lib=jl)
title "Pipelines in project &vf_project_id"; proc print data=jl.items noobs; var id name; run; title;
proc sql noprint;
  select id into :vf_pipeline_id trimmed from jl.items(obs=1);
  select id into :vf_pipeline_ids separated by ' ' from jl.items;
quit;
libname jl clear;

/*------------------------------------------------------------------------
  6. run the pipelines
------------------------------------------------------------------------*/
%let vf_job_state = ;
%if &run_pipelines ne none %then %do;
  %local np pid_i jobs jobid j;
  %let jobs = ;
  %let np = %sysfunc(countw(&vf_pipeline_ids, %str( )));
  %if &run_pipelines = first %then %let np = 1;
  %do i = 1 %to &np;
    %let pid_i = %scan(&vf_pipeline_ids, &i, %str( ));
    %viya_http(method=POST, path=/analyticsGateway/projects/&vf_project_id/pipelines/&pid_i/jobs, expect=200 201 202, quiet=1)
    %viya_json(lib=jj) %viya_scalar(lib=jj, var=id, into=jobid) libname jj clear;
    %if %length(&jobid) %then %do;
      %let jobs = &jobs &jobid;
      %put NOTE: [vf] pipeline &pid_i -> job &jobid started;
    %end;
    %else %put ERROR: [vf] pipeline &pid_i did not start (&viya_rc);
  %end;
  %if &wait_for_job %then %do;
    %do j = 1 %to %sysfunc(countw(&jobs, %str( )));
      %viya_wait(path=/jobExecution/jobs/%scan(&jobs, &j, %str( )), state_var=state, interval=&poll_interval, max_wait=&max_wait)
      %let vf_job_state = &vf_job_state &viya_state;
    %end;
  %end;
  %else %let vf_job_state = started (not waited);
%end;

/*------------------------------------------------------------------------
  7. results: pipeline comparison, one row per completed pipeline
------------------------------------------------------------------------*/
%if &run_pipelines = none or &wait_for_job %then %do;
  %viya_http(path=/forecastingGateway/projects/&vf_project_id/pipelineComparison/table, expect=200 404, quiet=1)
  %if &viya_rc = 200 %then %do;
    %viya_json(lib=jc)
    /* the JSON engine flattens each row's cells[] array into table ITEMS_CELLS
       (one row per pipeline, columns cells1..cells9); column order is fixed
       by the service: isChampion, PIPELINE_NAME, WMAE, WMAPE, WMASE, WASE,
       WRMSE, WAPE, id */
    %local rowtab;
    proc sql noprint; select memname into :rowtab trimmed from dictionary.tables
      where libname='JC' and memname = 'ITEMS_CELLS'; quit;
    %if %length(&rowtab) %then %do;
    data _vf_cmp;
      set jc.&rowtab;
      length champion $5 pipeline $60;
      champion = cells1; pipeline = cells2;
      WMAE = input(cells3, best.); WMAPE = input(cells4, best.); WMASE = input(cells5, best.);
      WASE = input(cells6, best.); WRMSE = input(cells7, best.); WAPE = input(cells8, best.);
      keep champion pipeline WMAE WMAPE WMASE WASE WRMSE WAPE;
    run;
    %end;
    %else %do;
      %put WARNING: [vf] comparison rows table not found; printing raw ALLDATA;
      data _vf_cmp; set jc.alldata; where V=1 and lowcase(P4)='cells'; run;
    %end;
    title "Pipeline comparison - &project_name";
    proc print data=_vf_cmp noobs; format WMAE WRMSE comma12.1 WMAPE WMASE WASE 8.3 WAPE percent8.2; run;
    title;
    libname jc clear;
  %end;
  %else %put NOTE: [vf] no pipeline comparison yet (&viya_rc);
%end;

%put NOTE: [vf] ============================================================;
%put NOTE: [vf] project   : &project_name;
%put NOTE: [vf] id        : &vf_project_id;
%put NOTE: [vf] pipelines : &vf_pipeline_ids;
%put NOTE: [vf] job state : &vf_job_state;
%put NOTE: [vf] open in Model Studio: &viya_base/SASModelStudio/?projectId=&vf_project_id;
%put NOTE: [vf] ============================================================;
filename body clear; filename vraw clear; filename tpl clear;
%mend build_vf_project;

/* Run with the defaults (= projects/mfg_demand.yml), unless the caller
   set  %let vf_skip_autorun = 1;  before %including this file in order to
   call %build_vf_project(...) with overrides. */
%macro _vf_autorun; %if not %symexist(vf_skip_autorun) %then %do; %build_vf_project() %end; %mend;
%_vf_autorun
