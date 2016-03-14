function learningAlgorithm()


% read in processed text data
learning_materials = readtable('data\IN\undergrad\description_learning_materials.xlsx');

issue_codes = unique(learning_materials.issue_codes);
description_text = cell(1,length(issue_codes))';
weights = cell(1,length(issue_codes))';

common_words = {'and' 'of' 'a' 'an' 'the' 'is' 'or' 'on' 'by' 'for' 'in' 'to' 'bill' 'resolution' 'with' 'various' 'maatters' 'program'};

master_issue_codes = containers.Map([1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16],...
    {'Agriculture','Commerce, Business, Economic Development',...
    'Courts & Judicial','Education','Elections & Apportionment',...
    'Employment & Labor','Environment & Natural Resources',...
    'Family, Children, Human Affairs & Public Health',...
    'Banks & Financial Institutions','Insurance',...
    'Government & Regulatory Reform','Local Government',...
    'Roads & Transportation','Utilities, Energy & Telecommunications',...
    'Ways & Means, Appropriations','Other'});

additional_issue_codes = containers.Map([1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16],...
    {'','firearm',...
    '','Schools student','Advocacy',...
    'Unemployment wage','',...
    'Child immigration',...
    '','',...
    'Access','Records',...
    '','',...
    'Taxation Taxes Tax',''});

learning_table = table(issue_codes,description_text,weights);

% results_table = table;
% 
% iwv = 1.4:0.02:1.8;
% awv = 0.6:0.02:1;
% threshold = 0.15:0.05:0.75;

% steps = 2;
% iwv = linspace(0.75,2,steps);
% awv = linspace(0.5,1,steps);
% threshold = linspace(0,0.9,steps);

data_storage = struct();
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

nIter = 500;
x_storage = zeros(nIter,2);
fval_storage = zeros(1,nIter);

for i = 1:nIter  
    threshold = 0;
    f = @(x)processAlgorithm(x,threshold,learning_materials,learning_table,data_storage,common_words);
    x0 = [rand*3.5,rand*2.5];
    A = [-1 1];
    b = 0;
    options = optimoptions('fmincon','Algorithm','sqp','TolFun',1e-8);
    [x,fval] = fmincon(f,x0,A,b,[],[],[0.3 0.2],[3.5 2.5],[],options);
    fprintf('%5i ||| %8.3f%% || i %10.2f | a %10.2f \n',i,-1*fval,x(1),x(2));
    x_storage(i,:) = x;
    fval_storage(i) = -1*fval; 
end

[max_accuracy, index] = max(fval_storage);
input_parameters = x_storage(index,:);

fprintf('Max Accuracy %8.3f%% || i %10.2f | a %10.2f \n',max_accuracy,input_parameters(1),input_parameters(2));
var_list = who;
var_list = var_list(~ismember(var_list,'obj'));
for i = 1:length(var_list)
    assignin('base',var_list{i},eval(var_list{i}));
end

end

function accuracy = processAlgorithm(x,threshold,learning_materials,learning_table,data_storage,common_words)
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
    bill_title = upper(bill_title(~ismember(upper(bill_title),upper(common_words))));
    
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

results_table = table(accuracy,correct,total,iwv,awv,threshold,count_17);

accuracy = -1*accuracy;

end