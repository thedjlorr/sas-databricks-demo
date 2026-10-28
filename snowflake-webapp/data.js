// Snowflake catalog: RND_DB.SEFORD as read through SNOWLIB on Viya, 27 Oct 2026 (INFORMATION_SCHEMA via pass-through).
// The three NMAC_AUTO_ tables hold the synthetic NMAC-style auto loan book built by sas/06_nmac_auto_data.sas.
window.SF_TABLES = [
  { name: "NMAC_AUTO_LOANS", rows: 8853, cols: 23, created: "2026-10-27", role: "nmac", note: "One row per auto loan: borrower, vehicle, dealer, terms, credit tier, current status and balance. 7,500 customers with 1 to 3 loans each." },
  { name: "NMAC_AUTO_SNAPSHOT", rows: 18214, cols: 16, created: "2026-10-27", role: "nmac", note: "Loan features at four month-ends. Three past snapshots carry the 12-month outcome DEFAULT_12M (model training); 30 Sep 2026 is the live book to score." },
  { name: "NMAC_AUTO_MONTHLY", rows: 36, cols: 7, created: "2026-10-27", role: "nmac", note: "36 months of portfolio delinquency (Oct 2023 to Sep 2026). History for the ETS forecast." },
  { name: "COLLECTIONS_DATA4X", rows: 13494, cols: 43, created: "2026-10-26", role: "legacy", note: "Earlier demo table. Rows come in duplicated pairs and its customer key groups different borrowers, so it is not used." },
  { name: "NMAC_MODELING", rows: 1000, cols: 39, created: "2026-10-02", role: "legacy", note: "Earlier 1,000-loan synthetic table. Not used." },
  { name: "AUTOLOAN", rows: 5960, cols: 18, created: "2025-07-01", role: "sandbox", note: "Auto loan sample." },
  { name: "IDMMHMEQ_CUSTID", rows: 4232, cols: 14, created: "2024-11-11", role: "sandbox", note: "Home equity sample with customer id." },
  { name: "IDMMHMEQ_CUSTID_TEST", rows: 10, cols: 14, created: "2024-11-11", role: "sandbox", note: "" },
  { name: "LGB_PARAMS", rows: 1, cols: 19, created: "2025-07-02", role: "sandbox", note: "LightGBM parameters." },
  { name: "LGB_VALIDATION", rows: 1633, cols: 19, created: "2025-07-02", role: "sandbox", note: "LightGBM validation set." },
  { name: "DM_ORDER", rows: 137466, cols: 17, created: "2025-01-10", role: "sandbox", note: "Order history." },
  { name: "SIMULATED_DATES", rows: 100000, cols: 2, created: "2025-05-30", role: "sandbox", note: "" },
  { name: "MOVIE_TITLES", rows: 17770, cols: 3, created: "2024-12-04", role: "sandbox", note: "" },
  { name: "WINE_QUALITY", rows: 6497, cols: 13, created: "2024-11-22", role: "sandbox", note: "" },
  { name: "WINE_QUALITY_TEST", rows: 10, cols: 13, created: "2024-11-22", role: "sandbox", note: "" },
  { name: "GOOGLE_ANALYTICS_TEST", rows: 2482, cols: 19, created: "2024-05-16", role: "sandbox", note: "" },
  { name: "BASEBALL", rows: 322, cols: 24, created: "2024-11-20", role: "sandbox", note: "" },
  { name: "BASEBALL_TEST", rows: 10, cols: 24, created: "2024-11-18", role: "sandbox", note: "" },
  { name: "CARS", rows: 428, cols: 15, created: "2024-05-13", role: "sandbox", note: "" },
  { name: "CARS_TESTING", rows: 0, cols: 15, created: "2025-02-14", role: "sandbox", note: "" },
  { name: "AIRLINE_TESTING", rows: 144, cols: 3, created: "2025-02-14", role: "sandbox", note: "" },
  { name: "AIR_TESTING", rows: 0, cols: 2, created: "2025-02-17", role: "sandbox", note: "" },
  { name: "GAS_TESTING", rows: 0, cols: 4, created: "2025-03-14", role: "sandbox", note: "" },
  { name: "DOW_TEST", rows: 4, cols: 5, created: "2025-03-12", role: "sandbox", note: "" },
  { name: "TEST", rows: 2, cols: 2, created: "2025-03-12", role: "sandbox", note: "" }
];

// Column lists as reported by CAS through SNOWLIB (get_castable_columns).
window.SF_COLUMNS = {
  NMAC_AUTO_LOANS: [["loan_id","varchar"],["customer_id","varchar"],["dealer_id","varchar"],["state","varchar"],["brand","varchar"],["model","varchar"],["product","varchar"],["orig_date","date"],["term","double"],["amount_financed","double"],["apr","double"],["monthly_payment","double"],["credit_score","double"],["credit_tier","varchar"],["ltv","double"],["dti","double"],["pti","double"],["income","double"],["age","double"],["employment","varchar"],["home_ownership","varchar"],["loan_status","varchar"],["balance_current","double"]],
  NMAC_AUTO_SNAPSHOT: [["snapshot_date","date"],["loan_id","varchar"],["customer_id","varchar"],["mob","double"],["balance","double"],["dpd","double"],["dpd_bucket","varchar"],["delinq_30","double"],["n30_12m","double"],["max_dpd_6m","double"],["contacts_90d","double"],["promise_to_pay","double"],["broken_promise","double"],["autopay","double"],["payment_ratio","double"],["default_12m","double"]],
  NMAC_AUTO_MONTHLY: [["month_end","date"],["active_loans","double"],["delinquent_30","double"],["delinquency_rate","double"],["balance_active","double"],["balance_30plus","double"],["new_chargeoffs","double"]]
};

// Logical architecture: what lives where, and what Viya creates.
window.LAYERS = [
  { id: "sf", title: "1  Snowflake", sub: "RND_DB.SEFORD", tone: "snow", items: [
    { name: "NMAC_AUTO_LOANS", meta: "8,853 loans, 7,500 customers", tag: "source" },
    { name: "NMAC_AUTO_SNAPSHOT", meta: "18,214 loan-month rows", tag: "source" },
    { name: "NMAC_AUTO_MONTHLY", meta: "36 months of delinquency", tag: "source" },
    { name: "+ 22 other tables", meta: "sandbox and earlier demos", tag: "source" } ] },
  { id: "lib", title: "2  SNOWLIB caslib", sub: "SAS Data Connector to Snowflake", tone: "conn", items: [
    { name: "Live read", meta: "queries push down to Snowflake", tag: "access" },
    { name: "Pass-through SQL", meta: "counts computed inside Snowflake", tag: "access" },
    { name: "Credentials masked", meta: "global, permanent caslib", tag: "access" } ] },
  { id: "cas", title: "3  SAS Viya (CAS)", sub: "CASUSER, in memory", tone: "viya", items: [
    { name: "WEB_SF_LOANS / _SNAPSHOT", meta: "loaded copies of the Snowflake tables", tag: "created" },
    { name: "WEB_SF_SCORED", meta: "default probability for every loan-month", tag: "created" },
    { name: "WEB_SF_LIVE", meta: "5,148 live loans: PD, risk band, expected loss", tag: "created" },
    { name: "Report tables", meta: "tier, band, heatmap, dealer, worklist, forecast", tag: "created" } ] },
  { id: "out", title: "4  Take action", sub: "Decisions and reporting", tone: "act", items: [
    { name: "SEFORD.NMAC_AUTO_SCORES", meta: "scores written back to Snowflake", tag: "target" },
    { name: "Visual Analytics", meta: "report pages on the CAS tables", tag: "report" },
    { name: "Intelligent Decisioning", meta: "collector queues (next step)", tag: "target" },
    { name: "Model Manager", meta: "champion / challenger (next step)", tag: "target" } ] }
];
