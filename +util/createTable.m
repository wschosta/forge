function [varargout] = createTable(rows,columns,type)
% Switch by type of table being created
switch type
    case 'NaN'  % initalized with NaNs
        return_table = array2table(NaN(length(rows),length(columns)),'RowNames',rows,'VariableNames',columns);
    case 'zero' % initialied with zeros
        return_table = array2table(zeros(length(rows),length(columns)),'RowNames',rows,'VariableNames',columns);
    otherwise   % throw an error
        error('TABLE TYPE NOT FOUND');
end

for i = 1:max(nargout,1)
    varargout{i} = return_table; %#ok<AGROW>
end

end