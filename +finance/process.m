function compiled_list = process(state)

state_data = readtable(sprintf('finance_data/%s_reduced.xlsx',state));

compiled_list = [];

names = unique(state_data.name);

for i = 1:length(names)
    matches = util.CStrAinBP(state_data.name,names(i));
    
    basis_row = state_data(matches(1),:);
    basis_row{:,6:end} = sum(state_data{matches,6:end},1);
    basis_row.year_count = length(matches);
    
    compiled_list = [compiled_list ; basis_row];
end

writetable(compiled_list,sprintf('finance_data/%s_merged_data.csv',state))
end