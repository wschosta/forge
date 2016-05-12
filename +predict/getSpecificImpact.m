function specific_impact = getSpecificImpact(revealed_preference,specific_impact)
switch revealed_preference
    case 0 % preference revealed to be no
        switch specific_impact
            case 0
                specific_impact = 0.99; % voted no, low consistency
            case 1
                specific_impact = 0.01; % voted no, high consistency
            otherwise
                specific_impact = 1 - specific_impact;
        end
    case 1
        switch specific_impact
            case 0
                specific_impact = 0.01; % voted yes, low consistency
            case 1
                specific_impact = 0.99; % voted yes, high consistency
            otherwise
                specific_impact = specific_impact; %#ok<ASGSL>
        end
    otherwise
        error('Functionality for non-binary revealed preferences not currently supported')
end
end