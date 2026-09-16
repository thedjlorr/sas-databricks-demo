/*--------------------------------------------------------------------------
  viya_rest.sas
  Project : MCP_Forecasting  (shared helper library — %include before use)
  Purpose : Thin, reusable wrappers around PROC HTTP for calling SAS Viya
            REST services from a compute session.

            Authentication is the session's own identity
            (oauth_bearer=sas_services) — no tokens, no .env. The base URL
            comes from the SERVICESBASEURL option. Works identically in
            SAS Studio, batch, and the MCP connector's compute session.

  Macros  :
    %viya_http(method=, path=, in=, in_type=, accept=, out=, expect=)
        One REST call. Body from fileref &in (optional). Response body in
        fileref &out (default RESP). Sets globals:
          viya_rc      HTTP status code
          viya_ok      1 if status is in &expect, else 0
          viya_etag    ETag response header (for If-Match updates)
          viya_location Location header (new-resource URI on 201)
        On failure prints the first part of the response body to the log.
    %viya_json(out=, lib=)     assign a JSON libref &lib on fileref &out
    %viya_scalar(lib=, table=, var=, into=, where=)
        pull one value from a JSON libref table into macro var &into (G)
    %viya_wait(path=, state_var=, done=, interval=, max_wait=)
        poll a resource until its &state_var is in &done; sets viya_state
  Notes   : keep all names in keyword parameters; nothing here is
            dataset-specific.
--------------------------------------------------------------------------*/

%macro viya_http(
   method  = GET,                       /* GET POST PUT PATCH DELETE          */
   path    = ,                          /* e.g. /analyticsGateway/projects    */
   in      = ,                          /* fileref holding the request body   */
   in_type = application/json,          /* Content-Type when &in is given     */
   accept  = application/json,          /* Accept header                      */
   out     = resp,                      /* fileref for the response body      */
   ifmatch = ,                          /* ETag for PUT/PATCH updates         */
   expect  = 200 201 202 204,           /* status codes treated as success    */
   quiet   = 0                          /* 1 = no log line on success         */
);
%global viya_rc viya_ok viya_etag viya_location viya_base;
%local hdrs;
%if %length(&viya_base) = 0 %then %let viya_base = %sysfunc(getoption(SERVICESBASEURL));
%if %sysfunc(fexist(&out)) = 0 %then %do; filename &out temp; %end;
filename _vhdr temp;

proc http method="&method"
   url="&viya_base.&path"
   oauth_bearer=sas_services
   %if %length(&in) %then %do; in=&in ct="&in_type" %end;
   out=&out
   headerout=_vhdr headerout_overwrite;
   headers "Accept"="&accept"
   /* body-less POST/PUT: PROC HTTP would default to form-urlencoded, which
      Viya services reject (415) — send an explicit Content-Type instead */
   %if %length(&in) = 0 and (%upcase(&method) = POST or %upcase(&method) = PUT or %upcase(&method) = PATCH) %then %do;
      "Content-Type"="&in_type"
   %end;
   /* ETags contain double quotes (W/"123"), so single-quote the value */
   %if %length(&ifmatch) %then %do; "If-Match"=%tslit(&ifmatch) %end;
   ;
run;

%let viya_rc = &SYS_PROCHTTP_STATUS_CODE;
%let viya_ok = %eval(%index( &expect , &viya_rc ) > 0);

/* harvest ETag / Location from the response headers */
%let viya_etag = ; %let viya_location = ;
data _null_;
   infile _vhdr truncover;
   input line $2000.;
   if upcase(scan(line,1,':')) = 'ETAG'     then call symputx('viya_etag',     strip(substr(line, index(line,':')+1)), 'G');
   if upcase(scan(line,1,':')) = 'LOCATION' then call symputx('viya_location', strip(substr(line, index(line,':')+1)), 'G');
run;
filename _vhdr clear;

%if &viya_ok %then %do;
   %if not &quiet %then %put NOTE: [viya] &method &path -> &viya_rc;
%end;
%else %do;
   %put ERROR: [viya] &method &path -> &viya_rc &SYS_PROCHTTP_STATUS_PHRASE (expected &expect);
   data _null_; infile &out lrecl=32767 truncover obs=5; input line $32767.; put "ERROR- [viya] body: " line; run;
%end;
%mend viya_http;


%macro viya_json(out=resp, lib=j);
libname &lib clear;
libname &lib json fileref=&out;
%mend viya_json;


%macro viya_scalar(lib=j, table=root, var=, into=, where=);
/* write into the caller's variable if it exists (local or global);
   only create a global when nothing of that name exists yet */
%if not %symexist(&into) %then %global &into;
%let &into = ;
proc sql noprint;
   select &var into :&into trimmed
   from &lib..&table
   %if %length(&where) %then %do; where &where %end;
   ;
quit;
%mend viya_scalar;


%macro viya_wait(
   path      = ,                        /* resource to poll (GET)             */
   state_var = state,                   /* JSON field holding the state       */
   done      = completed failed canceled cancelled timedOut error,
   interval  = 5,                       /* seconds between polls              */
   max_wait  = 3600                     /* give up after this many seconds    */
);
%global viya_state;
%local waited;
%let waited = 0; %let viya_state = ;
%if %length(&path) = 0 or %qsubstr(&path, %length(&path), 1) = %str(/) %then %do;
   %put ERROR: [viya] viya_wait: empty resource id in path "&path" - nothing to wait for;
   %let viya_state = error;
   %return;
%end;
%do %until (%index( %lowcase(&done) , %lowcase(&viya_state) ) > 0 or &waited >= &max_wait);
   %viya_http(method=GET, path=&path, out=_vw, quiet=1)
   %viya_json(out=_vw, lib=_vw)
   %viya_scalar(lib=_vw, table=root, var=&state_var, into=viya_state)
   libname _vw clear;
   %if %index( %lowcase(&done) , %lowcase(&viya_state) ) = 0 %then %do;
      %put NOTE: [viya] waiting: &path state=&viya_state (&waited s);
      %let rc = %sysfunc(sleep(&interval, 1));
      %let waited = %eval(&waited + &interval);
   %end;
%end;
%put NOTE: [viya] &path final state=&viya_state after &waited s;
%mend viya_wait;
