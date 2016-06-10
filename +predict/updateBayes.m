function [t_set,t_count,t_current,accuracy] = updateBayes(revealed_id,revealed_preference,t_set,chamber_specifics,t_count,ids,t_final_results)

t_count              = t_count + 1;
t_current            = sprintf('t%i',t_count);
t_previous           = sprintf('t%i',t_count-1);
t_set_previous_value = t_set.(t_previous);
t_set_current_value  = NaN(length(ids),1);

matched_ids = find(ismember(ids,revealed_id));
id_list = 1:length(ids);
id_list(ismember(ids,revealed_id)) = [];

for j = id_list
    combined_impact = 1;
    for k = 1:length(matched_ids)
        if chamber_specifics(j,matched_ids(k)) == 1 || chamber_specifics(j,matched_ids(k)) == 0
            specific_impact = abs(revealed_preference(k) - 0.001);
        else
            specific_impact = abs(1 - revealed_preference(k) - chamber_specifics(j,matched_ids(k)));
        end
        
        combined_impact = combined_impact*specific_impact;
    end
    t_set_current_value(j) = (combined_impact*t_set_previous_value(j))/(1 + 2*combined_impact*t_set_previous_value(j) - combined_impact - t_set_previous_value(j));
    % the denominator above is functionally the same as: (combined_impact*t_set{j,t_previous} + (1-combined_impact)*(1-t_set{j,t_previous})
    % In the active form it reduces the number of references to the table
    % which *should* be faster
end

for j = 1:length(matched_ids)
    t_set_current_value(matched_ids(j)) = abs(revealed_preference(j) - 0.001);
end

t_check   = round(t_set_current_value) == t_final_results;
incorrect = sum(t_check == false);
are_nan   = sum(isnan(t_final_results(t_check == false)));
accuracy  = 100*(1-(incorrect-are_nan)/(100-are_nan));

t_set.(t_current) = t_set_current_value;

end