function [learning_coded, matches] = classifyBill(bill_title,data_storage)

    bill_title = regexp(bill_title,'\W|\s+','split');
    bill_title = bill_title{:};
    bill_title = bill_title(~cellfun(@isempty,bill_title));
    bill_title = upper(bill_title(~ismember(upper(bill_title),upper(data_storage.common_words))));
    
    issue_codes = cell2mat(data_storage.master_issue_codes.keys);
    matches = zeros(1,length(issue_codes));
    for j = 1:length(issue_codes)
        
        description_text = [data_storage.unique_text_store{j} data_storage.issue_text_store{j} data_storage.additional_issue_text_store{j}];
        weights = [data_storage.weights_store{j};data_storage.issue_text_weight_store{j}*data_storage.iwv;data_storage.additional_issue_text_weight_store{j}*data_storage.awv];
        
        in_description = ismember(description_text,bill_title);
        
        if any(in_description)
            matches(j) = matches(j) + sum(weights(in_description > 0));
        end
    end
    
    [~,learning_coded] = max(matches); % this will just take the highest match, do i need bounds as well?
end