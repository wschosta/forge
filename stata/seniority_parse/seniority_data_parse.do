capture log close
log using seniority_data_parse, replace text

// program: seniority_data_parse.do
// task: parse out the seniority data for a given state (IN) from the massive 
//		 dataset
// project: forge
// author: Walter Schostak
// 2017-11-16

version 13.1
clear all
set linesize 80
macro drop _all

// load the dataset
use finance_data13.dta

// use this to set the state
local state = "IN"


drop if won == 0
keep if election_state == "`state'" 

keep chamb thirdparty republican democratic election_year candidate cumulative

// drop other chamber (0 is lower chamber, 1 is upper chamber)

drop if chamb == 1
sort election_year

// change to be the state
save "seniority_data_`state'.dta", replace
export delimited seniority_data_`state'.csv, replace
