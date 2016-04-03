function [learning_table,data_storage] = generateLearningTable(learning_materials,common_words,master_issue_codes,additional_issue_codes)

issue_codes = unique(learning_materials.issue_codes);
description_text = cell(1,length(issue_codes))';
weights = cell(1,length(issue_codes))';

learning_table = table(issue_codes,description_text,weights);

data_storage = struct();
data_storage.common_words = common_words;
data_storage.master_issue_codes = master_issue_codes;
data_storage.additional_issue_codes = additional_issue_codes;
data_storage.unique_text_store = cell(1,length(issue_codes));
data_storage.issue_text_store = cell(1,length(issue_codes));
data_storage.additional_issue_text_store = cell(1,length(issue_codes));
data_storage.weights_store = cell(1,length(issue_codes));
data_storage.issue_text_weight_store = cell(1,length(issue_codes));
data_storage.additional_issue_text_weight_store = cell(1,length(issue_codes));

for i = 1:length(issue_codes)
    
    title_text = learning_materials{learning_materials.issue_codes == issue_codes(i),'title'};
    issue_text = master_issue_codes(issue_codes(i));
    additional_issue_text = additional_issue_codes(issue_codes(i));
    
    issue_text = regexp(issue_text,'\W|\s+','split');
    issue_text = upper(issue_text(~ismember(upper(issue_text),upper(common_words))));
    issue_text = issue_text(~cellfun(@isempty,issue_text));
    issue_text_weight = ones(length(issue_text),1);
    
    additional_issue_text = regexp(additional_issue_text,'\W|\s+','split');
    additional_issue_text = upper(additional_issue_text(~ismember(upper(additional_issue_text),upper(common_words))));
    additional_issue_text = additional_issue_text(~cellfun(@isempty,additional_issue_text));
    additional_issue_text_weight = ones(length(additional_issue_text),1);
    
    merge_text = '';
    for j = 1:length(title_text)
        merge_text = strcat(merge_text,title_text{j});
    end
    merge_text = regexp(merge_text,'\W|\s+','split');
    
    merge_text = upper(merge_text(~ismember(upper(merge_text),upper(common_words))));
    merge_text = merge_text(~ismember(merge_text,issue_text));
    merge_text = merge_text(~ismember(merge_text,additional_issue_text));
    merge_text = merge_text(~cellfun(@isempty,merge_text));
    
    [unique_text,~,c] = unique(merge_text);
    weights = hist(c,length(unique_text))';
    
    weights = weights./max(weights);
    
    data_storage.unique_text_store{i} = unique_text;
    data_storage.issue_text_store{i} = issue_text;
    data_storage.additional_issue_text_store{i} = additional_issue_text;
    data_storage.weights_store{i} = weights;
    data_storage.issue_text_weight_store{i} = issue_text_weight;
    data_storage.additional_issue_text_weight_store{i} = additional_issue_text_weight;
    
    learning_table{learning_table.issue_codes == issue_codes(i),'description_text'} = {[unique_text issue_text additional_issue_text]};
    learning_table{learning_table.issue_codes == issue_codes(i),'weights'} = {[weights;issue_text_weight;additional_issue_text_weight]};
end

end
