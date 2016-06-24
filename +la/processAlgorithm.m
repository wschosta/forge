function output = processAlgorithm(x,learning_materials,learning_table,data_storage,output_flag)
% PROCESSALGORITHM
% Process the total bill set based on a given learned set

% Read in the awv and iwv values
awv = x(1);
iwv = x(2);

% Read in the bill list
learning_coded = zeros(length(learning_materials.issue_codes),1);
issue          = cell(1,length(learning_materials.issue_codes))';

% Place the awv and iwv values in the data stoage structure
data_storage.awv = awv;
data_storage.iwv = iwv;

for i = 1:length(learning_materials.issue_codes)
    
    bill_title = learning_materials{i,'title'};
    
    [learning_coded(i), issue{i}] = la.classifyBill(bill_title,data_storage);
    
    % Cleanup the bill title and eliminate common words
    [bill_title,~] = la.cleanupText(bill_title,data_storage.common_words);
    
    % Find the issue codes and create matched values array
    issue_codes = unique(learning_table.issue_codes);
    matches     = zeros(1,length(issue_codes));
    
    % Iterate over issue codes
    for j = 1:length(issue_codes)
        
        % Find all of the description text and all of the associated
        % weights
        description_text = [data_storage.unique_text_store{j} data_storage.issue_text_store{j} data_storage.additional_issue_text_store{j}];
        weights          = [data_storage.weights_store{j};data_storage.issue_text_weight_store{j}*iwv;data_storage.additional_issue_text_weight_store{j}*awv];
        
        % Find matches with the title text
        in_description = ismember(description_text,bill_title);
        
        % If there are matches, add the weights
        if any(in_description)
            matches(j) = matches(j) + sum(weights(in_description > 0));
        end
    end
    
    % Find the index of the highest match
    [~,learning_coded(i)] = max(matches); % this will just take the highest match, do i need bounds as well?
    
    % Store the issue weights
    issue{i} = matches;
end

% create the learned table
learned_table = table(learning_coded,issue);

% create the processed table
processed = [learning_materials,learned_table];

% Find how many bills were correctly matched
processed.matched = (processed.issue_codes == processed.learning_coded);

% Generate basic stats
correct  = sum(processed.matched);
total    = length(processed.matched);
accuracy = correct/total*100;

% Find how many bills were not codeable
count_17 = sum(learning_coded == 17);

if output_flag
    output = -1*accuracy; % annoying feature of this program but so it goes
else
    % Generate the output structure
    output = struct();
    output.processed = processed;
    output.correct = correct;
    output.total = total;
    output.accuracy = accuracy;
    output.count_17 = count_17;
end

end