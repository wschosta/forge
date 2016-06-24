function [learning_coded, matches] = classifyBill(bill_title,data_storage)
% CLASSIFYBILL
% Classify the bill based on the bill title

% Cleanup the bill title and eliminate common words
[bill_title,~] = la.cleanupText(bill_title,data_storage.common_words);

% Get the issue codes
issue_codes = cell2mat(data_storage.master_issue_codes.keys);

% Set up the matches list
matches = zeros(1,length(issue_codes));

% Iterate over the different issue codes
for j = 1:length(issue_codes)
    % Pull toether all the relevant words
    description_text = [data_storage.unique_text_store{j} data_storage.issue_text_store{j} data_storage.additional_issue_text_store{j}];
    
    % Pull together the matching weights
    weights = [data_storage.weights_store{j};data_storage.issue_text_weight_store{j}*data_storage.iwv;data_storage.additional_issue_text_weight_store{j}*data_storage.awv];
    
    % Check for words in the description text and bill title
    in_description = ismember(description_text,bill_title);
    
    if any(in_description) % if there are mayches
        % Pull together the weights
        matches(j) = matches(j) + sum(weights(in_description > 0));
    end
end

% Take the highest match
[~,learning_coded] = max(matches); % TODO this will just take the highest match, do i need bounds as well?

end