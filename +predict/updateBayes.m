function [t_set,t_count,t_current] = updateBayes(revealed_id,revealed_preference,t_set,chamber_specifics,t_count,ids)

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
        
%         if revealed_preference(k) == 1
%             if chamber_specifics(j,matched_ids(k)) == 1 || chamber_specifics(j,matched_ids(k)) == 0
%                 specific_impact = 0.999; % voted yes, high consistency
%             elseif chamber_specifics(j,k) == 0
%                 specific_impact = 0.001; % voted yes, low consistency
%             else
%                 specific_impact = chamber_specifics(j,matched_ids(k));
%             end
%         elseif revealed_preference(k) == 0
%             if chamber_specifics(j,matched_ids(k)) == 0
%                 specific_impact = 0.999; % voted no, low consistency
%             elseif chamber_specifics(j,matched_ids(k)) == 1
%                 specific_impact = 0.001; % voted no, high consistency
%             else
%                 specific_impact = 1 - chamber_specifics(j,matched_ids(k));
%             end
%         else
%             error('Functionality for non-binary revealed preferences not currently supported')
%         end
        
        combined_impact = combined_impact*specific_impact;
    end
    t_set_current_value(j) = (combined_impact*t_set_previous_value(j))/(1 + 2*combined_impact*t_set_previous_value(j) - combined_impact - t_set_previous_value(j));
    % the denominator above is functionally the same as: (combined_impact*t_set{j,t_previous} + (1-combined_impact)*(1-t_set{j,t_previous})
    % In the active form it reduces the number of references to the table
    % which *should* be faster
end

for j = 1:length(matched_ids)
    t_set_current_value(matched_ids(j)) = abs(revealed_preference(j) - 0.001);
    
%     switch revealed_preference(j)
%         case 0
%             t_set_current_value(matched_ids(j)) = 0.001;
%         case 1
%             t_set_current_value(matched_ids(j)) = 0.999;
%         otherwise
%             error('Functionality for non-binary revealed preferences not currently supported')
%     end
end

t_set.(t_current) = t_set_current_value;

end