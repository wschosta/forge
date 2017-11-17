function count_rollcalls(state,chamber_size)

competitive_threshold = 0.85; % not the best way to do this, TODO

rollcalls = forge.readAllFilesOfSubject('rollcalls',state);

rollcalls.total_vote    = rollcalls.yea +  rollcalls.nay;
rollcalls.yes_percent   = rollcalls.yea ./ rollcalls.total_vote;
rollcalls.drop          = (rollcalls.total_vote < 0.75*chamber_size) | (rollcalls.total_vote > 1.25*chamber_size) ;
rollcalls.third_reading = ~cellfun(@isempty,regexp(upper(rollcalls.description),'THIRD'));
rollcalls.competitive   = rollcalls.third_reading & ((rollcalls.yes_percent < competitive_threshold) & (rollcalls.yes_percent > (1 - competitive_threshold)));


rollcalls(rollcalls.drop,:) = [];

year = unique(rollcalls.year);
total = hist(rollcalls.year,length(unique(rollcalls.year)))';


rollcalls(~rollcalls.third_reading,:) = [];
third_reading = hist(rollcalls.year,length(unique(rollcalls.year)))';

rollcalls(~rollcalls.competitive,:) = [];
competitive = hist(rollcalls.year,length(unique(rollcalls.year)))';

fprintf('Year       | Total      | Third Reading | Competitive\n')
fprintf('-----------------------------------------------------\n')
for i = 1:length(year)
    fprintf('%9.0i  | %9.0i  | %9.0i     | %9.0i\n',year(i),total(i),third_reading(i),competitive(i))
end

fprintf('----------------------------------------------------\n')
fprintf('Totals     | %9.0i  | %9.0i     | %9.0i\n',sum(total),sum(third_reading),sum(competitive))

bill_count_table = table(year,total,third_reading,competitive);

writetable(bill_count_table,sprintf('data/%s_bill_count.csv',state))

end