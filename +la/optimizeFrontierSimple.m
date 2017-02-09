function [accuracy,max_title,max_additional] = optimizeFrontierSimple(min_value,max_value,step_size,learning_materials,learning_table,data_storage)
% OPTIMIZEFRONTIERSIMPLW
% Funciton to find the optimal issue word value (iwv) independent from the
% additonal word value (awv)

keyboard

title_array = min_value(1):step_size(1):max_value(1);
additional_array = min_value(2):step_size(2):max_value(2);

if isempty(additional_array)
    additional_array = 1;
end

count = 0;
while any(floor(log10(step_size)) ~= -5)
    
    if count > 0

        [~,title_index] = max(max(-accuracy_list,[],1));
        [~,additional_index] = max(max(-accuracy_list,[],2));
        
        title_array = (title_array(title_index) - step_size(1)):step_size(1):(title_array(title_index) + step_size(1));
        additional_array = (additional_array(additional_index) - step_size(2)):step_size(2):(additional_array(additional_index) + step_size(2));
        step_size = step_size*0.75;
        
        if isempty(title_array)
            title_array = 1;
        end
        
        if isempty(additional_array)
            additional_array = 1;
        end
    end
    
    accuracy_list = zeros(length(title_array),length(additional_array));
    
    for i = 1:length(title_array)
        for j = 1:length(additional_array)
            
            fprintf('%0.4f %0.4f ',title_array(i),additional_array(j));
            x = [title_array(i),additional_array(j)];
            
            iwv = x(1);
            awv = x(2);
            
            % Place the awv and iwv values in the data stoage structure
            data_storage.awv = awv;
            data_storage.iwv = iwv;

            issue_codes      = unique(learning_table.issue_codes);
            description_text = cell(length(issue_codes),1);
            weights          = cell(length(issue_codes),1);
            
            for k = 1:length(issue_codes)
                % Find all of the description text and all of the associated weights
                description_text{k} = [data_storage.unique_text_store{k} data_storage.issue_text_store{k} data_storage.additional_issue_text_store{k}];
                weights{k}          = [data_storage.weights_store{k};data_storage.issue_text_weight_store{k}*iwv;data_storage.additional_issue_text_weight_store{k}*awv];
            end
            
            data_storage.description_text = description_text;
            data_storage.weights          = weights;
            data_storage.issue_code_count = length(issue_codes);
            
            accuracy_list(i,j) = la.processAlgorithm(learning_materials,data_storage,1,'parsed_text');
            
            fprintf(' %0.4f\n',-accuracy_list(i,j))
        end
    end
    
    save(sprintf('temp/learning_algorithm_simple_outputs_%i_%s.mat',count,date),'accuracy_list','title_array','additional_array','step_size');
        
    count = count + 1;
end
    
%     for i = 1:length(iwv_list)
%         
%         fprintf('%0.4f ',iwv_list(i));
%         
%         
%         accuracy_list_title(i) = la.processAlgorithm(x,learning_materials,learning_table,data_storage,1,'parsed_title');
%         accuracy_list_text(i)  = la.processAlgorithm(x,learning_materials,learning_table,data_storage,1,'parsed_text');
%         
%         fprintf(' %0.4f%% %0.4f%%\n',-accuracy_list_title(i),-accuracy_list_text(i))
%     end


% Search for output files
files = dir('temp/learning_algorithm_simple_outputs_*_*.mat');

if isempty(files)
    % Print a warning message
    warning('ERROR: FILES NOT FOUND')
    
    % Set the outputs to empty
    accuracy_title = [];
    accuracy_text  = [];
    iwv            = [];
else
    
    master_title_array      = [];
    master_additional_array = [];
    master_accuracy_list    = [];
    
    % Iterate over all the files
    for i = 1:length(files)
        
        % Load the file
        output = load(files(i).name);
        
        % If it does not contain the field "learning_materials" it's the
        % processed data and what we're looking for
        if ~isfield(output,'learning_materials')
            
            % Add the outputs to the master lists
            
            title_temp = zeros(length(output.title_array)*length(output.additional_array),1);
            additional_temp = zeros(length(output.title_array)*length(output.additional_array),1);
            accuracy_temp = zeros(length(output.title_array)*length(output.additional_array),1);
            
            count = 1;
            for j = 1:length(output.title_array)
                for k = 1:length(output.additional_array)
                    title_temp(count) = output.title_array(j);
                    additional_temp(count) = output.additional_array(k);
                    accuracy_temp(count) = output.accuracy_list(j,k);
                    count = count + 1;
                end
            end
            
            master_title_array      = [master_title_array ; title_temp]; %#ok<AGROW>
            master_additional_array = [master_additional_array ; additional_temp]; %#ok<AGROW>
            master_accuracy_list    = [master_accuracy_list ; accuracy_temp]; %#ok<AGROW>
            % Deletion of constituent files under evaluation
            %             delete(files(i).name);
        else
            continue
        end
    end

    t = delaunay(master_title_array,master_additional_array);
    
    % Geneare the figure
    figure()
    hold on; grid on;
    fill3(master_title_array(t)',master_additional_array(t)',-master_accuracy_list(t)',-master_accuracy_list(t)')
    title('Paraeto surface for learning algorithm weighting')
    xlabel('Additional Word Weights')
    ylabel('Issue Word Weights')
    zlabel('Accuracy (%)')
    colorbar
    grid off; hold off;
    saveas(gcf,sprintf('optimized_surface_%s',date),'png')
    
    % Save the data into a master .mat file
    title_array      = master_title_array;
    additional_array = master_additional_array;
    accuracy_list    = -master_accuracy_list;
    save(sprintf('learning_algorithm_simple_optimization_results_%s',date),'title_array','additional_array','accuracy_list','learning_materials','data_storage');
    
    % Find the maximum accuracy
    [accuracy,index] = max(accuracy_list);
    
    
    max_title = title_array(index);
    max_additional = additional_array(index_text);
end

end