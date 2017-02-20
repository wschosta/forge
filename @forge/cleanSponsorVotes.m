function [people_matrix,possible_votes] = cleanSponsorVotes(obj,people_matrix,possible_votes,sponsorship_counts)
% CLEANSPONSORVOTES
% Clean out the sponsorship votes for the legislators that don't meet the
% basic qualifications

if ~isempty(people_matrix) && ~isempty(possible_votes)
    
    % Clean the people matrix
    [people_matrix,possible_votes] = obj.cleanVotes(people_matrix,possible_votes);
    
    % FInd the sponsor filter level, half a standard deviation below the mean
    obj.sponsor_filter = mean(sponsorship_counts.count) - std(sponsorship_counts.count)/2;
    
    % Generate the list of column names
    row_names = people_matrix.Properties.RowNames;
    
    % Iterate over the column names
    for i = 1:length(row_names)
        
        % If the value for sponsorship is less than the filter
        if sponsorship_counts{row_names{i},'count'} < obj.sponsor_filter
            people_matrix.(row_names{i})  = []; % Clear the people matrix
            possible_votes.(row_names{i}) = []; % Clear the possible vote matrix
            
            if obj.show_warnings
                fprintf('WARNING: %s did not meet the vote threshold with only %i\n',row_names{i},sponsorship_counts{i,'count'});
            end
        end
    end
    
elseif obj.show_warnings
    fprintf('WARNING: empty sponsor matrix!\n')
end

end