function sponsor_name = getSponsorName(obj,id_code)
% GETSPONSORNAME
% Turns IDs into sponsor names

if iscell(id_code)
    % If it's a cell or an array of cells, strip away the text
    specific_id  = cellfun(@str2double,regexprep(id_code,'id',''));
    
    % Pull out the sponsor names
    sponsor_name = obj.people.name(arrayfun(@(x)find(obj.people.sponsor_id==x,1),specific_id));
else % already numeric
    % Pull out the sponsor names
    sponsor_name = obj.people.name(arrayfun(@(x)find(obj.people.sponsor_id==x,1),id_code));
end

end