function chamber_data = processChamberRollcalls(obj,rollcalls,votes_create,committee_size)
% PROCESSCHAMBERDATA
% Read in the chamber vote data for a specific vote

% Initialize the chamber matrix
chamber_data = {};

% Initialize the committee votes based o nthe template
committee_votes = util.templates.getVoteTemplate();

% Set the final size of the committee vote array
if sum(rollcalls.total_vote < committee_size) > 0
    committee_votes(sum(rollcalls.total_vote < committee_size)).rollcall_id = 1;
end

% Set the final size of the chamber vote array
chamber_votes = util.templates.getVoteTemplate();
if sum(rollcalls.total_vote >= committee_size)
    chamber_votes(sum(rollcalls.total_vote >= committee_size)).rollcall_id = 1;
end

% TODO: set the committee ID -  chammber_data.committee_id 

% Initialize the vote count
committee_vote_count = 0;
chamber_vote_count   = 0;

% Iterate over all the rollcalls
for j = 1:size(rollcalls,1)
    % Pull out the votes for that rollcall
    specific_votes = votes_create(votes_create.roll_call_id == rollcalls{j,'roll_call_id'},:);
    
    if rollcalls{j,'total_vote'} < committee_size % committee
        % iterate the committee vote count
        committee_vote_count                  = committee_vote_count + 1;
        
        % input the committee vote into the structure
        committee_votes(committee_vote_count) = obj.addRollcallVotes(rollcalls(j,:),specific_votes);
    else % full chamber
        % iterate the chamber vote count
        chamber_vote_count                = chamber_vote_count + 1;
        
        % input the chamber vote into the structure
        chamber_votes(chamber_vote_count) = obj.addRollcallVotes(rollcalls(j,:),specific_votes);
    end
end

% Put everything into the chamber data structure
chamber_data(end+1).committee_votes = committee_votes;
chamber_data.chamber_votes = chamber_votes;
chamber_data.final_yes_percentage = -1;

% If there actually were votes, put together the final information about
% the bill
if ~isempty(chamber_votes)
    chamber_data.final_yea            = chamber_votes(end).yea;
    chamber_data.final_nay            = chamber_votes(end).nay;
    chamber_data.final_nv             = chamber_votes(end).nv;
    chamber_data.final_total_vote     = chamber_votes(end).total_vote;
    chamber_data.final_yes_percentage = chamber_votes(end).yes_percent;
end

end