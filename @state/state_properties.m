function [upper, lower] = state_properties(obj)

switch obj.state_ID
    case 'CA'
        upper = 40;
        lower = 88;
    case 'IN'
        upper = 50;
        lower = 100;
    case 'OH'
        upper = 33;
        lower = 99;
    case 'US'
        upper = 100;
        lower = 435;
    otherwise
        error('STATE NOT YET SUPPORTED')
end

end