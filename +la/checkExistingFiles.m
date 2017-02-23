function [master_title_array,master_additional_array,master_accuracy_list,hit_list] = checkExistingFiles(files)

master_title_array      = [];
master_additional_array = [];
master_accuracy_list    = [];

% Iterate over all the files
hit_list = zeros(1,length(files));
for i = 1:length(files)
    
    % Load the file
    output = load([files(i).folder '\' files(i).name]);
    
    % If it does not contain the field "learning_materials" it's the
    % processed data and what we're looking for
    if ~isfield(output,'learning_materials')
        hit_list(i) = 1;
        if isfield(output,'flag')
            master_title_array      = [master_title_array ; output.title_array]; %#ok<AGROW>
            master_additional_array = [master_additional_array ; output.additional_array]; %#ok<AGROW>
            master_accuracy_list    = [master_accuracy_list ; output.accuracy_list]; %#ok<AGROW>
        else
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
        end
    else
        continue
    end
end

end