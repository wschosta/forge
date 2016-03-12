classdef forge_reorg < handle
    properties
        vote_template = struct(...
            'rollcall_id',{},...
            'description',{},...
            'yes',{},...
            'no',{},...
            'abstain',{},...
            'total_votes',{},...
            'yes_percentage',{},...
            'yes_list',{},...
            'no_list',{},...
            'abstain_list',{});
        chamber_template = struct(...
            'committee_id',{},... % make sure multiple comittees are possible
            'committee_votes',{},...
            'chamber_votes',{},...
            'passed',{},...
            'final_yes',{},...
            'final_no',{},...
            'final_abstain',{},...
            'final_yes_percentage',{});
        % final committe and final chamber vote
        bill_template = struct(...
            'bill_id',{},...
            'bill_number',{},...
            'description',{},...
            'issue_category',{},...
            'sponsors',{},... % first vs co, also authors 
            'date_introduced',{},...
            'date_of_last_vote',{},...
            'house_data',{},...
            'passed_house',{},...
            'senate_data',{},...
            'passed_senate',{},...
            'passed_both',{},...
            'signed_into_law',{});
        % originated in house/senate?
        
        people
        bills
        rollcalls
        sponsors
        votes
        
        party_key = containers.Map([0,1],{'Democrat','Republican'})
        vote_key = containers.Map([1,2,3,4],{'yea','nay','absent','no vote'});
        issue_key % key for issue category
        chamber_leadership_key % key for leadership codes
        committee_key
        committee_leadership_key % key for committee leadership
    end
    
    methods
        function obj = forge_reorg()
            
        end
        
        function run(obj)
            
            
            % The goal is to create a container map, keyed by bill id
            bills = containers.Map('KeyType','int32','ValueType','struct');
            
            % each entry will be a structure that contains the important
            % information about the bill and its passage through both the
            % senate and the house
                % this might be an opportunity to bring in the as-yet
                % unused "history" sheet - from which it should be possible
                % to mine primary vs secondary sponsors
            
            % build in a key for each coded variable on both a bill and
            % person basis: {bill : issue, committee of origin } {person :
            % party, chamber leadership, committee leadership}
            
            % the result will be a system in which the bills are stored in
            % a struct that can be drilled to get specific information and
            % people will continue to be stored in a table
            
            % district information, which will be included soon, will also
            % be stored in table format
            
            % makes sense for the relational things (seat proximity, vote
            % similarity, sponsorship) to be stored in a table as well -
            % they can be referenced directly by the legislator ID
            
            % ID should probably be stored as a string throughout, that way
            % it can be used in variable names more easily
        end
        
        
       

    end
    
    methods (Static)
        function do_something()
           fprintf('something\n') 
        end
    end
end