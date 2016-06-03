function [t_set,t_count,t_current] = updateBayes(revealed_id,revealed_preference,t_set,chamber_specifics,t_count,ids)

t_count              = t_count + 1;
t_current            = sprintf('t%i',t_count);
t_previous           = sprintf('t%i',t_count-1);
t_set_previous_value = t_set.(t_previous);
t_set_current_value  = NaN(length(ids),1);

matched_ids = find(ismember(ids,revealed_id));

for j = 1:length(ids)
    if ~any(j == matched_ids)
        combined_impact = 1;
        
        for k = 1:length(matched_ids)
            combined_impact = combined_impact*predict.getSpecificImpact(revealed_preference,chamber_specifics(j,k));
        end
        t_set_current_value(j) = (combined_impact*t_set_previous_value(j))/(1 + 2*combined_impact*t_set_previous_value(j) - combined_impact - t_set_previous_value(j));
        % the denominator above is functionally the same as: (combined_impact*t_set{j,t_previous} + (1-combined_impact)*(1-t_set{j,t_previous})
        % In the active form it reduces the number of references to the table
        % which *should* be faster
    else
        switch revealed_preference
            case 0
                t_set_current_value(j) = 0.01;
            case 1
                t_set_current_value(j) = 0.99;
            otherwise
                error('Functionality for non-binary revealed preferences not currently supported')
        end
    end
end

t_set.(t_current) = t_set_current_value;

end