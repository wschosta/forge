function mergeSeniority(state)

merged_data = readtable(sprintf('finance_data/seniority_data_%s.csv',state));
merged_data.full_name = merged_data.candidate;
merged_data.candidate = [];
merged_data.terms_served = merged_data.cumulative;
merged_data.cumulative = [];
merged_data.chamb = [];
merged_data.thirdparty = [];
merged_data.democratic = [];
merged_data.republican  = [];

merge_data_directory = sprintf('data/%s/merged_data',state);

if exist(sprintf('data/%s/merged_data',state),'dir') ~= 7
    error('Currenty not supported if files don''t aleady exist! Run finance.mergeData first!')
end

file_location = sprintf('%s/*.csv',merge_data_directory);

fprintf('START----- Seniority Data Merge for %s:\n',state)
fprintf('File Location:\n')
fprintf('\t\t%s\n',file_location)

fprintf('\n\nBEGIN:\n')


% first we need to cut down the data set to just the final year for each
% candidate
unique_names = unique(merged_data.full_name);

unique_data = [];

for i = 1:length(unique_names)
    subset_data = merged_data(strcmp(merged_data.full_name,unique_names{i}),:);
    unique_data = [unique_data ; subset_data(end,:)]; %#ok<AGROW>
end

unique_data.election_year = [];

start_time = tic;

delete_str = '';


files_to_match = dir(file_location);

for i = 1:length(files_to_match)
    
    read_file = readtable([files_to_match(i).folder '/' files_to_match(i).name]);
    
    full_name = cell(height(read_file),1);
    
    for j = 1:height(read_file)
        
        print_str = sprintf('%i %i',i,j);
        fprintf([delete_str,print_str]);
        delete_str = repmat(sprintf('\b'),1,length(print_str));
        
        merged_name = read_file.last_name{j};
        
        if iscell(read_file.suffix(j)) && ~isempty(read_file.suffix{j})
            merged_name = sprintf('%s %s, %s',merged_name,read_file.suffix{j},read_file.first_name{j});
        else
            merged_name = sprintf('%s, %s', merged_name,read_file.first_name{j});
        end
        
        if iscell(read_file.middle_name(j)) && ~isempty(read_file.middle_name{j})
            merged_name = sprintf('%s %s',merged_name,read_file.middle_name{j});
        end
        
        if iscell(read_file.nickname(j)) && ~isempty(read_file.nickname{j})
            merged_name = sprintf('%s (%s)',merged_name,read_file.nickname{j});
        end
        
        merged_name = upper(regexprep(merged_name,'\.',''));
        
        full_name{j} = merged_name;
        
    end
    
    read_file.full_name = full_name;
    
    a = util.CStrAinBP(unique_data.full_name,full_name);
    b = util.CStrAinBP(full_name,unique_data.full_name);
    
    total_merge = join(read_file(b,:),unique_data(a,:));
    
    writetable(total_merge,sprintf('data/%s/merged_data/%s',state,files_to_match(i).name))
end


print_str = sprintf('COMPLETE ');
fprintf([delete_str,print_str]);

toc(start_time)

end