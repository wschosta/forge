function return_table = createTable(rows,columns,type)
% Switch by type of table being created
switch type
    case 'NaN'  % initalized with NaNs
        return_table = array2table(NaN(length(rows),length(columns)),'RowNames',rows,'VariableNames',columns);
    case 'zero' % initialied with zeros
        return_table = array2table(zeros(length(rows),length(columns)),'RowNames',rows,'VariableNames',columns);
    otherwise   % throw an error
        error('TABLE TYPE NOT FOUND');
end
end