function [upper, lower] = state_properties(obj)

switch obj.state_ID
    % Per Squire Data we're looking for a high, medium, and low ranked
    % state. These will likely be:
    %   High: (1) CA, (2) NY, (3) WI
    %   Medium: (25) OR, (26) VT, (27) KY
    %   Low: (41) IN, (42) ME, (43) MT
    case 'CA'
        % Squire Rank: 1
        upper = 40;
        lower = 88;
    case 'IN'
        % Squire Rank: 41
        upper = 50;
        lower = 100;
    case 'KY'
        % Squire Rank: 27
        upper = 38;
        lower = 100;
    case 'ME'
        % Squire Rank: 42
        upper = 35; % though can vary between 31, 33, and 35
        lower = 154;
    case 'MT'
        % Squire Rank: 43
        upper = 50;
        lower = 100;
    case 'NY'
        % Squire Rank: 2
        upper = 63;
        lower = 150;
    case 'OH'
        % Squire Rank: 7
        upper = 33;
        lower = 99;
    case 'OR'
        % Squire Rank: 25
        upper = 30;
        lower = 60;
    case 'VT'
        % Squire Rank: 26
        upper = 30;
        lower = 150;
    case 'WI'
        % Squire Rank: 3
        upper = 33;
        lower = 99;
    case 'US'
        upper = 100;
        lower = 435;
    otherwise
        error('STATE NOT YET SUPPORTED')
end

end