function [learning_coded, matches] = classifyBill(bill_title,data_storage)
% CLASSIFYBILL
% Classify the bill based on the bill title

% Get the issue codes
issue_code_count = length(data_storage.master_issue_codes.keys);

% Set up the matches list
matches = zeros(1,issue_code_count);

bill_title = la.cleanupText(bill_title,data_storage.common_words);

% Iterate over the different issue codes
for j = 1:issue_code_count

    % Find matches with the title text
    in_description = util.CStrAinBP(data_storage.unique_text_store{j},bill_title);
    
    % If there are matches, add the weights
    if ~isempty(in_description)
        matches(j) = sum(data_storage.weights_store{j}(in_description));
    end
end

% Take the highest match
[~,learning_coded] = max(matches); % TODO this will just take the highest match, do i need bounds as well?

end