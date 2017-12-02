/* program: forge_in.do */
/* task: analysis of indiana house consequence */
/* project: FORGE */
/* data set using: total_0 */
/* author: enw, 11.20.17 */

/*     #0 */
/* program setup */
/* be sure to forge_IN.dta data */
version 15.1
set linesize 80
macro drop _all

/*     #1 */
/* create variables */
rename score_variable score_var
rename score_fixed score_fix
rename population_density density
rename terms_served tenure
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
clonevar dataset2 = dataset
replace dataset2 = dataset2 + 20
recode dataset2 (31 = 211)
gen distance_chmbr = abs(np_score - chamber_md)
gen distance_dem = abs(np_score - dem_md)
gen distance_gop = abs(np_score - gop_md)
recode leadership (1/max = 1)(.=.), gen(leaders)
foreach i of numlist 0/2 4/6 8 9 11 {
   gen v3`i' = (v`i' / v2`i')
}

//* labels *//
label variable density "district pop density"
label variable tenure "terms served"
label variable np_score "indvl ideology"
label variable chamber_md "median chamber ideology"
label variable dem_md "dem caucus median ideology"
label variable gop_md "gop caucus median ideology"
label variable leaders "member of chamber leadership"
label variable distance_chmbr "absolute ideological distance from chamber median"
label variable distance_dem "absolute ideological distance from dem median"
label variable distance_gop "absolute ideological distance from gop median"
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
label variable v30 "total per contributor"
label variable v31 "ag per contributor"
label variable v32 "finance per contributor"
label variable v34 "comm per contributor"
label variable v35 "ideo per contributor"
label variable v36 "candidate et al. per contributor"
label variable v38 "construction et al. per contributor"
label variable v39 "defense & law per contributor"
label variable v311 "health & labor per contributor"
label define party_lbl 0 "Dem" 1 "GOP"
label define data_lbl 0 "total" 1 "ag" 2 "finance" 4 "comm" 5 "ideo" 6 "candidate" ///
   8 "construction" 9 "defense/law" 11 "health/labor"
label define data2_lbl 20 "#total" 21 "#ag" 22 "#finance" 24 "#comm" 25 "#ideo" 26 "#candidate" ///
   28 "#construction" 29 "#defense/law" 211 "#health/labor"   
label values party_id party_lbl
label values dataset data_lnl
label values dataset2 data2_lbl
order leaders density tenure distance_chmbr distance_dem distance_gop

/*     #2 */
/* descriptions of variables */
symplot score_var
symplot score_fix
foreach i of numlist 0/2 4/6 8 9 11 {
   symplot v`i'
   graph rename Graph gr`i'
}
foreach j of numlist 20/22 24/26 28 29 211 {
   symplot v`j'
   graph rename Graph gr`j'
}
foreach k of numlist 30/32 34/36 38 39 311 {
   symplot v`k'
   graph rename Graph gr`k' 
}
foreach var of varlist tenure-distance_gop {
   symplot `var'
   graph rename Graph gr`var'
   ladder `var'
}
graph drop _all

/*     #3 */
/* transformation of variables */
gen elo_var = 1/(sqrt(score_var))
gen elo_fix = 1/(sqrt(score_fix))
foreach i of numlist 0/2 4/6 8 9 11 {
   gen v`i'_log = log(v`i')
}
foreach j of numlist 20/22 24/26 28 29 211 {
   gen v`j'_log = log(v`j')
}
foreach k of numlist 30/32 34/36 38 39 311 {
   gen v`k'_log = log(v`k')
}
foreach var of varlist tenure-distance_gop {
   gen `var'lg = log(`var')
}

/*     #4 */
/* exploratory correlations */
//* v0 to v11 are total $, various sectors *//
des v0 - v2 v4 - v6 v8 v9 v11
foreach i of numlist 0/2 4/6 8 9 11 {
   pwcorr elo_var elo_fix  v`i'_log tenurelg-distance_goplg if dataset==`i', sig
}
foreach i of numlist 0/2 4/6 8 9 11 {
   bysort party_id:pwcorr elo_var elo_fix  v`i'_log tenurelg-distance_goplg if dataset==`i', sig
}

//* v2 to v211 are total # contributors, various sectors *//
des v20 - v22 v24 - v26 v28 v29 v211
foreach j of numlist 0/2 4/6 8 9 11 {
   pwcorr elo_var elo_fix  v2`j'_log tenurelg-distance_goplg if dataset==`j', sig
}
foreach j of numlist 0/2 4/6 8 9 11 {
   bysort party_id:pwcorr elo_var elo_fix  v2`j'_log tenurelg-distance_goplg if dataset==`j', sig
}

//* v30 to v311 are $/#constributrs, various sectors *//
des v30 - v32 v34 - v36 v38 v39 v311
foreach k of numlist 0/2 4/6 8 9 11 {
   pwcorr elo_var elo_fix v3`k'_log tenurelg-distance_goplg if dataset==`k', sig
}
foreach k of numlist 30/32 34/36 38 39 311 {
   bysort party_id:pwcorr elo_var elo_fix  v3`k'_log tenurelg-distance_goplg if dataset==`k', sig
}


*     #5 */
/* fifth set of procedures */


