function [concise_issue_codes,concise_codes] = generateConciseMaps(master_issue_codes,concise_recode)

concise_issue_codes      = containers.Map('KeyType','int32','ValueType','char');

concise_keys   = zeros(1,length(master_issue_codes.keys));
concise_values = zeros(1,length(additional_issue_codes.keys));

for i = 1:length(concise_recode)
    
    temp_issue      = cell(length(concise_recode{i}),1);
    
    for j = 1:length(concise_recode{i})
        temp_issue{j}      = master_issue_codes(concise_recode{i}(j));
        
        concise_keys(concise_recode{i}(j))   = concise_recode{i}(j);
        concise_values(concise_recode{i}(j)) = i;
    end
    
    concise_issue_codes(i)      = strjoin(temp_issue);
end

generate_concise_codes = containers.Map(concise_keys,concise_values);
concise_codes = arrayfun(@(x) generate_concise_codes(x),issue_codes);

end