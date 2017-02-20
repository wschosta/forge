function [accuracy_title,accuracy_text,iwv] = optimizeFrontierSimple(min_value,max_value,step_size,learning_materials,learning_table,data_storage)
% OPTIMIZEFRONTIERSIMPLW
% Funciton to find the optimal issue word value (iwv) independent from the
% additonal word value (awv)

count = 0;
while floor(log10(step_size)) ~= -4
    
    if count > 0
        [~,index] = max(-accuracy_list_title);
        
        step_size = step_size/2;
        min_value = iwv_list(index) - step_size;
        max_value = iwv_list(index) + step_size;
    end
    
    iwv_list = [min_value:step_size:max_value]'; %#ok<NBRAK>
    accuracy_list_title = zeros(length(iwv_list),1);
    accuracy_list_text = zeros(length(iwv_list),1);
     
    for i = 1:length(iwv_list)
        
        fprintf('%0.4f ',iwv_list(i));
        
        x = [0,iwv_list(i)];
        accuracy_list_title(i) = la.processAlgorithm(x,learning_materials,learning_table,data_storage,1,'parsed_title');
        accuracy_list_text(i)  = la.processAlgorithm(x,learning_materials,learning_table,data_storage,1,'parsed_text');
        fprintf(' %0.4f%% %0.4f%%\n',-accuracy_list_title(i),accuracy_list_text(i))
    end
    save(sprintf('+la/temp/learning_algorithm_simple_outputs_%02d.mat',step_size*1000),'iwv_list','accuracy_list_title','accuracy_list_text','step_size');
    
    count = count + 1;
end

% Search for output files
files = dir('+la/temp/learning_algorithm_simple_outputs_*.mat');

if isempty(files)
    % Print a warning message
    warning('ERROR: FILES NOT FOUND')
    
    % Set the outputs to empty
    accuracy_title = [];
    accuracy_text  = [];
    iwv            = [];
else
    
    master_iwv      = [];
    master_accuracy_title = [];
    master_accuracy_text  = [];
    
    % Iterate over all the files
    for i = 1:length(files)
        
        % Load the file
        output = load(files(i).name);
        
        % If it does not contain the field "learning_materials" it's the
        % processed data and what we're looking for
        if ~isfield(output,'learning_materials')
            
            % Add the outputs to the master lists
            master_iwv            = [master_iwv output.iwv_list]; %#ok<AGROW>
            master_accuracy_title = [master_accuracy_title output.accuracy_list_title]; %#ok<AGROW>
            master_accuracy_text  = [master_accuracy_text output.accuracy_list_text]; %#ok<AGROW>
            % Deletion of constituent files under evaluation
            %             delete(files(i).name);
        else
            continue
        end
    end
    
    % Geneare the figure
    figure()
    hold on; grid on;
    plot(master_iwv,master_accuracy_title,master_accuracy_text);
    title('Issue word curve for learning algorithm weighting')
    xlabel('Issue Word Weights')
    ylabel('Accuracy (%)')
    colorbar
    grid off; hold off;
    
    % Save the results
    saveas(gcf,'+la/paraeto_surface_maximized','png')
    
    % Save the data into a master .mat file
    iwv_list            = master_iwv;
    accuracy_list_title = master_accuracy_title;
    accuracy_list_text  = master_accuracy_text;
    save(sprintf('+la/learning_algorithm_simple_optimization_results_%s',date),'awv_list','accuracy_list_title','accuracy_list_text','learning_materials','data_storage');
    
    % Find the maximum accuracy
    [accuracy_title,index_title] = max(accuracy_list_title);
    [accuracy_text,index_text] = max(accuracy_list_text);
    
    
    iwv = [iwv_list(index_title) iwv_list(index_text)];
end

end