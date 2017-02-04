function main()
% MAIN
% The driver file for the leargning algorithm functions
%
% Developed by Walter Schostak and Eric Waltenburg
%
% See also forge

optimize_frontier = false;
process_algorithm = true;

awv = 0.3870; % set by analysis
iwv = 1.0262; % set by analysis

% if ~exist(learning_materials whatever-we-call-it) || recompute

[title,policy_area,text,subject_area,complete_array,bill_list] = la.xmlparse(); % eventually need to add the recompute flag & check updates

% Eliminate incomplete bills
complete_array = logical(complete_array);
title          = title(complete_array);
policy_area    = policy_area(complete_array);
text           = text(complete_array);
subject_area   = subject_area(complete_array);
bill_list      = bill_list(complete_array);
complete_array = complete_array(complete_array); % silly but might as well be consistent

master_issue_codes   = containers.Map(1:length(unique(policy_area)),unique(policy_area));
generate_issue_codes = containers.Map(unique(policy_area),1:length(unique(policy_area)));

issue_codes  = cellfun(@(x) generate_issue_codes(x),policy_area);
unified_text = cellfun(@(a,b) [a ' ' b],title,text,'UniformOutput',false);

learning_materials = table(unified_text,issue_codes);

% read in processed text data

% learning_materials = readtable(sprintf('%s/%s/learning_algorithm/description_learning_materials.xlsx',data_location,state));

% Set list of common words to ignore
common_words = la.getCommonWordsList();
common_words = [common_words {'bill','ammendment'}];
% % Create map of issue codes and subjects
% master_issue_codes = containers.Map([1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16],...
%     {'Agriculture','Commerce, Business, Economic Development',...
%     'Courts & Judicial','Education','Elections & Apportionment',...
%     'Employment & Labor','Environment & Natural Resources',...
%     'Family, Children, Human Affairs & Public Health',...
%     'Banks & Financial Institutions','Insurance',...
%     'Government & Regulatory Reform','Local Government',...
%     'Roads & Transportation','Utilities, Energy & Telecommunications',...
%     'Ways & Means, Appropriations','Other'});
% 
% % Create map of additional words, hand chosen to increase accuracy
additional_issue_codes = containers.Map(1:length(unique(policy_area)),cell(1,length(unique(policy_area)))); % just for now

% Generate the learning table with the taught instructions and the
% additional common word, issue, and additional issue codes
[learning_table,data_storage] = la.generateLearningTable(learning_materials,common_words,master_issue_codes,additional_issue_codes);

if optimize_frontier
    % Run the frontier optimization to find the optimal value for the issue
    % word value (iwv) and the additional word value (awv)
    
    location      = 'H'; % string to identify the location of the run for distributed computing
    robust        = 10;  % number of times to rerun a grid square
    max_grid_size = 3;   % max number for the awv and iwv coefficient
    iterations    = 100; % number of points to select within the one by one grid
    
    % Run the optimization
    [accuracy, awv, iwv] = la.optimizeFrontier(location,robust,max_grid_size,iterations,learning_materials,learning_table,data_storage,data_location,state);
    
    % Print the results
    fprintf('Max Accuracy %8.3f%% || a %10.2f | i %10.2f \n',accuracy,awv,iwv);
end

if process_algorithm
    
    % Set the awv and iwv values
    x(1) = awv;
    x(2) = iwv;
    
    % Process the results 
    outputs = la.processAlgorithm(x,learning_materials,learning_table,data_storage,0);
    
    % Check the stats
    processed = outputs.processed;
    correct   = outputs.correct;
    total     = outputs.total;
    accuracy  = outputs.accuracy;
    
    % Print the results output
    fprintf('Results: %i of %i (%0.2f%%) || a %10.2f | i %10.2f \n',correct,total,accuracy,awv,iwv);
    
    % Manually make the histogram here so it can reflect all the categories
    % --- begin histogram
    figure()
    hold on; grid on;
    
    keys        = master_issue_codes.keys;
    tick_values = cell(1,length(keys)+1);
    peak        = -inf;
    
    for i = 1:length(keys)
        tick_values{i} = sprintf('%i',keys{i});
        
        rectangle('Position',[i-0.5,0,1,sum(processed.issue_codes == keys{i})+0.000001],'FaceColor','b')
        peak = max([peak, sum(processed.issue_codes == keys{i})]);
    end
    
    axis([0.5,16.5,0,peak])
    ax = gca;
    set(ax,'XTick',[keys{:}])
    set(ax,'XTickLabel',tick_values)

    xlabel('Issue Codes')
    ylabel('Frequency')
    title('Distribution of Categorized Bills')
    saveas(gcf,sprintf('learning_algorithm_historgram_%s',date),'png')
    % --- end histogram
    
    
    % Write the learning table to a file
    writetable(processed,sprintf('learning_algorithm_results_%s.csv',date))
    
    % Structure the data for output
    data_storage.awv = awv;
    data_storage.iwv = iwv;
    
    % Create a checkpoint for the learning algorithm data based on the data
    save(sprintf('learning_algorithm_data_%s',date),'learning_table','data_storage');
    
    % Save it in its normal file location
    save('learning_algorithm_data','learning_table','data_storage'); 
end

end