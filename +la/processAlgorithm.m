function output = processAlgorithm(learning_materials,data_storage,output_flag,varargin)
% PROCESSALGORITHM
% Process the total bill set based on a given learned set

if length(varargin) == 1
    focus_text = varargin{1};
else
    focus_text = 'parsed_text';
end

% Read in the bill list
learning_coded = zeros(length(learning_materials.issue_codes),1);
issue          = cell(1,length(learning_materials.issue_codes))';

analysis_text = learning_materials.(focus_text);

delete_str = '';
for i = 1:length(analysis_text)
    
    [learning_coded(i), issue{i}] = la.classifyBill(analysis_text{i},data_storage);
    
    print_str = sprintf('%i ',i);
    fprintf([delete_str,print_str]);
    delete_str = repmat(sprintf('\b'),1,length(print_str));
end

print_str = sprintf('Algorithm Process Complete! ');
fprintf([delete_str,print_str]);

% create the learned table
learned_table = table(learning_coded,issue);

% create the processed table
processed = [learning_materials,learned_table];

% Find how many bills were correctly matched
processed.matched = (processed.issue_codes == processed.learning_coded);

% Generate basic stats
correct  = sum(processed.matched);
total    = length(processed.matched);
accuracy = correct/total*100;

if output_flag
    output = accuracy;
else
    % Generate the output structure
    output = struct();
    output.processed = processed;
    output.correct = correct;
    output.total = total;
    output.accuracy = accuracy;
end

end