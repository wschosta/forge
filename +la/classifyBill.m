function [learning_coded, matches] = classifyBill(bill_title,data_storage)
% CLASSIFYBILL
% Classify the bill based on the bill title

% Get the issue codes
issue_code_count = length(data_storage.master_issue_codes.keys);

% Set up the matches list
matches = zeros(1,issue_code_count);

[clean_title,weights] = la.cleanupText(bill_title,data_storage.common_words);

if isempty(text) || all(weights == 0)
    learning_coded = NaN;
    return
end

% Iterate over the different issue codes
for j = 1:issue_code_count

    % Find matches with the title text
    [in_description,index] = util.CStrAinBP(data_storage.description_text{j},clean_title);
    
    % If there are matches, add the weights
    if ~isempty(in_description)
        sum_value = sum(data_storage.weights{j}(in_description).*weights(index));
        
        if length(sum_value) > 1
            sum_value = sum(data_storage.weights{j}(in_description).*weights(index)');
        end
        matches(j) = sum_value;
    end
end

% Take the highest match
if all(matches == 0)
    learning_coded = NaN;
else
    [~,learning_coded] = max(matches); % TODO this will just take the highest match, do i need bounds as well?
end

end