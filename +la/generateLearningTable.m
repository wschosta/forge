function [learning_table,data_storage] = generateLearningTable(iwv,awv,learning_materials,common_words,master_issue_codes,additional_issue_codes,concise_flag,title_parsed_flag)
% GENERATELEARNINGTABLE
% Function to "teach" the learning algorithm based on a manually coded set
% of bill titles.
%
% Developed by Walter Schostak and Eric Waltenburg
%
% See also la.main

cut_off = 3001; % The higher this value, the slower everything runs
% But seemingly the higher the accuracy

% Initialuze appropriate arrays
if concise_flag
    unique_issue_codes = unique(learning_materials.concise_codes);
    issue_code_array   = learning_materials.concise_codes;
else
    unique_issue_codes = unique(learning_materials.issue_codes);
    issue_code_array   = learning_materials.issue_codes;
end
description_text             = cell(length(unique_issue_codes),1);
weights                      = cell(length(unique_issue_codes),1);
issue_text                   = cell(length(unique_issue_codes),1);
issue_text_weight            = cell(length(unique_issue_codes),1);
additional_issue_text        = cell(length(unique_issue_codes),1);
additional_issue_text_weight = cell(length(unique_issue_codes),1);

% Create the table
issue_codes    = unique_issue_codes;
learning_table = table(issue_codes,description_text,weights,issue_text,issue_text_weight,additional_issue_text,additional_issue_text_weight);

% Initialize the data storage structure
data_storage = struct();
data_storage.cut_off                            = cut_off;
data_storage.common_words                       = common_words;
data_storage.master_issue_codes                 = master_issue_codes;
data_storage.additional_issue_codes             = additional_issue_codes;
data_storage.unique_text_store                  = cell(1,length(unique_issue_codes));
data_storage.unique_text_full_store             = cell(1,length(unique_issue_codes));
data_storage.issue_text_store                   = cell(1,length(unique_issue_codes));
data_storage.additional_issue_text_store        = cell(1,length(unique_issue_codes));
data_storage.weights_store                      = cell(1,length(unique_issue_codes));
data_storage.weights_full_store                 = cell(1,length(unique_issue_codes));
data_storage.issue_text_weight_store            = cell(1,length(unique_issue_codes));
data_storage.additional_issue_text_weight_store = cell(1,length(unique_issue_codes));
data_storage.issue_code_count                   = length(unique_issue_codes);

 delete_str = '';

% Iterate over the issue codes
for i = 1:length(unique_issue_codes)
    
    print_str = sprintf('%i %s',i,master_issue_codes(i));
    fprintf([delete_str,print_str]);
    delete_str = repmat(sprintf('\b'),1,length(print_str));
    
    bill_count = sum(issue_code_array == unique_issue_codes(i));
    
    % Look for title matches for a given issue code
    merge_text = learning_materials{issue_code_array == unique_issue_codes(i),title_parsed_flag};
    merge_text = [merge_text{:}];

    % Find and cleanup the issue text
    issue_text                     = master_issue_codes(unique_issue_codes(i));
    [issue_text,issue_text_weight] = la.cleanupText(issue_text,common_words);
    
    % Find and cleanup the additional issue text
    additional_issue_text                                = additional_issue_codes(unique_issue_codes(i));
    [additional_issue_text,additional_issue_text_weight] = la.cleanupText(additional_issue_text,common_words);
    
    % Find all of the unique words and the column index for each
    

    % Seems to lower accuracy
    %          [merge_text,~] = la.cleanupText(merge_text,[issue_text,additional_issue_text]);
    [unique_text,~,c] = unique(merge_text);
    
    % Using the column index and length, generate the count
    count         = hist(c,length(unique_text));
    [count,index] = sort(count,2,'descend');
    unique_text   = unique_text(index);
    
    % Normalize the weights
    weights = (count./bill_count)';
    
    % Enter all of the information into the data storage array
    data_storage.unique_text_full_store{i} = unique_text;
    data_storage.weights_full_store{i}     = weights;
    
    unique_text(cut_off:end) = [];
    weights(cut_off:end)     = [];
    
    % TODO Currently it does the weighting based on the frequency with
    % which a word shows up in a bill (the number of times it is counted /
    % number of bills). Should I be weighting it again based on relative
    % appareance in different issue categories? i.e. everything gets
    % normalized across bills?
    
    data_storage.unique_text_store{i}                  = unique_text;
    data_storage.issue_text_store{i}                   = issue_text;
    data_storage.additional_issue_text_store{i}        = [additional_issue_text unique_text(1:5)];
    data_storage.weights_store{i}                      = weights;
    data_storage.issue_text_weight_store{i}            = issue_text_weight;
    data_storage.additional_issue_text_weight_store{i} = [additional_issue_text_weight ; weights(1:5)];
    
    % Store the information in the learning table
    learning_table{learning_table.issue_codes == unique_issue_codes(i),'description_text'} = {data_storage.unique_text_store{i}}; 
    learning_table{learning_table.issue_codes == unique_issue_codes(i),'weights'}          = {data_storage.weights_store{i}}; 
    
    learning_table{learning_table.issue_codes == unique_issue_codes(i),'issue_text'}        = {data_storage.issue_text_store{i}};
    learning_table{learning_table.issue_codes == unique_issue_codes(i),'issue_text_weight'} = {data_storage.issue_text_weight_store{i}};
    
    learning_table{learning_table.issue_codes == unique_issue_codes(i),'additional_issue_text'}        = {data_storage.additional_issue_text_store{i}};
    learning_table{learning_table.issue_codes == unique_issue_codes(i),'additional_issue_text_weight'} = {data_storage.additional_issue_text_weight_store{i}};
    
    data_storage.iwv = iwv;
    data_storage.awv = awv;
    
    description_text = cell(length(unique_issue_codes),1);
    weights          = cell(length(unique_issue_codes),1);
    sum_weights      = zeros(length(unique_issue_codes),1);
    for k = 1:length(unique_issue_codes)
        % Find all of the description text and all of the associated weights
        description_text{k} = [data_storage.unique_text_store{k} data_storage.issue_text_store{k} data_storage.additional_issue_text_store{k}];
        weights{k}          = [data_storage.weights_store{k}; data_storage.issue_text_weight_store{k}*data_storage.iwv ; data_storage.additional_issue_text_weight_store{k}*data_storage.awv];
        sum_weights(k)      = sum(weights{k});
    end
    
    data_storage.description_text = description_text;
    data_storage.weights          = weights;
    
end
print_str = sprintf('Finished Learning Table Generation!\n');
fprintf([delete_str,print_str]);

figure()
hold on
grid on
histogram(issue_code_array,data_storage.issue_code_count);
xlabel('Issue Codes')
ylabel('Frequency')
title('Learning Material Issue Code Frequency')
axis tight
hold off
saveas(gcf,sprintf('+la/learning_algorithm_issue_frequency_%s',date),'png')
close(gcf);

end