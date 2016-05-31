function [t_set,t_count,t_current] = updateBayes(revealed_id,revealed_preference,t_set,chamber_matrix,t_count,ids)

t_count           = t_count + 1;
t_current         = sprintf('t%i',t_count);
t_previous        = sprintf('t%i',t_count-1);
t_set.(t_current) = NaN(length(ids),1);

expressed_preference = array2table(zeros(length(ids),2),'VariableNames',{'expressed','locked'},'RowNames',ids);
expressed_preference{:,'expressed'}           = 0;
expressed_preference{revealed_id,'expressed'} = 1;

preference_unknown = expressed_preference(~expressed_preference.expressed,:).Properties.RowNames';
preference_known   = expressed_preference(~~expressed_preference.expressed,:).Properties.RowNames'; % dumb but effective

for j = preference_unknown
    combined_impact = 1;
    for k = preference_known
        combined_impact = combined_impact*predict.getSpecificImpact(revealed_preference,chamber_matrix{j,k});
    end
    
    t_set{j,t_current} = (combined_impact*t_set{j,t_previous})/(combined_impact*t_set{j,t_previous} + (1-combined_impact)*(1-t_set{j,t_previous}));
end

end