function [learning_table,data_storage] = generateLearningTable(learning_materials,common_words,master_issue_codes,additional_issue_codes)
% GENERATELEARNINGTABLE
% Function to "teach" the learning algorithm based on a manually coded set
% of bill titles.
%
% Developed by Walter Schostak and Eric Waltenburg
%
% See also la.main

% Initialuze appropraite arrays
issue_codes       = unique(learning_materials.issue_codes);
description_text  = cell(length(issue_codes),1);
weights           = cell(length(issue_codes),1);
issue_text        = cell(length(issue_codes),1);
issue_text_weight = cell(length(issue_codes),1);
additional_issue_text         = cell(length(issue_codes),1);
additional_issue_text_weight = cell(length(issue_codes),1);
% Create the table
learning_table = table(issue_codes,description_text,weights,issue_text,issue_text_weight,additional_issue_text,additional_issue_text_weight);

% Initialize the data storage structure
data_storage = struct();
data_storage.common_words                       = common_words;
data_storage.master_issue_codes                 = master_issue_codes;
data_storage.additional_issue_codes             = additional_issue_codes;
data_storage.unique_text_store                  = cell(1,length(issue_codes));
data_storage.issue_text_store                   = cell(1,length(issue_codes));
data_storage.additional_issue_text_store        = cell(1,length(issue_codes));
data_storage.weights_store                      = cell(1,length(issue_codes));
data_storage.issue_text_weight_store            = cell(1,length(issue_codes));
data_storage.additional_issue_text_weight_store = cell(1,length(issue_codes));

% Iterate over the issue codes
for i = 1:length(issue_codes)
    
    % Look for title matches for a given issue code
    title_text = learning_materials{learning_materials.issue_codes == issue_codes(i),'title'};
    
    % Find matching issue text
    issue_text = master_issue_codes(issue_codes(i));
    additional_issue_text = additional_issue_codes(issue_codes(i));
    
    % Cleanup the issue text
    [issue_text,issue_text_weight] = la.cleanupText(issue_text,common_words);
    
    % Cleanup the additional issue text
    [additional_issue_text,additional_issue_text_weight] = la.cleanupText(additional_issue_text,common_words);
    
    % Merge all of the title text words
    merge_text = strjoin(title_text);
    
    % Cleanup the merged text
    [merge_text,~] = la.cleanupText(merge_text,[common_words issue_text additional_issue_text]);
    
    % Find all of the unique words and the count for each
    [unique_text,~,c] = unique(merge_text);
    
    % Generate weights according to that count
    weights           = hist(c,length(unique_text));
    
    [weights,index] = sort(weights,2,'descend');
    unique_text = unique_text(index);
    
    % Normalize the weights
    weights = (weights./max(weights))';
    
    % Enter all of the information into the data storage array
    
    data_storage.unique_text_full_store{i}                  = unique_text;
    data_storage.weights_full_store{i}                      = weights;
    
    unique_text(201:end) = [];
    weights(201:end) = [];
    
    data_storage.unique_text_store{i}                  = unique_text;
    data_storage.issue_text_store{i}                   = issue_text;
    data_storage.additional_issue_text_store{i}        = additional_issue_text;
    data_storage.weights_store{i}                      = weights;
    data_storage.issue_text_weight_store{i}            = issue_text_weight;
    data_storage.additional_issue_text_weight_store{i} = additional_issue_text_weight;
    
% end
% 
% [text,~,count] = unique([data_storage.unique_text_store{:}]);
% hit_list = hist(count,length(text));
% kill_text = text(hit_list > 1);
% 
% for i = 1:length(data_storage.unique_text_store)
%     index = util.CStrAinBP(data_storage.unique_text_store{i},kill_text);
%     
%     data_storage.unique_text_store{i}(index) = [];
%     data_storage.weights_store{i}(index) = [];
%     

    % Store the information in the learning table
    learning_table{learning_table.issue_codes == issue_codes(i),'description_text'} = {data_storage.unique_text_store{i}}; 
    learning_table{learning_table.issue_codes == issue_codes(i),'weights'} = {data_storage.weights_store{i}}; 
    
    learning_table{learning_table.issue_codes == issue_codes(i),'issue_text'} = {data_storage.issue_text_store{i}};
    learning_table{learning_table.issue_codes == issue_codes(i),'issue_text_weight'} = {data_storage.issue_text_weight_store{i}};
    
    learning_table{learning_table.issue_codes == issue_codes(i),'additional_issue_text'} = {data_storage.additional_issue_text_weight_store{i}};
    learning_table{learning_table.issue_codes == issue_codes(i),'additional_issue_text_weight'} = {data_storage.additional_issue_text_store{i}};
end

figure()
hold on
grid on
hist(learning_materials.issue_codes,32);
xlabel('Issue Codes')
ylabel('Frequency')
title('Learning Material Issue Code Frequency')
axis tight
hold off
saveas(gcf,sprintf('learning_algorithm_issue_frequency_%s',date),'png')

end