function learningAlgorithm()

% read in processed text data
learning_materials = readtable('data\IN\undergrad\description_learning_materials.xlsx');

issue_codes = unique(learning_materials.issue_codes);
description_text = cell(1,length(issue_codes))';
weights = cell(1,length(issue_codes))';

common_words = {'and' 'of' 'a' 'an' 'the' 'is' 'or' 'on' 'by' 'for' 'in' 'to' 'bill' 'resolution' 'with' 'various' 'matters' 'program' 'public'};

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

location = 'h2';

nIter = 150;

robust = 4;
max_grid_size = 3;

for j = 1:robust
    for k = 1:max_grid_size
        for l = 1:max_grid_size
            
            
            x = zeros(nIter,1);
            y = zeros(nIter,1);
            z = zeros(nIter,1);
            
            max_awv = k;
            min_awv = k-1;
            max_iwv = l;
            min_iwv = l-1;
            
            for i = 1:nIter
                threshold = 0;
                f = @(x)processAlgorithm(x,threshold,learning_materials,learning_table,data_storage,common_words);
                x0 = [min_awv+rand*(max_awv-min_awv),min_iwv+rand*(max_iwv-min_iwv)];
                options = optimoptions('fmincon','Algorithm','sqp','TolFun',1e-8);
                [out,fval] = fmincon(f,x0,[],[],[],[],[min_awv min_iwv],[max_awv max_iwv],[],options);
                fprintf('%5i ||| %8.3f%% || i %10.2f | a %10.2f \n',i,-fval,out(1),out(2));
                x(i) = out(1);
                y(i) = out(2);
                z(i) = -fval;
            end
            
%             [max_accuracy, index] = max(fval_storage);
%             input_parameters = x_storage(index,:);
            
%             out = x_storage(:,1);
%             y = x_storage(:,2);
%             z = fval_storage;
%             t = delaunay(x,y);
            
%             figure()
%             hold on; grid on;
%             fill3(x(t)',y(t)',z(t)',z(t)')
%             title('Paraeto surface for learning algorithm weighting')
%             xlabel('Additional Word Weights')
%             ylabel('Issue Word Weights')
%             zlabel('Accuracy (%)')
%             colorbar
%             grid off;
%             saveas(gcf,sprintf('paraeto_surface_%s_%i%i%i',location,j,k,l),'png')
            
            
%             fprintf('Max Accuracy %8.3f%% || i %10.2f | a %10.2f \n',max_accuracy,input_parameters(1),input_parameters(2));
%             var_list = who;
%             var_list = var_list(~ismember(var_list,'obj'));
%             for i = 1:length(var_list)
%                 assignin('base',var_list{i},eval(var_list{i}));
%             end
            
            save(sprintf('learning_algorithm_outputs_%s_%i%i%i',location,j,k,l),'x','y','z')
            
        end
    end
end

master_x = [];
master_y = [];
master_z = [];
    
files = dir('learning_algorithm_outputs*.mat');
for i = 1:length(files)

    output = load(files(i).name);
    
    master_x = [master_x;output.x];
    master_y = [master_y;output.y];
    master_z = [master_z;output.z];
end

master_z = master_z(master_x <= 3);
master_y = master_y(master_x <= 3);

master_x = master_x(master_x <= 3);


t = delaunay(master_x,master_y);

figure()
hold on; grid on;
fill3(master_x(t)',master_y(t)',master_z(t)',master_z(t)')
title('Paraeto surface for learning algorithm weighting')
xlabel('Additional Word Weights')
ylabel('Issue Word Weights')
zlabel('Accuracy (%)')
colorbar
grid off;
saveas(gcf,'paraeto_surface_maximized','png')
saveas(gcf,'paraeto_surface_maximized','fig')

x = master_x;
y = master_y; 
z = master_z; 
save('learning_algorithm_ouputs_combined','x','y','z')
% should also save in the triggers used to get to this point, namely thw
% word lists (as this is the major factor behind the possible thresholds)
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