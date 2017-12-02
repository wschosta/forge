function proximity_matrix = processSeatProximity(obj,people)
% PROCESSSEATPROXIMITY
% Find the distance between each legislator in the chamber

% Create the string array list (which allows for referencing variable names
ids = util.createIDstrings(people{:,'sponsor_id'});

% Pull the x position
x    = people{:,'SEATROW'};

% Pull the y position
y    = people{:,'SEATCOLUMN'};

% Find the distance between them
dist = sqrt(bsxfun(@minus,x,x').^2 + bsxfun(@minus,y,y').^2);

% Put the array into a table
proximity_matrix      = array2table(dist,'RowNames',ids,'VariableNames',ids);

% Add in the sponsor names to the table
% proximity_matrix.name = obj.getSponsorName(ids)';

end