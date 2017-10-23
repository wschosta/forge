function mergeData(state)

merged_data = readtable(sprintf('finance_data/%s_merged_data.csv',state));
merged_data.full_name = merged_data.name;
merged_data.name = [];
merged_data.year = [];
merged_data.district = [];
merged_data.ID = [];

% name_parts = regexp(merged_data.name,'[, ]','split');

file_locations = {sprintf('data/%s/elo_model/*.csv',state), sprintf('data/%s/elo_model/MC/*.csv',state)};

fprintf('START----- Finance Data Merge for %s:\n',state)
fprintf('File Locations:\n')
fprintf('\t\t%s\n',file_locations{:})

fprintf('\n\nBEGIN:\n')

start_time = tic;

delete_str = '';

for f = 1:length(file_locations)
    
    files_to_match = dir(file_locations{f});
    
    for i = 1:length(files_to_match)
        
        
        read_file = readtable([files_to_match(i).folder '/' files_to_match(i).name]);
        
        full_name = cell(height(read_file),1);
        
        for j = 1:height(read_file)
            
            print_str = sprintf('%i %i %i',f,i,j);
            fprintf([delete_str,print_str]);
            delete_str = repmat(sprintf('\b'),1,length(print_str));
            
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
        
        if strcmp(state,'IN')
            
            people_file = readtable('data/IN/undergrad/people_2013-2014.xlsx');
            people_file.district = [];
            people_file.party = [];
            
            full_name = total_merge.name;
            
            a = util.CStrAinBP(people_file.name,full_name);
            b = util.CStrAinBP(full_name,people_file.name);
            
            total_merge = join(total_merge(b,:),people_file(a,:));
        end
        
        writetable(total_merge,sprintf('data/%s/merged_data/%s.csv',state,files_to_match(i).name))
    end
    
end

print_str = sprintf('COMPLETE ');
fprintf([delete_str,print_str]);

toc(start_time)

end