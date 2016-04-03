function output = processAlgorithm(x,threshold,learning_materials,learning_table,data_storage,output_flag)
awv = x(1);
iwv = x(2);

% read in bill list
learning_coded = zeros(length(learning_materials.issue_codes),1);
issue = cell(1,length(learning_materials.issue_codes))';
for i = 1:length(learning_materials.issue_codes)
    
    bill_title = learning_materials{i,'title'};
    
    bill_title = regexp(bill_title,'\W|\s+','split');
    bill_title = bill_title{:};
    bill_title = bill_title(~cellfun(@isempty,bill_title));
    bill_title = upper(bill_title(~ismember(upper(bill_title),upper(data_storage.common_words))));
    
    issue_codes = unique(learning_table.issue_codes);
    matches = zeros(1,length(issue_codes));
    for j = 1:length(issue_codes)
        
        description_text = [data_storage.unique_text_store{j} data_storage.issue_text_store{j} data_storage.additional_issue_text_store{j}];
        weights = [data_storage.weights_store{j};data_storage.issue_text_weight_store{j}*iwv;data_storage.additional_issue_text_weight_store{j}*awv];
        
        in_description = ismember(description_text,bill_title);
        
        if any(in_description)
            matches(j) = matches(j) + sum(weights(in_description > 0));
        end
    end
    
    if max(matches) > sum(matches)*threshold
        [~,learning_coded(i)] = max(matches); % this will just take the highest match, do i need bounds as well?
    else
        learning_coded(i) = 17;
    end
    issue{i} = matches;
end

learned_table = table(learning_coded,issue);

processed = [learning_materials,learned_table];
processed.matched = (processed.issue_codes == processed.learning_coded);

correct = sum(processed.matched);
total = length(processed.matched);
accuracy = correct/total*100;

count_17 = sum(learning_coded == 17);

if output_flag
    output = -1*accuracy;
else
    output = struct();
    output.processed = processed;
    output.correct = correct;
    output.total = total;
    output.accuracy = accuracy;
    output.count_17 = count_17;
end

end