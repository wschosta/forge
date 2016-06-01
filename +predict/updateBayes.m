function [t_set,t_count,t_current] = updateBayes(revealed_id,revealed_preference,t_set,chamber_matrix,t_count,ids)

t_count           = t_count + 1;
t_current         = sprintf('t%i',t_count);
t_previous        = sprintf('t%i',t_count-1);
t_set.(t_current) = NaN(length(ids),1);

expressed_preference = array2table(zeros(length(ids),1),'VariableNames',{'expressed'},'RowNames',ids);
expressed_preference{revealed_id,'expressed'} = 1;

preference_unknown = expressed_preference(~expressed_preference.expressed,:).Properties.RowNames';
preference_known   = expressed_preference(~~expressed_preference.expressed,:).Properties.RowNames'; % dumb but effective

for j = preference_unknown
    combined_impact = 1;
    for k = preference_known 
        % currently this is always a single value but writing it this way
        % allows for multiple values in the future
        combined_impact = combined_impact*predict.getSpecificImpact(revealed_preference,chamber_matrix{j,k});
    end
    
    t_set{j,t_current} = (combined_impact*t_set{j,t_previous})/(1 + 2*combined_impact*t_set{j,t_previous} - combined_impact - t_set{j,t_previous}); 
    % the denominator above is functionally the same as: (combined_impact*t_set{j,t_previous} + (1-combined_impact)*(1-t_set{j,t_previous})
    % In the active form it reduces the number of references to the table
    % which *should* be faster
end

end