function [accuracy_list,accuracy_delta,legislators_list,accuracy_steps_list,bill_list,results_table] = montecarloPrediction(obj,bill_ids,people,sponsor_chamber_matrix,consistency_matrix,sponsor_committee_matrix,chamber_matrix,chamber)
% MONTECARLOPREDICTION
% Predict the monte carlo series for a legislative process

% Get the file list
files = dir(sprintf('%s/%s_predictive_model_m*.mat',obj.outputs_directory,lower(chamber)));

% if the file doesn't exist or if we're forcing a recomput
if isempty(files) || obj.recompute_montecarlo
    % Run the monte carlo analysis
    [accuracy_list,accuracy_delta,legislators_list,accuracy_steps_list,bill_list] = obj.runMonteCarlo(bill_ids,people,sponsor_chamber_matrix,consistency_matrix,sponsor_committee_matrix,chamber_matrix,0,chamber,obj.monte_carlo_number);
else
    % Iffiles oft he right pattern do exist, search for the largest value
    % to use in the analysis
    specific_index = zeros(length(files),1);
    pattern = strcat(lower(chamber),'_predictive_model_m(\d+).mat');
    for i = 1:length(files)
        specific_index(i) = str2double(cellfun(@(x) x{:},regexp(files(i).name,pattern,'tokens'),'UniformOutput',false));
    end
    specific_index = max(specific_index);
    
    % Read in the file with the largest monte carlo number
    data = load(sprintf('%s/%s_predictive_model_m%i.mat',obj.outputs_directory,lower(chamber),specific_index));
    
    % Pull out the specifics
    accuracy_list       = data.accuracy_list;
    accuracy_delta      = data.accuracy_delta;
    legislators_list    = data.legislators_list;
    accuracy_steps_list = data.accuracy_steps_list;
    bill_list           = data.bill_ids;
end

% Process the impacts
results_table = obj.processLegislatorImpacts(accuracy_list,accuracy_delta,legislators_list,accuracy_steps_list,bill_list);

% Write the results to a table
writetable(results_table,sprintf('%s/%s_results_table.csv',obj.outputs_directory,lower(chamber)),'WriteRowNames',true)

end