/* program: vscanalysis.do */
/* task: illustrate indiana house behavior from Forge data */
/* project: vsc intern class talk */
/* data sets using: votematrix.dta, people.dta */
/* author: enw, February 23, 2017 */

/*     #0 */
/* program setup */
/* be sure to load data set */
version 14.2
set linesize 80
macro drop _all

/*     #1 */
/* boxplots & ttests of r. bacon [distric= 75, id=10568] */
graph box agree if district~=75, by(party)
robvar agree if district~=75, by(party)
ttest agree if district~=75, by(party) unequal
graph box agree if district~=75, by(rural_district)
robvar agree if district~=75, by(rural_district)
ttest agree if district~=75, by(rural_district) unequal
graph box agree if district~=75, by(commit)
robvar agree if district~=75, by(commit)
ttest agree if district~=75, by(commit) unequal
graph box agree if district~=75, by(seatprox)
robvar agree if district~=75, by(seatprox)
ttest agree if district~=75, by(seatprox)
graph box agree if district~=75, by(hi_income)
robvar agree if district~=75, by(hi_income)
ttest agree if district~=75, by(hi_income) unequal
graph box agree if district~=75, by(whitepct)
robvar agree if district~=75, by(whitepct)
ttest agree if district~=75, by(whitepct) unequal
graph box agree if district~=75, by(hiedpct)
robvar agree if district~=75, by(hiedpct)
ttest agree if district~=75, by(hiedpct)

/*     #2 */
/* model influence; use people.dta */
reg influence keycmt party leadership tot_contribs
margins, at(tot_contribs=(11.96 12.59 13.12)) vsquish
marginsplot
twoway (lfit influence tot_contribs) ///
   (scatter influence tot_contribs, mlabel(id2) mlabsize(medlarge) mlabcolor(red))

