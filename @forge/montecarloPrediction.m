function [accuracy_list,accuracy_delta,legislators_list,bill_list,results_table] = montecarloPrediction(obj,bill_ids,people,sponsor_chamber_matrix,chamber_matrix,chamber)
% MONTECARLOPREDICTION
% Predict the monte carlo series for a legislative process

% Get the file list
files = dir(sprintf('%s/%s_prediction_model_m*.mat',obj.prediction_directory,upper(chamber(1))));

% if the file doesn't exist or if we're forcing a recompute
if isempty(files) || obj.recompute_montecarlo
    % Run the monte carlo analysis
    [accuracy_list,accuracy_delta,legislators_list,accuracy_steps_list,bill_list] = obj.runMonteCarlo(bill_ids,people,sponsor_chamber_matrix,chamber_matrix,chamber,obj.monte_carlo_number);

    specific_index = obj.monte_carlo_number;
    
    % Process the impacts
    results_table = obj.processLegislatorImpacts(accuracy_list,accuracy_delta,legislators_list,accuracy_steps_list,bill_list);
    
    if ~isempty(results_table)
        % Write the results to a table
        writetable(results_table,sprintf('%s/%s_prediction_model_results_m%i.csv',obj.outputs_directory,upper(chamber(1)),specific_index),'WriteRowNames',true)
        save(sprintf('%s/%s_prediction_model_results_m%i.mat',obj.prediction_directory,upper(chamber(1)),obj.monte_carlo_number),'results_table')
    end
else
    % If files of the right pattern do exist, search for the largest value
    % to use in the analysis
    specific_index = zeros(length(files),1);
    pattern = strcat(upper(chamber(1)),'_prediction_model_m(\d+).mat');
    for i = 1:length(files)
        specific_index(i) = str2double(cellfun(@(x) x{:},regexp(files(i).name,pattern,'tokens'),'UniformOutput',false));
    end
    specific_index = max(specific_index); % TODO build in an override to allow the plotting of specific montecarlo sizes
    
    % Read in the file with the largest monte carlo number
    data = load(sprintf('%s/%s_predictive_model_m%i.mat',obj.prediction_directory,upper(chamber(1)),specific_index));
    
    % Pull out the specifics
    accuracy_list       = data.accuracy_list;
    accuracy_delta      = data.accuracy_delta;
    legislators_list    = data.legislators_list;
    bill_list           = data.bill_ids;
    
    data = load(sprintf('%s/%s_predictive_model_results_m%i.mat',obj.prediction_directory,upper(chamber(1)),specific_index));
    results_table = data.results_table;
end

end