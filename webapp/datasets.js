/* Real dataset inventory, read from the live environment on 9 October 2026.
   Databricks: 25 tables in the default schema (rows from count(*), columns from the SAS dictionary).
   CAS: 13 files in caslib P_LORH (not loaded into memory; sizes are file sizes on disk). */
window.DATASETS = {
 "checked": "2026-10-09",
 "databricks": {
  "library": "DB_TEST",
  "schema": "default",
  "tables": [
   {
    "name": "ACCOUNT_SUMMARY",
    "cols": 15,
    "rows": 13494,
    "group": "Collections and credit"
   },
   {
    "name": "AUTOLOAN_1",
    "cols": 14,
    "rows": 5960,
    "group": "Loans"
   },
   {
    "name": "AUTO_LOAN_2",
    "cols": 13,
    "rows": 29,
    "group": "Loans"
   },
   {
    "name": "CUSTOMER_PROFILE",
    "cols": 10,
    "rows": 13494,
    "group": "Collections and credit"
   },
   {
    "name": "DEF_PRED",
    "cols": 87,
    "rows": 13494,
    "group": "Collections and credit"
   },
   {
    "name": "FINANCIAL_TRANSACTIONS",
    "cols": 23,
    "rows": 13494,
    "group": "Collections and credit"
   },
   {
    "name": "HMEQ",
    "cols": 13,
    "rows": 5960,
    "group": "Loans"
   },
   {
    "name": "HMEQ_ID",
    "cols": 14,
    "rows": 5960,
    "group": "Loans"
   },
   {
    "name": "HOME_EQUITY_LOANID",
    "cols": 15,
    "rows": 5960,
    "group": "Loans"
   },
   {
    "name": "LOAN_DATA_SET_CSV",
    "cols": 13,
    "rows": 614,
    "group": "Loans"
   },
   {
    "name": "MAC1_SENSOR_1_CSV",
    "cols": 7,
    "rows": 50,
    "group": "Sensor data"
   },
   {
    "name": "MAC2_SENSOR_1_CSV",
    "cols": 7,
    "rows": 50,
    "group": "Sensor data"
   },
   {
    "name": "MAC3_SENSOR_CSV",
    "cols": 7,
    "rows": 50,
    "group": "Sensor data"
   },
   {
    "name": "MACHINE1_SENSOR_DATA_2_CSV",
    "cols": 7,
    "rows": 50,
    "group": "Sensor data"
   },
   {
    "name": "MACHINE2_SENSOR_DATA_2_CSV",
    "cols": 7,
    "rows": 50,
    "group": "Sensor data"
   },
   {
    "name": "MACHINE3_SENSOR_DATA_1_CSV",
    "cols": 7,
    "rows": 50,
    "group": "Sensor data"
   },
   {
    "name": "MGM_1",
    "cols": 15,
    "rows": 10000,
    "group": "Other"
   },
   {
    "name": "MGM_CUST_3",
    "cols": 31,
    "rows": 50000,
    "group": "Other"
   },
   {
    "name": "SCALATABLE",
    "cols": 5,
    "rows": 5,
    "group": "Reference and test"
   },
   {
    "name": "SCALATABLE2",
    "cols": 5,
    "rows": 5,
    "group": "Reference and test"
   },
   {
    "name": "SCALATABLE3",
    "cols": 5,
    "rows": 5,
    "group": "Reference and test"
   },
   {
    "name": "STATE_EXP",
    "cols": 3,
    "rows": 51,
    "group": "Reference and test"
   },
   {
    "name": "STATE_EXP2",
    "cols": 3,
    "rows": 51,
    "group": "Reference and test"
   },
   {
    "name": "TEST",
    "cols": 5,
    "rows": 19,
    "group": "Reference and test"
   },
   {
    "name": "TEST_FILE",
    "cols": 12,
    "rows": 29222,
    "group": "Reference and test"
   }
  ]
 },
 "cas": {
  "caslib": "P_LORH",
  "tables": [
   {
    "name": "PRICEDATA",
    "bytes": 270749824
   },
   {
    "name": "HISTORICAL PRODUCT DEMAND",
    "bytes": 116304176
   },
   {
    "name": "PROD_DEMAND",
    "bytes": 116307520
   },
   {
    "name": "FINAL_DATA_DOE",
    "bytes": 27164208
   },
   {
    "name": "MONTH_DATA_COLL_OPT2",
    "bytes": 6312872
   },
   {
    "name": "HMEQ",
    "bytes": 794864
   },
   {
    "name": "HARLEYDOWN",
    "bytes": 227344
   },
   {
    "name": "HARLEY_WARRANTY_DATA",
    "bytes": 138448
   },
   {
    "name": "SUPPLIER_RISKV2",
    "bytes": 47456
   },
   {
    "name": "BRIDGE_WARTIRES2",
    "bytes": 37896
   },
   {
    "name": "SUPPLIER_NETWORK_NODES",
    "bytes": 13096
   },
   {
    "name": "SUPPLIER_NETWORK_EDGES",
    "bytes": 13088
   },
   {
    "name": "NODES_OUT",
    "bytes": 12760
   }
  ]
 }
};
