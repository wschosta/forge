function main(varargin)
% MAIN
% The driver file for the leargning algorithm functions
%
% Developed by Walter Schostak and Eric Waltenburg
%
% See also forge

in = inputParser;
addOptional(in,'optimize_frontier',0,@islogical);
addOptional(in,'process_algorithm',1,@islogical);
addOptional(in,'relearn_materials',0,@islogical);
parse(in,varargin{:});

optimize_frontier = in.Results.optimize_frontier;
process_algorithm = in.Results.process_algorithm;
relearn_materials = in.Results.relearn_materials;

% awv = 0.8467; % set by analysis
% iwv = 0.8645; % set by analysis

if exist('+la\description_learning_materials.mat','file') ~= 2 || relearn_materials
    
    [bill_title,policy_area,text,~,complete_array,~] = la.xmlparse('force_recompute',false); % TODO eventually need to add the recompute flag & check updates
    
    % Eliminate incomplete bills
    complete_array = logical(complete_array);
    bill_title     = bill_title(complete_array);
    policy_area    = policy_area(complete_array);
    text           = text(complete_array);
    
    % Create map of issue codes and subjects
    master_issue_codes   = containers.Map(1:length(unique(policy_area)),unique(policy_area));
    
    % Create map of additional words, hand chosen to increase accuracy
    additional_issue_codes = containers.Map(1:length(unique(policy_area)),{'Tomato corn',...
        'Cat dog','Military troops','Movie award','black white','trade rights',...
        'government representative','police riot','econometrics financing',...
        'school academy','fema hurricane','power electricity','pristine clean',...
        'children babies','feduciary stock','world global','politics republic',...
        'medicine hospital','neighborhood village','migrant visa',...
        'realism liberalism','work jobs','tort reform','indian born',...
        'park mine','tech','historical anthropology','benefits handouts',...
        'fun football','taxes tax','roads highways','river lake'});
    
    % Set list of common words to ignore
    common_words = la.getCommonWordsList();
    common_words = [common_words {'bill','ammendment'}];
    
    generate_issue_codes = containers.Map(unique(policy_area),1:length(unique(policy_area)));
    
    issue_codes  = cellfun(@(x) generate_issue_codes(x),policy_area);
    unified_text = cellfun(@(a,b) [a ' ' b],bill_title,text,'UniformOutput',false);
    
    delete_str = '';
    
    parsed_title = cell(length(bill_title),1);
    parsed_text  = cell(length(unified_text),1);
    for i = 1:length(unified_text)
        parsed_text{i}  = la.cleanupText(unified_text{i},common_words);
        parsed_title{i} = la.cleanupText(bill_title{i},common_words);
        
        print_str = sprintf('%i',i);
        fprintf([delete_str,print_str]);
        delete_str = repmat(sprintf('\b'),1,length(print_str));
    end
    print_str = sprintf('Finished Text and Title Parsing!\n');
    fprintf([delete_str,print_str]);
    
    learning_materials = table(bill_title,unified_text,issue_codes,parsed_text,parsed_title);
    
    % Generate the learning table with the taught instructions and the
    % additional common word, issue, and additional issue codes
    [learning_table,data_storage] = la.generateLearningTable(learning_materials,common_words,master_issue_codes,additional_issue_codes);
    
    save('+la\description_learning_materials.mat','learning_materials','learning_table','data_storage','master_issue_codes','additional_issue_codes','bill_title','policy_area','text','common_words');
    
else
    load('+la\description_learning_materials.mat')
end


if optimize_frontier
     
    % Organized = [title additional];
    min_value = [0   0];
    max_value = [4   4];
    step_size = [0.2 0.2];
    
    estimated_time = length(min_value(1):step_size(1):max_value(1))*length(min_value(2):step_size(2):max_value(2))*180/3600;
    fprintf('Estimated time to completion of first round: %0.2f hours\n',estimated_time)
    
    [accuracy,iwv,awv] = la.optimizeFrontierSimple(min_value,max_value,step_size,learning_materials,learning_table,data_storage); 
    
    fprintf('Max Accuracy %8.3f%% || a %10.2f | i %10.2f \n',accuracy,awv,iwv);
else
    load('+la\learning_algorithm_results.mat')
end

if process_algorithm
    % Process the results
    outputs = la.processAlgorithm(learning_materials,data_storage,0);
    
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
    real_histogram  = histogram(processed.issue_codes); %#ok<NASGU>
    coded_histogram = histogram(processed.learning_coded); %#ok<NASGU>
    legend({'Actual','Learning Coded'})
    axis tight
    xlabel('Issue Codes')
    ylabel('Frequency')
    title(sprintf('Learning coded bills as compared to their actual categories\nAccuracy: %0.4f%%',accuracy));
    hold off
    saveas(gcf,sprintf('+la/learning_algorithm_historgram_%s',date),'png')
    % --- end histogram
    
    % Generate some additional data for the 
    adjacency_matrix = zeros(length(unique(processed.issue_codes)),length(unique(processed.learning_coded)));
    
    for i = 1:length(processed.issue_codes)
        adjacency_matrix(processed.issue_codes(i),processed.learning_coded(i)) = adjacency_matrix(processed.issue_codes(i),processed.learning_coded(i)) + 1;
    end
    
    xlswrite(sprintf('+la/testdata_%s.xlsx',date),adjacency_matrix);
    
    % Write the learning table to a file
    save(sprintf('+la/temp/learning_algorithm_results_%s',date),'outputs','real_histogram','coded_histogram');
    
    % Structure the data for output
    data_storage.awv = awv;
    data_storage.iwv = iwv;
    
    % Create a checkpoint for the learning algorithm data based on the data
    save(sprintf('+la/temp/learning_algorithm_data_%s',date),'learning_table','data_storage');
    
    % Save it in its normal file location
    save('+la/learning_algorithm_data','learning_table','data_storage');
end

end