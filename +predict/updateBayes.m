function [t_set,t_count,t_current,accuracy] = updateBayes(revealed_id,revealed_preference,t_set,chamber_specifics,t_count,ids,t_final_results)

t_count              = t_count + 1;
t_current            = sprintf('t%i',t_count);
t_previous           = sprintf('t%i',t_count-1);
t_set_previous_value = t_set.(t_previous);

matched_ids          = find(ismember(ids,revealed_id));
id_list              = 1:length(ids);
id_list(matched_ids) = [];

combined_impact          = zeros(length(ids),1);
combined_impact(id_list) = abs(1 - revealed_preference - chamber_specifics(id_list,matched_ids));

t_set_current_value = (combined_impact.*t_set_previous_value)./(1 + 2*combined_impact.*t_set_previous_value - combined_impact - t_set_previous_value);
% the denominator above is functionally the same as: (combined_impact*t_set{j,t_previous} + (1-combined_impact)*(1-t_set{j,t_previous})
% In the active form it reduces the number of references to the table
% which *should* be faster
t_set_current_value(t_set_current_value == 0) = 0.001;
t_set_current_value(t_set_current_value == 1) = 0.999;
t_set_current_value(matched_ids)              = abs(revealed_preference - 0.001);

t_check   = round(t_set_current_value) == t_final_results;
incorrect = sum(t_check == false);
are_nan   = sum(isnan(t_final_results(t_check == false)));
accuracy  = 100*(1-(incorrect-are_nan)/(100-are_nan));

t_set.(t_current) = t_set_current_value;

end