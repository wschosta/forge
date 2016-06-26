function results_table = processLegislatorImpacts(obj,accuracy_list,accuracy_list_delta,legislators_list,accuracy_steps_list,bill_list)
% PROCESSLEGISLATORIMPACTS
% find the impacts of all legislators across the all bills in the monte
% carlo prediction
% TODO comments

% Initialize the list
master_list = [];

if isempty(legislators_list) || isempty(accuracy_list) || isempty(accuracy_steps_list)
    results_table = [];
    return
end

% Iterate over the legislator list 
for i = 1:size(legislators_list,1)
    
    specific_accuracy_list = zeros(size(legislators_list{i,1},1),size(accuracy_steps_list{i,1}(1),1)+1);
    specific_delta_list    = zeros(size(legislators_list{i,1},1),size(accuracy_steps_list{i,1}(1),1));
    
    % Iterate over the number of predictions
    for j = 1:size(accuracy_list,2)
        
        specific_accuracy_list(j,1) = accuracy_list(i,j) - accuracy_list_delta(i,j); % find the starting accuracy
        
        
        for k = 1:length(accuracy_steps_list{i,j})
            specific_accuracy_list(j,k+1) = specific_accuracy_list(j,k) + accuracy_steps_list{i,j}(k); 
            specific_delta_list(j,k)      = accuracy_steps_list{i,j}(k);
        end
    end
    
    % A neat way to generate the monte carlo spread for a single
    % bill, not sure it's super useful for the massive number of
    % bills but neat on a single bill basis
    
    %         figure()
    %         hold on ; grid on ;
    %         title('Accuracy Over Predictive Set')
    %         plot(specific_accuracy_list')
    %         xlabel('Revealed preference points')
    %         ylabel('Accuracy')
    %         hold off
    %
    %         figure()
    %         title('Delta Accuracy Over Predictive Set')
    %         hold on ; grid on ;
    %         plot(specific_delta_list')
    %         xlabel('Revealed preference points')
    %         ylabel('Change in Accuracy')
    %         hold off
    
    % I need to come up with some equation to relate initial
    % accuracy revealed, preference posiition (1-8), change in
    % accuracy as a result of their revealed preference...
    % maybe others? average agreement score with other
    % legislators?
    
    unique_legislators = unique(legislators_list{i});
    impact_score       = cell(1,length(unique_legislators));
    placement          = cell(1,length(unique_legislators));
    legislator_score   = zeros(length(unique_legislators),1);
    placement_points   = linspace(length(legislators_list{i}),1,length(legislators_list{i}))';
    for j = 1:length(unique_legislators)
        impact_score{j}     = specific_delta_list(ismember(legislators_list{i},unique_legislators(j)));
        placement{j}        = sum(ismember(legislators_list{i},unique_legislators(j)),2);
        legislator_score(j) = mean(impact_score{j})/(specific_accuracy_list(1,1)*mean(placement{j}.*placement_points));
    end
    
    master_list = [master_list ; unique_legislators legislator_score]; %#ok<AGROW>
end

master_unique_legislators = unique(master_list(:,1));
coverage = NaN(length(master_unique_legislators),1);
results  = NaN(length(master_unique_legislators),1);
for i = 1:length(master_unique_legislators)
    index       = ismember(master_list(:,1),master_unique_legislators(i));
    coverage(i) = sum(index);
    results(i)  = mean(master_list(index,2));
end
coverage = coverage / length(bill_list);
results  = results / max(results);

sponsor_names = obj.getSponsorName(master_unique_legislators);
results_table = table(master_unique_legislators,sponsor_names,coverage,results);

end