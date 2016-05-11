% in the future this is most likely abstractable, for now I'll do
% it manually and not use this function
function t_table = updateBayes(bayes)

t_table = array2table(NaN(length(bayes.Properties.RowNames),1),'VariableNames',{'p'},'RowNames',bayes.Properties.RowNames);

for i = bayes.Properties.RowNames'
    time_update = 1;
    count = 1;
    for j = bayes.Properties.VariableNames
        if count == length(bayes.Properties.VariableNames) && (isnan(bayes{i,j}) || bayes{i,j} == -1)
            time_update = bayes{i,j};
        end
        
        if ~isnan(bayes{i,j}) && (bayes{i,j} ~= -1)
            time_update = time_update * bayes{i,j};
        end
        
        count = count + 1;
    end
    
    if (isnan(time_update) || time_update == -1)
        t_table{i,'p'} = time_update/0.5;
    else
        t_table{i,'p'} = time_update;
    end
end
end
