function specific_impact = getSpecificImpact(revealed_preference,specific_impact)

if revealed_preference == 1
    if specific_impact == 1
        specific_impact = 0.999; % voted yes, high consistency
    elseif specific_impact == 0
        specific_impact = 0.001; % voted yes, low consistency
    end
elseif revealed_preference == 0
    if specific_impact == 0
        specific_impact = 0.999; % voted no, low consistency
    elseif specific_impact == 1
        specific_impact = 0.001; % voted no, high consistency
    else
        specific_impact = 1 - specific_impact;
    end
else
    error('Functionality for non-binary revealed preferences not currently supported')
end

end