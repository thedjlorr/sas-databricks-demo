/*--------------------------------------------------------------------------
  06_nmac_auto_data.sas
  Project : NMAC Collections on Viya and Snowflake
  Purpose : Build a synthetic NMAC-style auto loan book with the right grain:
            one row per LOAN, 1 to 3 loans per customer, a balance per loan,
            dealers, credit tiers, and a month-by-month delinquency history.
            Replaces COLLECTIONS_DATA4X, whose rows are duplicated in pairs and
            whose customer key is a group, not a person.
  Runs in : Viya compute session + CAS. Reads nothing, writes to CASUSER only.

  Tables  : CASUSER.NMAC_LOANS     one row per loan (terms, borrower, dealer, final status)
            CASUSER.NMAC_SNAPSHOT  loan features at two month-ends:
                                   30SEP2024, 31MAR2025 and 30SEP2025 with the 12-month outcome DEFAULT_12M (train and validate)
                                   30SEP2026 without an outcome (the live book to score)
            CASUSER.NMAC_MONTHLY   36 months of portfolio delinquency for the ETS forecast

  Notes   : SYNTHETIC data, not NMAC data. Delinquency is a monthly roll model:
            current -> 30 -> 60 -> 90+ -> charge-off, with cures. DEFAULT_12M = the loan
            reaches 90+ days past due or charge-off in the 12 months after the snapshot.
            Month index 0 = Jan 2019, 92 = Sep 2026.
--------------------------------------------------------------------------*/
options obs=max nosyntaxcheck;

%macro nmac_build(seed=20261028, ncust=7500);
data work.nm_loans(keep=loan_id customer_id orig_date term product brand model dealer_id state credit_score credit_tier
                        apr amount_financed monthly_payment ltv dti pti income employment home_ownership age
                        loan_status balance_current)
     work.nm_snapshot(keep=snapshot_date loan_id customer_id mob balance dpd dpd_bucket delinq_30 n30_12m max_dpd_6m
                       contacts_90d promise_to_pay broken_promise autopay payment_ratio default_12m)
     work.nm_monthly(keep=month_end active_loans delinquent_30 delinquency_rate balance_active balance_30plus new_chargeoffs);
   call streaminit(&seed);
   length customer_id $7 loan_id $9 state $2 product $19 brand $8 model $10 dealer_id $4 credit_tier $11
          employment $13 home_ownership $8 loan_status $11 dpd_bucket $7;
   array st[13] $2 _temporary_ ('TX','CA','FL','GA','TN','NC','AZ','OH','IL','PA','VA','CO','MI');
   array deff[60] _temporary_;
   array hist[0:92] _temporary_;
   array c_act[0:92] _temporary_ (93*0);
   array c_30[0:92] _temporary_ (93*0);
   array b_act[0:92] _temporary_ (93*0);
   array b_30[0:92] _temporary_ (93*0);
   array c_co[0:92] _temporary_ (93*0);
   array seas[12] _temporary_ (.25 .22 .15 .0 -.05 -.1 -.1 -.05 .0 .05 .0 .12);
   do d = 1 to 60; deff[d] = rand('normal',0,.25); end;
   lnum = 0;
   do c = 1 to &ncust;
      customer_id = cats('C', put(c, z6.));
      age = round(min(75, max(21, rand('normal',43,12))));
      income = round(max(22000, exp(rand('normal', log(62000), .45))), 500);
      r = rand('uniform');
      if r < .80 then employment='Employed'; else if r < .90 then employment='Self-employed';
      else if r < .97 then employment='Retired'; else employment='Unemployed';
      r = rand('uniform');
      if r < .42 then home_ownership='Own'; else if r < .80 then home_ownership='Rent'; else home_ownership='Mortgage';
      cust_score = round(min(840, max(500, rand('normal',705,72))));
      state = st[ceil(rand('uniform')*13)];
      nl = 1 + (rand('uniform') < .15) + (rand('uniform') < .03);
      do k = 1 to nl;
         lnum + 1;
         loan_id = cats('NL', put(lnum, z7.));
         orig_idx = min(92, floor(93*(rand('uniform')**0.7)));
         orig_date = intnx('month', '01JAN2019'd, orig_idx, 'end');
         r = rand('uniform');
         if r < .48 then product='New Retail'; else if r < .80 then product='Used Retail'; else product='Certified Pre-Owned';
         if rand('uniform') < .78 then do;
            brand='Nissan';
            model = scan('Altima Rogue Sentra Pathfinder Frontier Kicks Murano Versa', ceil(rand('uniform')*8), ' ');
         end;
         else do;
            brand='INFINITI';
            model = scan('QX50 Q50 QX60 QX80 Q60', ceil(rand('uniform')*5), ' ');
         end;
         if product='New Retail' then amt = rand('normal',36500,9000);
         else if product='Used Retail' then amt = rand('normal',24500,7000);
         else amt = rand('normal',29500,7500);
         if brand='INFINITI' then amt = amt*1.32;
         amount_financed = round(min(85000, max(9000, amt)), 100);
         r = rand('uniform');
         if r < .07 then term=36; else if r < .22 then term=48; else if r < .66 then term=60; else term=72;
         credit_score = round(min(840, max(500, cust_score + rand('normal',0,12))));
         if credit_score >= 740 then credit_tier='Super Prime'; else if credit_score >= 680 then credit_tier='Prime';
         else if credit_score >= 620 then credit_tier='Near Prime'; else credit_tier='Subprime';
         used = (product ne 'New Retail');
         apr = min(.219, max(.029, .033 + max(0, 740-credit_score)*.00058 + used*.012 + rand('normal',0,.005)));
         i12 = apr/12;
         monthly_payment = round(amount_financed*i12/(1-(1+i12)**(-term)), .01);
         ltv = min(1.5, max(.65, rand('normal',1.0,.13) + used*.04 + (credit_score<620)*.08));
         dti = min(.65, max(.08, rand('normal',.33,.10) + (credit_score<620)*.05));
         pti = monthly_payment / (income/12);
         dealer_n = ceil(rand('uniform')*60);
         dealer_id = cats('D', put(dealer_n, z3.));
         frail = rand('normal',0,.35);
         autopay0 = (rand('uniform') < .55);

         do m = 0 to 92; hist[m] = -1; end;
         s = 0; loan_status = 'Active';
         last_m = min(92, orig_idx + term - 1);
         do m = orig_idx to last_m;
            hist[m] = s;
            if s = 4 then do; loan_status = 'Charged off'; leave; end;
            if m = last_m then do; if m < 92 then loan_status = 'Matured'; leave; end;
            mob = m - orig_idx;
            if s = 0 then do;
               if rand('uniform') < .009 then do; loan_status = 'Paid off'; leave; end;
               if mob < 4 then mt = -1.4; else if mob < 12 then mt = -.25; else if mob < 36 then mt = .2; else mt = -.1;
               macro = .006 * max(0, m + 1 - 57);
               lg = -5.45 + .016*(700-credit_score) + 1.4*(ltv-1) + 3*(pti-.12) + deff[dealer_n] + frail
                    + .22*used + .2*(term=72) + seas[mod(m+1,12)+1] + macro + mt;
               if rand('uniform') < 1/(1+exp(-lg)) then s = 1;
            end;
            else if s = 1 then do; u = rand('uniform'); if u < .50 then s = 0; else if u < .80 then s = 2; end;
            else if s = 2 then do; u = rand('uniform'); if u < .25 then s = 0; else if u < .70 then s = 3; end;
            else if s = 3 then do; u = rand('uniform'); if u < .08 then s = 0; else if u < .48 then s = 4; end;
         end;

         /* portfolio counters for the monthly series */
         do m = 57 to 92;
            if hist[m] >= 0 and hist[m] < 4 then do;
               kk = m - orig_idx;
               bal = amount_financed*((1+i12)**term - (1+i12)**kk)/((1+i12)**term - 1);
               c_act[m] + 1; b_act[m] + bal;
               if hist[m] >= 1 then do; c_30[m] + 1; b_30[m] + bal; end;
            end;
            if hist[m] = 4 and hist[m-1] ne 4 then c_co[m] + 1;
         end;

         /* snapshot rows at 30SEP2024, 31MAR2025, 30SEP2025 (indexes 68, 74, 80: outcome known) and 30SEP2026 (index 92: live book) */
         do m = 68, 74, 80, 92;
            if hist[m] >= 0 and hist[m] < 4 then do;
               s = hist[m];
               snapshot_date = intnx('month', '01JAN2019'd, m, 'end');
               mob = m - orig_idx;
               kk = m - orig_idx;
               balance = round(amount_financed*((1+i12)**term - (1+i12)**kk)/((1+i12)**term - 1), .01);
               n30_12m = 0; mx6 = 0;
               do j = max(orig_idx, m-11) to m;
                  if hist[j] >= 1 and hist[j] < 4 then n30_12m + 1;
                  if j >= m-5 and hist[j] > mx6 then mx6 = min(hist[j],3);
               end;
               if s = 0 then dpd = 0; else if s = 1 then dpd = 30 + floor(rand('uniform')*30);
               else if s = 2 then dpd = 60 + floor(rand('uniform')*30); else dpd = 90 + floor(rand('uniform')*60);
               if dpd = 0 then dpd_bucket='Current'; else if dpd < 60 then dpd_bucket='30-59'; else if dpd < 90 then dpd_bucket='60-89'; else dpd_bucket='90+';
               delinq_30 = (s >= 1);
               max_dpd_6m = choosen(mx6+1, 0, 30, 60, 90);
               contacts_90d = rand('poisson', .15 + 1.4*(s>=1) + .8*(s>=2) + .5*(s>=3) + .3*(n30_12m>0));
               promise_to_pay = (s >= 1 and rand('uniform') < .35);
               broken_promise = (promise_to_pay and rand('uniform') < .45);
               autopay = (autopay0 and not (n30_12m > 0 and rand('uniform') < .5));
               if s = 0 then payment_ratio = round(min(1.2, max(.9, rand('normal',1.0,.04))), .01);
               else payment_ratio = round(min(1, max(0, rand('normal', .55 - .1*(s-1), .25))), .01);
               default_12m = .;
               if m + 12 <= 92 then do;
                  default_12m = 0;
                  do j = m+1 to m+12; if hist[j] >= 3 then default_12m = 1; end;
               end;
               output work.nm_snapshot;
            end;
         end;

         if hist[92] >= 0 and hist[92] < 4 then do;
            kk = 92 - orig_idx;
            balance_current = round(amount_financed*((1+i12)**term - (1+i12)**kk)/((1+i12)**term - 1), .01);
         end;
         else balance_current = 0;
         output work.nm_loans;
      end;
   end;
   do m = 57 to 92;
      month_end = intnx('month', '01JAN2019'd, m, 'end');
      active_loans = c_act[m]; delinquent_30 = c_30[m]; delinquency_rate = delinquent_30/active_loans;
      balance_active = b_act[m]; balance_30plus = b_30[m]; new_chargeoffs = c_co[m];
      output work.nm_monthly;
   end;
   format orig_date snapshot_date month_end date9. apr ltv dti pti percent8.1 delinquency_rate percent8.2;
run;

%local t nm;
cas websf;
libname casuser cas caslib="casuser" sessref=websf;
%do t = 1 %to 3;
   %let nm = %scan(LOANS SNAPSHOT MONTHLY, &t);
   proc cas; table.dropTable / caslib="casuser" name="NMAC_&nm" quiet=true; quit;
   data casuser.NMAC_&nm (promote=yes); set work.nm_%lowcase(&nm); run;
%end;
%mend nmac_build;

/* Checks the generator output has the right shape. Results land in WORK.WEB_* for the caller to read. */
%macro nmac_check;
proc sql;
   create table work.web_c1 as select count(*) as loans, count(distinct customer_id) as customers,
      count(*)/count(distinct customer_id) as loans_per_customer, mean(amount_financed) as avg_amount,
      mean(apr) as avg_apr, sum(loan_status='Active') as active_now, sum(balance_current) as book_balance,
      sum(balance_current)/sum(loan_status='Active') as avg_balance_active
      from work.nm_loans;
   create table work.web_c2 as select snapshot_date format=date9., count(*) as loans, mean(delinq_30) as delinq30_rate,
      mean(default_12m) as default12_rate, mean(balance) as avg_balance from work.nm_snapshot group by snapshot_date;
   create table work.web_c3 as select credit_tier, count(*) as loans, mean(default_12m) as default12_rate
      from work.nm_snapshot as s inner join work.nm_loans as l on s.loan_id = l.loan_id
      where snapshot_date = '30SEP2025'd group by credit_tier;
   create table work.web_c4 as select min(delinquency_rate) as min_rate, max(delinquency_rate) as max_rate,
      mean(delinquency_rate) as mean_rate, min(active_loans) as min_active, max(active_loans) as max_active from work.nm_monthly;
   create table work.web_c5 as select month_end format=yymmd7., active_loans, delinquency_rate, balance_30plus
      from work.nm_monthly where month(month_end) in (1,7) or month_end = '30SEP2026'd;
   create table work.web_c6 as select loans_per, count(*) as customers from
      (select customer_id, count(*) as loans_per from work.nm_loans group by customer_id) group by loans_per;
quit;
%mend nmac_check;

/* Publish the three tables to Snowflake as NEW tables in RND_DB.SEFORD, then let Snowflake count them.
   Creates or replaces only NMAC_AUTO_LOANS, NMAC_AUTO_SNAPSHOT and NMAC_AUTO_MONTHLY. Run %nmac_build first. */
%macro nmac_publish;
%local t nm;
cas websf;
libname casuser cas caslib="casuser" sessref=websf;
ods exclude all;
%do t = 1 %to 3;
   %let nm = %scan(LOANS SNAPSHOT MONTHLY, &t);
   proc cas;
      table.save / table={caslib="casuser", name="NMAC_&nm"}, caslib="SNOWLIB", name="NMAC_AUTO_&nm", replace=true;
   quit;
%end;
proc cas;
   table.dropTable / caslib="casuser" name="NMAC_PUB" quiet=true;
   fedSql.execDirect / query="select * from connection to SNOWLIB (select cast(table_name as varchar(64)) as name, row_count as sf_rows, to_char(created, 'YYYY-MM-DD HH24:MI') as created from information_schema.tables where table_schema='SEFORD' and table_name like 'NMAC_AUTO_%' order by table_name)",
      casout={caslib="casuser", name="NMAC_PUB", replace=true};
quit;
ods exclude none;
data work.web_result; set casuser.NMAC_PUB; run;
%mend nmac_publish;
