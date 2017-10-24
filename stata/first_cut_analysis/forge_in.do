/* program: forge_in.do */
/* task: analysis of indiana house consequence */
/* project: FORGE */
/* data set using: H_elo_score_1 */
/* author: enw, 10/18/17 */

/*     #0 */
/* program setup */
/* be sure to load data set */
version 15.0
set linesize 80
macro drop _all

/*     #1 */
/* prepare dataset for analysis */
rename score_variable score_var
rename score_fixed score_fix
clonevar v0 = total
clonevar v1 = ag
clonevar v2 = finance
clonevar v4 = comm
clonevar v5 = ideology
egen v6 = rsum(candidate government partyfund non public)
egen v8 = rsum(construct energy transportation)
egen v9 = rsum(defense law)
egen v11 = rsum(health labor)
clonevar v20 = total_count
clonevar v21 = ag_count
clonevar v22 = finance_count
clonevar v24 = comm_count
clonevar v25 = ideology_count
egen v26 = rsum(candidate_count government_count partyfund_count non_count public_count)
egen v28 = rsum(construct_count energy_count transportation_count)
egen v29 = rsum(defense_count law_count)
egen v211 = rsum(health_count labor_count)
label variable v0 "total"
label variable v1 "ag"
label variable v2 "finance"
label variable v4 "comm"
label variable v5 "ideo"
label variable v6 "candidate et al."
label variable v8 "construction et al."
label variable v9 "defense & law"
label variable v11 "health & labor"
label variable v20 "total count"
label variable v21 "ag count"
label variable v22 "finance count"
label variable v24 "comm count"
label variable v25 "ideo count"
label variable v26 "candidate et al. count"
label variable v28 "construction et al. count"
label variable v29 "defense & law count"
label variable v211 "health & labor count"
recode dataset (0=20)(1=21)(2=22)(4=24)(5=25)(6=26)(8=28)(9=29)(11=211)(.=.), gen(data_count)
label define party_lbl 0 "Dem" 1 "GOP"
label define data_lbl 0 "total" 1 "ag" 2 "finance" 4 "comm" 5 "ideo" 6 "candidate" ///
   8 "construction" 9 "defense/law" 11 "health/labor"
label define data2_lbl 20 "#total" 21 "#ag" 22 "#finance" 24 "#comm" 25 "#ideo" 26 "#candidate" ///
   28 "#construction" 29 "#defense/law" 211 "#health/labor"   
label values party_id party_lbl
label values dataset data_lbl
label values data_count data2_lbl

/*     #2 */
/* exploratory correlations */
/* V0 TO V11 ARE TOTAL CONTRIBUTIONS */
des v0 - v11
foreach i of numlist 0/2 4/6 8 9 11 {
   pwcorr score_var score_fix  v`i' if dataset==`i', sig
}
foreach i of numlist 0/2 4/6 8 9 11 {
   bysort party_id:pwcorr score_var score_fix  v`i' if dataset==`i', sig
}
/* V2 TO V211 ARE TOTAL NUMBER OF CONTRIBUTORS */
des v20 - v211
foreach j of numlist 20 21 22 24 25 26 28 29 211 {
   pwcorr score_var score_fix  v`j' if data_count==`j', sig
}
foreach j of numlist 20 21 22 24 25 26 28 29 211 {
   bysort party_id:pwcorr score_var score_fix  v`j' if data_count==`j', sig
}






*     #3 */
/* third set of procedures */

/*     #4 */
/* fourth set of procedures */
