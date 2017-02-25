function [accuracy,iwv,awv] = optimizeFrontierSimple(min_value,max_value,step_size,learning_materials,learning_table,data_storage,concise_flag,title_parsed_flag)
% OPTIMIZEFRONTIERSIMPLE
% Funciton to find the optimal issue word value (iwv) independent from the
% additonal word value (awv)

depth = -5; % as in 10^depth, serves as the stopping condition: any(floor(log10(step_size)) ~= depth)
step_size_multiplier = 0.5; % each "zoom in" the step size decreases by this number

title_array      = min_value(1):step_size(1):max_value(1);
additional_array = min_value(2):step_size(2):max_value(2);

[master_title_array,master_additional_array,master_accuracy_list,~,~] = la.checkExistingFiles('+la/temp/learning_algorithm_simple_outputs_*_*.mat',0);

count = 0;
while any(floor(log10(step_size)) ~= depth)
    
    if count > 0
        [~,title_index] = max(max(accuracy_list,[],2));
        [~,additional_index] = max(max(accuracy_list,[],1));
        
        title_min = util.greaterThanZero(title_array(title_index) - step_size(1));
        title_max = util.greaterThanZero(title_array(title_index) + step_size(1));
        
        additional_min = util.greaterThanZero(additional_array(additional_index) - step_size(2));
        additional_max = util.greaterThanZero(additional_array(additional_index) + step_size(2));
        
        title_array      = title_min:step_size(1):title_max;
        additional_array = additional_min:step_size(2):additional_max;
        step_size        = step_size*step_size_multiplier;
        
        if isempty(title_array) || isempty(additional_array)
            error('BOUNDS ERRROR ON TITLE ARRAY OR ADDITIONAL ARRAY!')
        end
    end
    
    accuracy_list = nan(length(title_array),length(additional_array));
    
    inside_hit = 0;
    
    iter = 1;
    for i = 1:length(title_array)
        for j = 1:length(additional_array)
            
            fprintf('%0.4f %0.4f ',title_array(i),additional_array(j));
            
            if any(ismember(find(title_array(i) == master_title_array),find(additional_array(j) == master_additional_array)))
                
                title_list      = find(title_array(i) == master_title_array);
                additional_list = find(additional_array(j) == master_additional_array);
                
                index = title_list(ismember(title_list,additional_list));
                
                if master_accuracy_list(index) > 0
                    accuracy_list(i,j) = master_accuracy_list(index(1));
                    
                    fprintf('Skip! %0.04f%% \n', accuracy_list(i,j))
                    continue
                else
                    master_title_array(index)      = [];
                    master_additional_array(index) = [];
                    master_accuracy_list(index)    = [];
                end
            end
            tic;
            
            inside_hit = 1;
            
            % Place the awv and iwv values in the data storage structure
            data_storage.iwv = title_array(i);
            data_storage.awv = additional_array(j);
            
            issue_codes      = unique(learning_table.issue_codes);
            description_text = cell(length(issue_codes),1);
            weights          = cell(length(issue_codes),1);
            sum_weights      = zeros(length(issue_codes),1);
            for k = 1:length(issue_codes)
                % Find all of the description text and all of the associated weights
                description_text{k} = [data_storage.unique_text_store{k} data_storage.issue_text_store{k} data_storage.additional_issue_text_store{k}];
                weights{k}          = [data_storage.weights_store{k}; data_storage.issue_text_weight_store{k}*data_storage.iwv ; data_storage.additional_issue_text_weight_store{k}*data_storage.awv];
                sum_weights(k)      = sum(weights{k});
            end
            
            data_storage.description_text = description_text;
            data_storage.weights          = weights;
            
            accuracy_list(i,j) = la.processAlgorithm(learning_materials,data_storage,1,concise_flag,title_parsed_flag);
            
            fprintf('%0.4f%% ',accuracy_list(i,j))
            
            toc;
            iter = iter + 1;
            if mod(iter,100) == 0 && inside_hit
                save(sprintf('+la/temp/learning_algorithm_simple_outputs_%i_%s.mat',count,date),'accuracy_list','title_array','additional_array','step_size')
            end
        end
    end
    
    if inside_hit
        save(sprintf('+la/temp/learning_algorithm_simple_outputs_%i_%s.mat',count,date),'accuracy_list','title_array','additional_array','step_size');
    end
    
    count = count + 1;
end

% Search for output files
[master_title_array,master_additional_array,master_accuracy_list,hit_list,files] = la.checkExistingFiles('+la/temp/learning_algorithm_simple_outputs_*_*.mat',1);

t = delaunay(master_title_array,master_additional_array);

% Generate the figure
figure()
hold on; grid on;
fill3(master_title_array(t)',master_additional_array(t)',master_accuracy_list(t)',master_accuracy_list(t)')
title('Paraeto surface for learning algorithm weighting')
xlabel('Additional Word Weights')
ylabel('Issue Word Weights')
zlabel('Accuracy (%)')
axis tight
colorbar
grid off; hold off;
saveas(gcf,sprintf('+la/temp/optimized_surface_%s',date),'png')

% Save the data into a master .mat file
title_array      = master_title_array;
additional_array = master_additional_array;
accuracy_list    = master_accuracy_list;

% Find the maximum accuracy
[accuracy,index] = max(accuracy_list);

% Place the awv and iwv values in the data stoage structure
data_storage.iwv = title_array(index);
data_storage.awv = additional_array(index);

iwv = data_storage.iwv;
awv = data_storage.awv;

issue_code_count = length(data_storage.master_issue_codes.keys);
description_text = cell(issue_code_count,1);
weights          = cell(issue_code_count,1);

for k = 1:issue_code_count
    % Find all of the description text and all of the associated weights
    description_text{k} = [data_storage.unique_text_store{k} data_storage.issue_text_store{k} data_storage.additional_issue_text_store{k}];
    weights{k}          = [data_storage.weights_store{k};data_storage.issue_text_weight_store{k}*data_storage.iwv;data_storage.additional_issue_text_weight_store{k}*data_storage.awv];
end

data_storage.description_text = description_text;
data_storage.weights          = weights;
data_storage.issue_code_count = issue_code_count;

save(sprintf('+la/temp/learning_algorithm_simple_output_results_%s',date),'accuracy','iwv','awv','title_array','additional_array','accuracy_list','learning_materials','data_storage');
save('+la/learning_algorithm_results','accuracy','iwv','awv','title_array','additional_array','accuracy_list','learning_materials');

flag = 1; %#ok<NASGU>
save(sprintf('+la/temp/learning_algorithm_simple_outputs_00000000000_%s.mat',date),'accuracy_list','title_array','additional_array','flag');

for i = 1:length(hit_list)
    if hit_list(i) == 1
        delete([files(i).folder '/' files(i).name]);
    end
end

end