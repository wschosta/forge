function merged_file = diffAndMerge(file1,file2,file3)
% DIFFANDMERGE
% Find the difference between several tables and merge the data together

% Read in each of the files
table1 = readtable(file1);
table2 = readtable(file2);
table3 = readtable(file3);

% Get the variables names from table one
variable_names = table1.Properties.VariableNames;

% Differences between table 1 and 2
for i = 1:length(variable_names)
    if isa(table1.(variable_names{i}),'double')
        if all(isnan(table1.(variable_names{i})))
            table1.(variable_names{i}) = [];
        end
        
        if all(isnan(table2.(variable_names{i})))
            table2.(variable_names{i}) = [];
        end
        
        if all(isnan(table3.(variable_names{i})))
            table3.(variable_names{i}) = [];
        end
    end
end


% Merge table1 and table2 together
merged_file = outerjoin(table1,table2,'mergeKeys',true);

% Check the matched size of the tables 
if size(merged_file,2) ~= size(table1,2)
    for i = 1:100
        if size(outerjoin(table2(i,:),table3(i,:),'mergeKeys',true),1) ~= 1
            outerjoin(table1(i,:),table2(i,:),'mergeKeys',true)
        end
    end

    error('TABLE NOT THE SAME SIZE')
end

% Merge the merged tables and table3 together
merged_file = outerjoin(merged_file,table3,'mergeKeys',true);

% Check the matched size of the tables
if size(merged_file,2) ~= size(table3,2)
    for i = 1:100
        if size(outerjoin(merged_file(i,:),table3(i,:),'mergeKeys',true),1) ~= 1
            outerjoin(merged_file(i,:),table3(i,:),'mergeKeys',true)
        end
    end
    
    error('TABLE NOT THE SAME SIZE')
end

end