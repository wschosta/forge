function [varargout] = createTable(rows,columns,type)
% CREATETABLE
% Create a table based on the type of tables needed

% Switch by type of table being created
switch type
    case 'NaN'  % initalized with NaNs
        return_table = array2table(NaN(length(rows),length(columns)),'RowNames',rows,'VariableNames',columns);
    case 'zero' % initialied with zeros
        return_table = array2table(zeros(length(rows),length(columns)),'RowNames',rows,'VariableNames',columns);
    otherwise   % throw an error
        error('TABLE TYPE NOT FOUND');
end

% Give the option to return a multiple tables of the same type
for i = 1:max(nargout,1)
    varargout{i} = return_table; %#ok<AGROW>
end

end