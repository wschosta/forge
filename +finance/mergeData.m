function mergeData(state)

merged_data = readtable(sprintf('finance_data/%s_merged_data.csv',state));
merged_data.full_name = merged_data.name;
merged_data.name = [];
merged_data.year = [];
merged_data.district = [];
merged_data.ID = [];

% name_parts = regexp(merged_data.name,'[, ]','split');

files_to_match = dir(sprintf('data/%s/elo_model/*.csv',state));

for i = 1:length(files_to_match)
    read_file = readtable([files_to_match(i).folder '/' files_to_match(i).name]); 
    
    full_name = cell(height(read_file),1);
    
    for j = 1:height(read_file)
        merged_name = read_file.last_name{j};
        
        if ~isempty(read_file.suffix{j})
            merged_name = sprintf('%s %s, %s',merged_name,read_file.suffix{j},read_file.first_name{j});
        else
            merged_name = sprintf('%s, %s', merged_name,read_file.first_name{j});
        end
        
        if ~isempty(read_file.middle_name{j})
            merged_name = sprintf('%s %s',merged_name,read_file.middle_name{j});
        end
        
        if ~isempty(read_file.nickname{j})
            merged_name = sprintf('%s (%s)',merged_name,read_file.nickname{j});
        end
        
        merged_name = upper(regexprep(merged_name,'\.',''));
        
        full_name{j} = merged_name;
        
    end
    
    read_file.full_name = full_name;
    
    a = util.CStrAinBP(merged_data.full_name,full_name);
    b = util.CStrAinBP(full_name,merged_data.full_name);
    
    total_merge = join(read_file(b,:),merged_data(a,:));
    
    writetable(total_merge,sprintf('data/%s/merged_data/%s.csv',state,files_to_match(i).name))
end


end