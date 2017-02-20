function vote_structure = addRollcallVotes(obj,new_rollcall,new_votelist)
% ADDROLLCALLVOTES
% Add the rollcall information into the vote structure. This allows for
% easier processing of the data

vote_structure.rollcall_id  = new_rollcall.roll_call_id;
vote_structure.description  = new_rollcall.description;
vote_structure.date         = new_rollcall.date;
vote_structure.yea          = new_rollcall.yea;
vote_structure.nay          = new_rollcall.nay;
vote_structure.nv           = new_rollcall.nv;
vote_structure.total_vote   = new_rollcall.total_vote;
vote_structure.yes_percent  = new_rollcall.yes_percent;
vote_structure.yes_list     = new_votelist{new_votelist.vote == obj.VOTE_KEY('yea'),'sponsor_id'};
vote_structure.no_list      = new_votelist{new_votelist.vote == obj.VOTE_KEY('nay'),'sponsor_id'};
vote_structure.abstain_list = new_votelist{new_votelist.vote == obj.VOTE_KEY('absent'),'sponsor_id'};

end