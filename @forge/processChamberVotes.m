function [chamber_matrix,chamber_votes,chamber_sponsor_matrix,chamber_sponsor_votes,committee_matrix,committee_votes,committee_sponsor_matrix,committee_sponsor_votes,consistency_matrix,bill_ids,republicans_chamber_votes,democrats_chamber_votes,republicans_chamber_sponsor,democrats_chamber_sponsor,republicans_committee_votes,democrats_committee_votes,democrats_committee_sponsor,republicans_committee_sponsor,seat_matrix] = processChamberVotes(obj,people,chamber)
% PROCESSCHAMBERVOTES
% Take in the people matrix and the chamber infomraiton to
% generate the specific information about the chamber

% This allows it to be abstractable to both chambers
chamber_data = sprintf('%s_data',chamber);

% create the id strings
ids = util.createIDstrings(people{:,'sponsor_id'});

% Initialize the people_matrix and possible_votes matrix
[chamber_matrix, chamber_votes]                     = util.createTable(unique(ids),unique(ids),'NaN');
[committee_matrix, committee_votes]                 = util.createTable(unique(ids),unique(ids),'NaN');
[chamber_sponsor_matrix, chamber_sponsor_votes]     = util.createTable(unique(ids),unique(ids),'NaN');
[committee_sponsor_matrix, committee_sponsor_votes] = util.createTable(unique(ids),unique(ids),'NaN');

% Create a table to keep track of the unique sponsorships
sponsorship_counts = util.createTable(unique(ids),{'count'},'zero');

% Create a table to keep track of the unique sponsorships
consistency_matrix = util.createTable(unique(ids),{'consistency' 'opportunity'},'zero');

% Set up the basic information to iterate over
bill_keys       = cell2mat(obj.bill_set.keys);
bill_ids        = zeros(1,length(bill_keys));
bill_count      = 0;

% Now we're going to iterate over all the bills
delete_str = '';
for i = bill_keys
    
    % Screen updates
    print_str = sprintf('%i',i);
    fprintf([delete_str,print_str]);
    delete_str = repmat(sprintf('\b'),1,length(print_str));
    
    % LIMITING CONDITIONS
    % yes percentage less than 85%
    % full chamber
    if obj.bill_set(i).(sprintf('passed_%s',chamber)) >= 0 && obj.bill_set(i).(chamber_data).competitive
        %final_yes_percentage < obj.competitive_threshold && ... % yes vote is under the threshold
        %   obj.bill_set(i).(chamber_data).final_yes_percentage > (1 - obj.competitive_threshold)  % no vote is under the threshold
       
        % Sponsor information
        sponsor_ids = util.createIDstrings(obj.bill_set(i).sponsors,ids);
        
        % Increase the sponsorship count by one
        sponsorship_counts{util.CStrAinBP(sponsorship_counts.Properties.RowNames,sponsor_ids),'count'} = sponsorship_counts{util.CStrAinBP(sponsorship_counts.Properties.RowNames,sponsor_ids),'count'} + 1;
        
        %%% COMMITTEE INFORMATION - TODO probably can collapse this into a common function with the chamber data
        %         is_committee_votes = 0; %TEST
        %
        %         for j = 1:length(obj.bill_set(i).(chamber_data).committee_votes)
        %
        %             % so it's sort of pointless to do the loop and then
        %             % only process the last bill but I want to preserve
        %             % the functionality
        %             if j < length(obj.bill_set(i).(chamber_data).committee_votes)
        %                 continue
        %             end
        %
        %             committee_count = committee_count + 1;
        %
        %             % Yes/No votes
        %             committee_yes_ids = util.createIDstrings(obj.bill_set(i).(chamber_data).committee_votes(j).yes_list,ids);
        %             committee_no_ids  = util.createIDstrings(obj.bill_set(i).(chamber_data).committee_votes(j).no_list,ids);
        %
        %             % STRAIGHT VOTES
        %             committee_matrix = obj.addVotes(committee_matrix,committee_yes_ids,committee_yes_ids);
        %             committee_matrix = obj.addVotes(committee_matrix,committee_no_ids,committee_no_ids);
        %             committee_matrix = obj.addVotes(committee_matrix,committee_yes_ids,committee_no_ids,'value',0);
        %             committee_matrix = obj.addVotes(committee_matrix,committee_no_ids,committee_yes_ids,'value',0);
        %
        %             % Place that information into possible votes matrix
        %             committee_votes = obj.addVotes(committee_votes,[committee_yes_ids ; committee_no_ids],[committee_yes_ids ; committee_no_ids]);
        %
        %             print_str = sprintf('%i %i',i,j);
        %             fprintf([delete_str,print_str]);
        %             delete_str = repmat(sprintf('\b'),1,length(print_str));
        %
        %             is_committee_votes = 1;
        %         end
        %
        %         if is_committee_votes % could also do a ~isempty(j)
        %             % SPONSORS - take the last *committee* vote - TODO is this really what we want to do here?
        %             committee_sponsor_matrix = obj.addVotes(committee_sponsor_matrix,sponsor_ids,committee_yes_ids);
        %             committee_sponsor_matrix = obj.addVotes(committee_sponsor_matrix,sponsor_ids,committee_no_ids,'value',0);
        %
        %             % Place that information into possible votes matrix
        %             committee_sponsor_votes  = obj.addVotes(committee_sponsor_votes,sponsor_ids,[committee_yes_ids ; committee_no_ids]);
        %         end
        committee_votes          = [];
        committee_matrix         = [];
        committee_sponsor_matrix = [];
        committee_sponsor_votes  = [];
        
        is_committee_votes = 1; %TEST
        
        %%% CHAMBER INFORMATION
        is_chamber_votes = 0;
        for j = 1:length(obj.bill_set(i).(chamber_data).chamber_votes)
            % so it's sort of pointless to do the loop and then
            % only process the last bill but I want to preserve
            % the functionality
            if isempty(regexp(upper(obj.bill_set(i).(chamber_data).chamber_votes(j).description{:}),'(THIRD|3RD|ON PASSAGE)','once'))
                continue
            end
            
            % Yes/No votes
            yes_ids = util.createIDstrings(obj.bill_set(i).(chamber_data).chamber_votes(j).yes_list,ids);
            no_ids  = util.createIDstrings(obj.bill_set(i).(chamber_data).chamber_votes(j).no_list,ids);
            
            % STRAIGHT VOTES
            chamber_matrix = obj.addVotes(chamber_matrix,yes_ids,yes_ids);
            chamber_matrix = obj.addVotes(chamber_matrix,no_ids,no_ids);
            chamber_matrix = obj.addVotes(chamber_matrix,yes_ids,no_ids,'value',0);
            chamber_matrix = obj.addVotes(chamber_matrix,no_ids,yes_ids,'value',0);
            
            % Place that information into possible votes matrix
            chamber_votes = obj.addVotes(chamber_votes,[yes_ids ; no_ids],[yes_ids ; no_ids]);
            
            print_str = sprintf('%i %i',i,j);
            fprintf([delete_str,print_str]);
            delete_str = repmat(sprintf('\b'),1,length(print_str));
            
            is_chamber_votes = 1;
        end
        
        if is_chamber_votes % could also do a ~isempty(j)
            % SPONSORS - take the last chamber vote - TODO is this really what we want to do here?
            chamber_sponsor_matrix = obj.addVotes(chamber_sponsor_matrix,sponsor_ids,yes_ids);
            chamber_sponsor_matrix = obj.addVotes(chamber_sponsor_matrix,sponsor_ids,no_ids,'value',0);
            
            % Place that information into possible votes matrix
            chamber_sponsor_votes  = obj.addVotes(chamber_sponsor_votes,sponsor_ids,[yes_ids ; no_ids]);
        end
        
        if is_chamber_votes && is_committee_votes
            % Generate the consistency information
%             joined_set = [committee_yes_ids;committee_no_ids];
%             joined_set = joined_set(ismember(joined_set,[yes_ids;no_ids]));
%             
%             consistency_matrix{joined_set,'opportunity'} = consistency_matrix{joined_set,'opportunity'} + 1;
%             
%             matched_set = [committee_yes_ids(ismember(committee_yes_ids,yes_ids)) ; committee_no_ids(ismember(committee_no_ids,no_ids))];
%             consistency_matrix{matched_set,'consistency'} = consistency_matrix{matched_set,'consistency'} + 1;
            
            bill_count = bill_count + 1;
            bill_ids(bill_count) = i;
        end
    end
end
bill_ids(bill_count+1:end) = [];

% Print out information
print_str = sprintf('Chamber Vote Processing Complete! %i bills\n',length(bill_keys));
fprintf([delete_str,print_str]);
fprintf('Complete Bill Count: %i\n',bill_count)

% Clean the votes of non-sufficient legislators
[chamber_matrix, chamber_votes]                     = obj.cleanVotes(chamber_matrix, chamber_votes);
[chamber_sponsor_matrix, chamber_sponsor_votes]     = obj.cleanSponsorVotes(chamber_sponsor_matrix,chamber_sponsor_votes,sponsorship_counts);
[committee_matrix, committee_votes]                 = obj.cleanVotes(committee_matrix, committee_votes);
[committee_sponsor_matrix, committee_sponsor_votes] = obj.cleanSponsorVotes(committee_sponsor_matrix,committee_sponsor_votes,sponsorship_counts);

% Normalize all of the legislator votes
[chamber_matrix]           = obj.normalizeVotes(chamber_matrix, chamber_votes);
[chamber_sponsor_matrix]   = obj.normalizeVotes(chamber_sponsor_matrix, chamber_sponsor_votes);
[committee_matrix]         = obj.normalizeVotes(committee_matrix,committee_votes);
[committee_sponsor_matrix] = obj.normalizeVotes(committee_sponsor_matrix,committee_sponsor_votes);

% Add the consistency for each legislator
consistency_matrix.percentage = consistency_matrix.consistency ./ consistency_matrix.opportunity;

% Create Republican and Democrat Lists (makes accounting easier)
[republican_ids, democrat_ids] = obj.processParties(people);

% Process party chamber and committee votes
republicans_chamber_votes     = chamber_matrix(util.CStrAinBP(chamber_matrix.Properties.RowNames,republican_ids),util.CStrAinBP(chamber_matrix.Properties.VariableNames,republican_ids));
democrats_chamber_votes       = chamber_matrix(util.CStrAinBP(chamber_matrix.Properties.RowNames,democrat_ids),util.CStrAinBP(chamber_matrix.Properties.VariableNames,democrat_ids));

if ~isempty(committee_matrix)
    republicans_committee_votes   = committee_matrix(util.CStrAinBP(committee_matrix.Properties.RowNames,republican_ids),util.CStrAinBP(committee_matrix.Properties.VariableNames,republican_ids));
    democrats_committee_votes     = committee_matrix(util.CStrAinBP(committee_matrix.Properties.RowNames,democrat_ids),util.CStrAinBP(committee_matrix.Properties.VariableNames,democrat_ids));
else
    republicans_committee_votes = [];
    democrats_committee_votes   = [];
end

% Process party chamber and committee sponsor votes
republicans_chamber_sponsor   = chamber_sponsor_matrix(util.CStrAinBP(chamber_sponsor_matrix.Properties.RowNames,republican_ids),util.CStrAinBP(chamber_sponsor_matrix.Properties.VariableNames,republican_ids));
democrats_chamber_sponsor     = chamber_sponsor_matrix(util.CStrAinBP(chamber_sponsor_matrix.Properties.RowNames,democrat_ids),util.CStrAinBP(chamber_sponsor_matrix.Properties.VariableNames,democrat_ids));

if ~isempty(committee_sponsor_matrix)
    republicans_committee_sponsor = committee_sponsor_matrix(util.CStrAinBP(committee_sponsor_matrix.Properties.RowNames,republican_ids),util.CStrAinBP(committee_sponsor_matrix.Properties.VariableNames,republican_ids));
    democrats_committee_sponsor   = committee_sponsor_matrix(util.CStrAinBP(committee_sponsor_matrix.Properties.RowNames,democrat_ids),util.CStrAinBP(committee_sponsor_matrix.Properties.VariableNames,democrat_ids));
else
    republicans_committee_sponsor = [];
    democrats_committee_sponsor   = [];
end
% if seat information exists generate the seat proximity matrix
seat_matrix = [];
if length(util.CStrAinBP({'SEATROW','SEATCOLUMN'},people.Properties.VariableNames)) == 2
    seat_matrix = obj.processSeatProximity(people);
end

end