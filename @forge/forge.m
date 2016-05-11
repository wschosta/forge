classdef forge < handle
    properties
        people
        bills
        history
        rollcalls
        sponsors
        votes
        
        bill_set
        
        chamber_leadership_key % key for leadership codes
        committee_key
        committee_leadership_key % key for committee leadership
        
        sponsor_filter
        
        state
        data_directory
        
        make_gifs
        make_histograms
        
        gif_directory
        histogram_directory
        outputs_directory
        
        senate_size
        house_size
        
        learning_algorithm_data
        
        generate_outputs
        recompute
        reprocess
    end
    
    properties (Constant)
        PARTY_KEY = containers.Map({'0','1','Democrat','Republican'},{'Democrat','Republican',0,1})
        VOTE_KEY  = containers.Map({'1','2','3','4','yea','nay','absent','no vote'},{'yea','nay','absent','no vote',1,2,3,4});
        
        ISSUE_KEY = containers.Map([1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16],{...
            'Agriculture',...
            'Commerce, Business, Economic Development',...
            'Courts & Judicial',...
            'Education',...
            'Elections & Apportionment',...
            'Employment & Labor',...
            'Environment & Natural Resources',...
            'Family, Children, Human Affairs & Public Health',...
            'Banks & Financial Institutions',...
            'Insurance',...
            'Government & Regulatory Reform',...
            'Local Government',...
            'Roads & Transportation',...
            'Utilities, Energy & Telecommunications',...
            'Ways & Means, Appropriations',...
            'Other'});
    end
    
    methods
        %TODO LIST:
        % - fix dates, Legiscan switches between M/D/YYYY and YYYY-MM-DD.
        %   We want the latter so we can easily sort by date
        % - differentiate between ammendment votes and third reading votes
        %       HALF DONE - accomplished by text searching for "THIRD
        %       READING" which works decently well
        % - generate committee membership lists
        %         function obj = forge(varargin)
        %             in = inputParser;
        %             addOptional(in,'recompute',0,@islogical);
        %             addOptional(in,'reprocess',0,@islogical);
        %             addOptional(in,'state','IN',@(x) ischar(x) && length(x) == 2);
        %             addOptional(in,'generateOutputs',0,@islogical);
        %             parse(in,varargin{:});
        %
        %             obj.recompute = in.Results.recompute;
        %             obj.reprocess = in.Results.reprocess;
        %             obj.state     = in.Results.state;
        %             obj.generate_outputs = in.Results.generateOutputs;
        %
        %             obj.data_directory = 'data';
        %
        %             obj.outputs_directory = sprintf('%s/%s/outputs',obj.data_directory,obj.state);
        %             obj.gif_directory = sprintf('%s/gif',obj.outputs_directory);
        %             obj.histogram_directory = sprintf('%s/histograms',obj.outputs_directory);
        %
        %             obj.learning_algorithm_data = la.loadLearnedMaterials();
        %             switch obj.state
        %                 case 'IN'
        %                     obj.senate_size = 50;
        %                     obj.house_size = 100;
        %                 case 'OH'
        %                     obj.senate_size = 33;
        %                     obj.house_size = 99;
        %                 otherwise
        %                     obj.senate_size = 50;
        %                     obj.house_size = 100;
        %             end
        %         end
        
        function init(obj)
            if obj.reprocess || exist(sprintf('%s_processed_data.mat',obj.state),'file') ~= 2
                
                bills_create     = obj.readAllFilesOfSubject('bills');
                people_create    = obj.readAllFilesOfSubject('people');
                rollcalls_create = obj.readAllFilesOfSubject('rollcalls');
                
                rollcalls_create.senate      = strncmpi(rollcalls_create{:,'description'},{'S'},1);
                rollcalls_create.total_vote  = rollcalls_create.yea + rollcalls_create.nay;
                rollcalls_create.yes_percent = rollcalls_create.yea ./ rollcalls_create.total_vote;
                
                sponsors_create = obj.readAllFilesOfSubject('sponsors');
                votes_create    = obj.readAllFilesOfSubject('votes');
                history_create  = obj.readAllFilesOfSubject('history');
                
                bill_set_create = containers.Map('KeyType','int32','ValueType','any');
                
                complete_check = table(bills_create.bill_id,zeros(length(bills_create.bill_id),1),zeros(length(bills_create.bill_id),1),'VariableNames',{'bill_id','complete','semi'});
                
                for i = 1:length(bills_create.bill_id)
                    
                    template = obj.getBillTemplate();
                    
                    complete = 1;
                    
                    template(end+1).bill_id = bills_create{i,'bill_id'}; %#ok<AGROW>
                    template.bill_number = bills_create{i,'bill_number'};
                    template.title = bills_create{i,'title'};
                    template.issue_category = la.classifyBill(template.title,obj.learning_algorithm_data);
                    
                    template.sponsors = sponsors_create{sponsors_create.bill_id == bills_create{i,'bill_id'},'sponsor_id'};
                    
                    template.history = sortrows(history_create(bills_create{i,'bill_id'} == history_create.bill_id,:),'date');
                    if ~isempty(template.history)
                        template.date_introduced  = template.history{1,'date'};
                        template.date_last_action = template.history{end,'date'};
                    else
                        complete = 0;
                    end
                    
                    bill_rollcalls = sortrows(rollcalls_create(rollcalls_create.bill_id == bills_create{i,'bill_id'},:),'date');
                    
                    % ------------------ House Data --------------------- %
                    house_rollcalls = bill_rollcalls(bill_rollcalls.senate == 0,:);
                    
                    if ~isempty(house_rollcalls)
                        
                        house_data = obj.processChamberRollcalls(house_rollcalls,votes_create,obj.house_size*0.75);
                        
                        template.house_data = house_data;
                        template.passed_house = (house_data.final_yes_percentage > 0.5);
                    else
                        template.passed_house = -1;
                        complete = 0;
                    end
                    
                    % ------------------ Senate Data -------------------- %
                    senate_rollcalls = bill_rollcalls(bill_rollcalls.senate == 1,:);
                    
                    if ~isempty(senate_rollcalls)
                        
                        senate_data = obj.processChamberRollcalls(senate_rollcalls,votes_create,obj.senate_size*0.75);
                        
                        template.senate_data = senate_data;
                        template.passed_senate = (senate_data.final_yes_percentage > 0.5);
                    else
                        template.passed_senate = -1;
                        complete = 0;
                    end
                    
                    if (template.passed_senate ~= -1) && (template.passed_house ~= -1)
                        template.passed_both = (template.passed_senate && template.passed_house);
                    else
                        template.passed_both = -1;
                    end
                    % signed into law?
                    
                    template.complete = complete;
                    complete_check{complete_check.bill_id == template.bill_id,'complete'} = complete;
                    bill_set_create(bills_create{i,'bill_id'}) = template;
                end
                
                clear complete chamber_votes committee_votes bill_history bill_rollcalls i j house_data house_rollcalls senate_data senate_rollcalls template
                
                var_list = who;
                var_list = var_list(~ismember(var_list,'obj'));
                save(sprintf('%s_processed_data',obj.state),var_list{:})
            else
                load(sprintf('%s_processed_data',obj.state)) %
            end
            
            obj.bills     = bills_create;
            obj.history   = history_create;
            obj.people    = people_create;
            obj.rollcalls = rollcalls_create;
            obj.sponsors  = sponsors_create;
            obj.votes     = votes_create;
            
            obj.bill_set = bill_set_create;
        end
       
        % There is probably a better, abstractable way to do this but it's a
        % good rough cut way. There may not actually be a better way to do
        % this in MATLAB...
        function [house_chamber_matrix,house_chamber_votes,...
                house_sponsor_chamber_matrix,house_sponsor_chamber_votes,...
                house_committee_matrix,house_committee_votes,...
                house_sponsor_committee_matrix,house_sponsor_committee_votes,...
                house_consistency_matrix,bill_ids] = processHouseVotes(obj,house_people)
            
            ids = util.createIDstrings(house_people{:,'sponsor_id'});
            
            % Initialize the people_matrix and possible_votes matrix
            house_chamber_matrix = util.createTable(unique(ids),unique(ids),'NaN');
            house_chamber_votes  = util.createTable(unique(ids),unique(ids),'NaN');
            
            house_committee_matrix = util.createTable(unique(ids),unique(ids),'NaN');
            house_committee_votes  = util.createTable(unique(ids),unique(ids),'NaN');
            
            house_sponsor_chamber_matrix = util.createTable(unique(ids),unique(ids),'NaN');
            house_sponsor_chamber_votes  = util.createTable(unique(ids),unique(ids),'NaN');
            
            house_sponsor_committee_matrix = util.createTable(unique(ids),unique(ids),'NaN');
            house_sponsor_committee_votes  = util.createTable(unique(ids),unique(ids),'NaN');
            
            % Create a table to keep track of the unique sponsorships
            sponsorship_counts = util.createTable(unique(ids),{'count'},'zero');
            
            % Create a table to keep track of the unique sponsorships
            house_consistency_matrix = util.createTable(unique(ids),{'consistency' 'opportunity'},'zero');
            
            bill_ids = [];
            
            bill_keys = cell2mat(obj.bill_set.keys);
            bill_count = 0;
            committee_count = 0;
            % Now we're going to iterate over all the bills
            delete_str = '';
            for i = bill_keys
                
                % Screen updates
                print_str = sprintf('%i',i);
                fprintf([delete_str,print_str]);
                delete_str = repmat(sprintf('\b'),1,length(print_str));
                
                % LIMITING CONDITIONS
                % yes percentage less than 85%
                % full chamber (greater than 60 votes)
                agreement_threshold = 0.85;
                if obj.bill_set(i).passed_house >= 0 && obj.bill_set(i).house_data.final_yes_percentage < agreement_threshold && obj.bill_set(i).house_data.final_yes_percentage >= 0
                    
                    % Sponsor information
                    sponsor_ids = util.createIDstrings(obj.bill_set(i).sponsors);
                    sponsor_ids = sponsor_ids(ismember(sponsor_ids,ids));
                    
                    % Increase the sponsorship count by one
                    sponsorship_counts{ismember(sponsorship_counts.Properties.RowNames,sponsor_ids),'count'} = sponsorship_counts{ismember(sponsorship_counts.Properties.RowNames,sponsor_ids),'count'} + 1;
                    
                    %%% COMMITTEE INFORMATION - TODO probably can collapse this into a common function with the chamber data
                    committee_votes = 0;
                    for j = 1:length(obj.bill_set(i).house_data.committee_votes)
                        
                        % so it's sort of pointless to do the loop and then
                        % only process the last bill but I want to preserve
                        % the functionality
                        if j < length(obj.bill_set(i).house_data.committee_votes)
                            continue
                        end
                        
                        committee_count = committee_count + 1;
                        
                        % Yes/No votes
                        committee_yes_ids = util.createIDstrings(obj.bill_set(i).house_data.committee_votes(j).yes_list);
                        committee_yes_ids = committee_yes_ids(ismember(committee_yes_ids,ids));
                        
                        committee_no_ids = util.createIDstrings(obj.bill_set(i).house_data.committee_votes(j).no_list);
                        committee_no_ids = committee_no_ids(ismember(committee_no_ids,ids));
                        
                        % STRAIGHT VOTES
                        house_committee_matrix = obj.addVotes(house_committee_matrix,committee_yes_ids,committee_yes_ids);
                        house_committee_matrix = obj.addVotes(house_committee_matrix,committee_no_ids,committee_no_ids);
                        house_committee_matrix = obj.addVotes(house_committee_matrix,committee_yes_ids,committee_no_ids,'value',0);
                        house_committee_matrix = obj.addVotes(house_committee_matrix,committee_no_ids,committee_yes_ids,'value',0);
                        
                        % Place that information into possible votes matrix
                        house_committee_votes = obj.addVotes(house_committee_votes,[committee_yes_ids ; committee_no_ids],[committee_yes_ids ; committee_no_ids]);
                        
                        print_str = sprintf('%i %i',i,j);
                        fprintf([delete_str,print_str]);
                        delete_str = repmat(sprintf('\b'),1,length(print_str));
                        
                        committee_votes = 1;
                    end
                    
                    if committee_votes % could also do a ~isempty(j)
                        % SPONSORS - take the last *committee* vote - TODO is this really what we want to do here?
                        house_sponsor_committee_matrix = obj.addVotes(house_sponsor_committee_matrix,sponsor_ids,yes_ids);
                        house_sponsor_committee_matrix = obj.addVotes(house_sponsor_committee_matrix,sponsor_ids,no_ids,'value',0);
                        
                        % Place that information into possible votes matrix
                        house_sponsor_committee_votes = obj.addVotes(house_sponsor_committee_votes,sponsor_ids,[yes_ids ; no_ids]);
                    end
                    
                    %%% CHAMBER INFORMATION
                    chamber_votes = 0;
                    for j = 1:length(obj.bill_set(i).house_data.chamber_votes)
                        % so it's sort of pointless to do the loop and then
                        % only process the last bill but I want to preserve
                        % the functionality
                        if isempty(regexp(upper(obj.bill_set(i).house_data.chamber_votes(j).description{:}),'THIRD','once'))
                            continue
                        end
                        
                        % Yes/No votes
                        yes_ids = util.createIDstrings(obj.bill_set(i).house_data.chamber_votes(j).yes_list);
                        yes_ids = yes_ids(ismember(yes_ids,ids));
                        
                        no_ids = util.createIDstrings(obj.bill_set(i).house_data.chamber_votes(j).no_list);
                        no_ids = no_ids(ismember(no_ids,ids));
                        
                        % STRAIGHT VOTES
                        house_chamber_matrix = obj.addVotes(house_chamber_matrix,yes_ids,yes_ids);
                        house_chamber_matrix = obj.addVotes(house_chamber_matrix,no_ids,no_ids);
                        house_chamber_matrix = obj.addVotes(house_chamber_matrix,yes_ids,no_ids,'value',0);
                        house_chamber_matrix = obj.addVotes(house_chamber_matrix,no_ids,yes_ids,'value',0);
                        
                        % Place that information into possible votes matrix
                        house_chamber_votes = obj.addVotes(house_chamber_votes,[yes_ids ; no_ids],[yes_ids ; no_ids]);
                        
                        print_str = sprintf('%i %i',i,j);
                        fprintf([delete_str,print_str]);
                        delete_str = repmat(sprintf('\b'),1,length(print_str));
                        
                        chamber_votes = 1;
                    end
                    
                    if chamber_votes % could also do a ~isempty(j)
                        % SPONSORS - take the last chamber vote - TODO is this really what we want to do here?
                        house_sponsor_chamber_matrix = obj.addVotes(house_sponsor_chamber_matrix,sponsor_ids,yes_ids);
                        house_sponsor_chamber_matrix = obj.addVotes(house_sponsor_chamber_matrix,sponsor_ids,no_ids,'value',0);
                        
                        % Place that information into possible votes matrix
                        house_sponsor_chamber_votes = obj.addVotes(house_sponsor_chamber_votes,sponsor_ids,[yes_ids ; no_ids]);
                    end
                    
                    if chamber_votes && committee_votes
                        % Generate the consistency information
                        joined_set = [committee_yes_ids;committee_no_ids];
                        joined_set = joined_set(ismember(joined_set,[yes_ids;no_ids]));
                        
                        house_consistency_matrix{joined_set,'opportunity'} = house_consistency_matrix{joined_set,'opportunity'} + 1;
                        
                        matched_set = [committee_yes_ids(ismember(committee_yes_ids,yes_ids)) ; committee_no_ids(ismember(committee_no_ids,no_ids))];
                        house_consistency_matrix{matched_set,'consistency'} = house_consistency_matrix{matched_set,'consistency'} + 1;
                        
                        bill_count = bill_count + 1;
                        
                        bill_ids(end+1) = i; %#ok<AGROW>
                    end
                end
                
            end
            print_str = 'Done!\n';
            fprintf([delete_str,print_str]);
            
            fprintf('Committee Count: %i of %i\n',committee_count,bill_count)
            
            [house_chamber_matrix, house_chamber_votes]  = obj.cleanVotes(house_chamber_matrix, house_chamber_votes);
            [house_sponsor_chamber_matrix,house_sponsor_chamber_votes] = obj.cleanSponsorVotes(house_sponsor_chamber_matrix,house_sponsor_chamber_votes,sponsorship_counts);
            
            [house_committee_matrix, house_committee_votes]  = obj.cleanVotes(house_committee_matrix, house_committee_votes);
            [house_sponsor_committee_matrix,house_sponsor_committee_votes] = obj.cleanSponsorVotes(house_sponsor_committee_matrix,house_sponsor_committee_votes,sponsorship_counts);
        end
        
        function [accuracy, number_sponsors, number_committee] = predictOutcomes(obj,bill_id,house_people,house_sponsor_chamber_matrix,house_consistency_matrix,house_sponsor_committe_matrix,house_chamber_matrix)
            % at some point it would probably be a good idea to spin this
            % out into its own file structure, just like the learning
            % algorithm
            
            bill_information = obj.bill_set(bill_id);
            
            ids = util.createIDstrings(house_people{:,'sponsor_id'});
            sponsor_ids = util.createIDstrings(bill_information.sponsors);
            sponsor_ids = sponsor_ids(ismember(sponsor_ids,ids));
            number_sponsors  = size(sponsor_ids,1);
            
            % this is cheating, eventually we'll need the committee
            % membership but this is fine for now (taking the people that
            % vote and working back) since we have perfect information
            
            if isempty(bill_information.house_data.committee_votes) % no committee information available
                accuracy = NaN;
                return
            end
            committee_yes     = bill_information.house_data.committee_votes.yes_list;
            committee_no      = bill_information.house_data.committee_votes.no_list;
            committee_members = [committee_yes ; committee_no];
            committee_ids     = util.createIDstrings(committee_members);
            committee_ids_yes = util.createIDstrings(committee_yes);
            committee_ids_no  = util.createIDstrings(committee_no);
            committee_ids     = committee_ids(ismember(committee_ids,ids));
            committee_ids_yes = committee_ids_yes(ismember(committee_ids_yes,ids));
            committee_ids_no  = committee_ids_no(ismember(committee_ids_no,ids));
            number_committee = size(committee_ids,1);
            
            found_it = 0;
            for i = length(bill_information.house_data.chamber_votes):-1:1
                if ~isempty(regexp(upper(bill_information.house_data.chamber_votes(i).description{:}),'THIRD READING','once'))
                    bill_yes = bill_information.house_data.chamber_votes(i).yes_list;
                    bill_no = bill_information.house_data.chamber_votes(i).no_list;
                    found_it = 1;
                    break
                end
            end
            
            if ~found_it
                accuracy = NaN;
                return
            end
            
            bill_yes_ids = util.createIDstrings(bill_yes);
            bill_no_ids  = util.createIDstrings(bill_no);
            bill_yes_ids = bill_yes_ids(ismember(bill_yes_ids,ids));
            bill_no_ids  = bill_no_ids(ismember(bill_no_ids,ids));
            
            
            % initial assumption, eveyone is equally likely to vote yes as
            % to vote no. This is probably not true, I'll have to figure
            % out how to figure this out.
            
            % Hypothesis [1, -1] [yes, no]
            
            % so we make a table for the bayes, we'll keep track of effects
            % here and then update at each time t. New column for ever
            % large step, new time t for every update
            bayes = array2table(0.5*ones(length(ids),1),'VariableNames',{'p_yes'},'RowNames',ids);
            t_set = array2table(NaN(length(ids),1),'VariableNames',{'final'},'RowNames',ids);
            accuracy_table = array2table(NaN(1,6),'VariableNames',{'final','name','t1','committee_vote','committee_consistency','p_yes_rev_cs'},'RowNames',{'accuracy'});
            
            t_set.name = obj.getSponsorName(ids)';
            
            t_set.t1 = NaN(length(ids),1);
            t_set{bill_yes_ids,'final'} = 1;
            t_set{bill_no_ids,'final'}  = 0;
            
            bayes.sponsor_effect_committee_positive = NaN(length(ids),1);
            bayes.sponsor_effect_committee_negative = NaN(length(ids),1);
            
            expressed_preference = array2table(zeros(length(ids),2),'VariableNames',{'expressed','locked'},'RowNames',ids);
            
            % --------- COMMITTEE EFFECT ---------
            % Calculate sponsor effect
            for i = 1:length(committee_ids)
                sponsor_effect_positive = 1;
                sponsor_effect_negative = 1;
                if ~ismember(committee_ids{i},house_sponsor_committe_matrix.Properties.RowNames)
                    sponsor_effect_positive = -1;
                    sponsor_effect_negative = -1;
                else
                    for k = 1:length(sponsor_ids)
                        if ~ismember(sponsor_ids{k},house_sponsor_committe_matrix.Properties.VariableNames)
                            continue
                        end
                        
                        sponsor_specific_effect = obj.getSpecificImpact(1,house_sponsor_committe_matrix{committee_ids{i},sponsor_ids{k}});
                        
                        sponsor_effect_positive = sponsor_effect_positive*sponsor_specific_effect;
                        sponsor_effect_negative = sponsor_effect_negative*(1-sponsor_specific_effect);
                    end
                end
                bayes{committee_ids{i},'sponsor_effect_committee_positive'} = sponsor_effect_positive;
                bayes{committee_ids{i},'sponsor_effect_committee_negative'} = sponsor_effect_negative;
            end
            
            % Set t1
            for i = t_set.Properties.RowNames'
                if ~isnan(bayes{i,'sponsor_effect_committee_positive'})
                    switch bayes{i,'sponsor_effect_committee_positive'}
                        case -1
                            t_set{i,'t1'} = bayes{i,'p_yes'};
                        otherwise
                            t_set{i,'t1'} = bayes{i,'sponsor_effect_committee_positive'}*bayes{i,'p_yes'} / (bayes{i,'sponsor_effect_committee_positive'}*bayes{i,'p_yes'} + bayes{i,'sponsor_effect_committee_negative'}*(1-bayes{i,'p_yes'}));
                    end
                end
            end
            
            t_set.committee_vote = NaN(length(t_set.Properties.RowNames),1);
            t_set{committee_ids_yes,'committee_vote'} = 1;
            t_set{committee_ids_no,'committee_vote'} = 0;
            
            t_set.committee_consistency = NaN(length(t_set.Properties.RowNames),1);
            t_set{committee_ids_yes,'committee_consistency'} = house_consistency_matrix{committee_ids_yes,'percentage'};
            t_set{committee_ids_no,'committee_consistency'} = house_consistency_matrix{committee_ids_no,'percentage'};
            
            t_set.p_yes_rev_cs = NaN(length(t_set.Properties.RowNames),1); % probability of yes, revised, for the committee and sponsor
            
            for i = t_set.Properties.RowNames'
                if ~isnan(t_set{i,'committee_vote'})
                    t_set{i,'p_yes_rev_cs'} = obj.getSpecificImpact(t_set{i,'committee_vote'},t_set{i,'committee_consistency'});
                end
            end
            
            for i = sponsor_ids'
                if ismember(i,house_sponsor_chamber_matrix.Properties.RowNames) && ismember(i,house_sponsor_chamber_matrix.Properties.VariableNames)
                    t_set{i,'p_yes_rev_cs'} = obj.getSpecificImpact(1,house_sponsor_chamber_matrix{i,i});
                else
                    t_set{i,'p_yes_rev_cs'} = 0.5;
                end
            end
            expressed_preference{[sponsor_ids; committee_ids],'expressed'} = 1;
            
            % So now we only update based on expressed preference for t2
            % calculate t2
            t_set.t2 = NaN(length(ids),1);
            
            preference_unknown = expressed_preference(~expressed_preference.expressed,:).Properties.RowNames';
            preference_known   = expressed_preference(~~expressed_preference.expressed,:).Properties.RowNames'; % dumb but effective
            
            for i = preference_unknown
                combined_impact = [];
                for k = preference_known
                    
                    specific_impact = obj.getSpecificImpact(1,house_chamber_matrix{i,k});
                    
                    combined_impact = [combined_impact specific_impact]; %#ok<AGROW>
                end
                
                t_set{i,'t2'} = (prod(combined_impact)*bayes{i,'p_yes'})/(prod(combined_impact)*bayes{i,'p_yes'} + prod(1-combined_impact)*(1-bayes{i,'p_yes'}));
            end
            
            for i = preference_known
                t_set{i,'t2'} = t_set{i,'p_yes_rev_cs'};
            end
            
            t2_check = round(t_set.t2) == t_set.final;
            
            incorrect = sum(t2_check == false);
            are_nan   = sum(isnan(t_set{t2_check == false,'final'}));
            accuracy_table.t2 = 100*(1-(incorrect-are_nan)/(100-are_nan));
            
            % here is where the updating comes in, need to mock up some
            % data whereby people declare preferences. However, things are
            % pretty damn solid at this point
            
            % at this point, for t3, we do basically the same thing as t2
            % but we just update everything
            
            number_of_legislators = 8;
            
            legislator_list = [bill_yes_ids ; bill_no_ids];
            legislator_list = legislator_list(randperm(length(legislator_list)));
            
            legislator_list = obj.createIDcodes(legislator_list);
            
            legislator_id = NaN(number_of_legislators,1);
            direction = NaN(number_of_legislators,1);
            for i = 1:number_of_legislators % because we just want a limited number of revealed votes
                legislator_id(i) = legislator_list(i);
                direction(i) = any(legislator_id(i) == bill_yes);
            end
            revealed_preferences = table(legislator_id,direction);
            
            save_directory = sprintf('%s/%i',obj.outputs_directory,bill_id);
            
            [~,~,~] = mkdir(save_directory);
            
            if bill_id == any(bill_id == [590034 583138 587734 590009])
                predict.plotTSet(t_set(:,'t1'),'t1 - Predicting the Committee Vote')
                saveas(gcf,sprintf('%s/t1',save_directory),'png');
                
                predict.plotTSet(t_set(:,'t2'),'t2 - Predicting chamber vote with committee and sponsor vote')
                saveas(gcf,sprintf('%s/t2',save_directory),'png');
            end
            
            t_count = 2;
            for i = 1:size(revealed_preferences,1)
                
                revealed_id = sprintf('id%i',revealed_preferences{i,'legislator_id'});
                revealed_preference = revealed_preferences{i,'direction'};
                
                if ismember(revealed_id,house_chamber_matrix.Properties.RowNames)
                    
                    t_count           = t_count + 1;
                    t_current         = sprintf('t%i',t_count);
                    t_previous        = sprintf('t%i',t_count-1);
                    t_set.(t_current) = NaN(length(ids),1);
                    
                    expressed_preference{:,'expressed'}           = 0;
                    expressed_preference{revealed_id,'expressed'} = 1;
                    
                    preference_unknown = expressed_preference(~expressed_preference.expressed,:).Properties.RowNames';
                    preference_known   = expressed_preference(~~expressed_preference.expressed,:).Properties.RowNames'; % dumb but effective
                    
                    for j = preference_unknown
                        combined_impact = [];
                        for k = preference_known
                            
                            specific_impact = obj.getSpecificImpact(revealed_preference,house_chamber_matrix{j,k});
                            
                            combined_impact = [combined_impact specific_impact]; %#ok<AGROW>
                        end
                        
                        if isnan(specific_impact) || isnan(combined_impact)
                            t_set{j,t_current} = t_set{j,t_previous};
                        else
                            t_set{j,t_current} = (prod(combined_impact)*t_set{j,t_previous})/(prod(combined_impact)*t_set{j,t_previous} + prod(1-combined_impact)*(1-t_set{j,t_previous}));
                        end
                    end
                    
                    switch revealed_preference
                        case 0
                            t_set{k,t_current} = 0.01;
                            vote_direction = 'nay';
                        case 1
                            t_set{k,t_current} = 0.99;
                            vote_direction = 'yea';
                        otherwise
                            error('Functionality for non-binary revealed preferences not currently supported')
                    end
                    
                    t_check = round(t_set.(t_current)) == t_set.final;
                    
                    incorrect = sum(t_check == false);
                    are_nan = sum(isnan(t_set{t_check == false,'final'}));
                    
                    accuracy_table.(t_current) = 100*(1-(incorrect-are_nan)/(100-are_nan));
                    
                    if bill_id == any(bill_id == [590034 583138 587734 590009])
                        predict.plotTSet(t_set(:,t_current),sprintf('%s - %s, %s',t_current,obj.getSponsorName({revealed_id}),vote_direction));
                        saveas(gcf,sprintf('%s/%s',save_directory,t_current),'png');
                    end
                end
                
                t_set.(sprintf('%s_check',t_current)) = round(t_set.(t_current)) == t_set.final;
                
                incorrect = sum(t_set.(sprintf('%s_check',t_current)) == false);
                are_nan = sum(isnan(t_set{t_set.(sprintf('%s_check',t_current)) == false,'final'}));
                
                accuracy = 100*(1-(incorrect-are_nan)/(100-are_nan));
            end
            
            if bill_id == any(bill_id == [590034 583138 587734 590009])
                accuracy_table.(sprintf('%s_check',t_current)) = accuracy;
                t_set = [t_set ; accuracy_table];
                
                writetable(t_set,sprintf('%s/t_set_test.xlsx',save_directory),'WriteRowNames',true)
            end
        end
        
        function plotTSet(obj,t_set_values,title_text)
            
            label_text = t_set_values.Properties.RowNames(~isnan(t_set_values{:,:}));
            plot_values = ceil(t_set_values{:,:}(~isnan(t_set_values{:,:}))*5) - 1 + 0.05;
            
            label_text = obj.getSponsorName(label_text);
            
            [plot_values, index] = sort(plot_values);
            label_text = label_text(index);
            
            unique_values = unique(plot_values);
            
            height = [];
            for i = 1:length(unique_values)
                height = [height linspace(0.02,0.98,sum(plot_values == unique_values(i)))]; %#ok<AGROW>
            end
            
            figure('units','normalized','outerposition',[0 0 1 1])
            hold on;
            title(title_text)
            patch([0 1 1 0],[0 0 1 1],[256/256  51/256  51/256]) % No - Red
            patch([1 2 2 1],[0 0 1 1],[256/256 153/256  51/256])
            patch([2 3 3 2],[0 0 1 1],[256/256 256/256  51/256]) % Swing - Yellow
            patch([3 4 4 3],[0 0 1 1],[153/256 256/256  51/256])
            patch([4 5 5 4],[0 0 1 1],[ 51/256 256/256  51/256]) % Yes - Green
            alpha(0.4)
            text(plot_values,height,label_text)
            axis([0,5,0,1])
            ax = gca;
            set(ax,'XTick',[0.5 1.5 2.5 3.5 4.5]);
            set(ax,'XTickLabel',{'Strong No','Leaning No','Neutral','Leaning Yes','Strong Yes'});
            set(ax,'YTick',[]);
            hold off
            
        end
        
        % probably can be moved to a plotting file
        function generatePlots(obj,people_matrix,label_string,specific_label,x_specific,y_specific,z_specific,tag)
            
            if ~isempty(people_matrix)
                h = figure();
                hold on
                title(sprintf('%s %s',label_string,specific_label))
                xlabel(x_specific)
                ylabel(y_specific)
                zlabel(z_specific)
                axis square
                grid on
                surf(people_matrix{:,:})
                colorbar
                view(3)
                hold off
                saveas(h,sprintf('%s/%s_%s',obj.outputs_directory,label_string,tag),'png')
                
                view(2)
                saveas(h,sprintf('%s/%s_%s_flat',obj.outputs_directory,label_string,tag),'png')
                
                if obj.make_gifs
                    directory = sprintf('%s/%s_%s/',obj.gif_directory,label_string,tag);
                    [~, ~, ~] = mkdir(directory);
                    
                    for i = 0:4:360
                        view(i,48)
                        saveas(h,sprintf('%s/%03i',directory,i),'png')
                    end
                    
                    plot.makeGif(directory,sprintf('%s_%s.gif',label_string,tag),obj.outputs_directory);
                end
                
                if obj.make_histograms
                    directory = sprintf(obj.histogram_directory);
                    [~, ~, ~] = mkdir(directory);
                    plot.generateHistograms(people_matrix,directory,label_string,specific_label,tag)
                end
            end
        end
        
        function [people_matrix,possible_votes] = cleanSponsorVotes(obj,people_matrix,possible_votes,sponsorship_counts)
            
            [people_matrix,possible_votes] = obj.cleanVotes(people_matrix,possible_votes);
            
            obj.sponsor_filter = mean(sponsorship_counts.count) - std(sponsorship_counts.count)/2;
            
            % Generate the list of column names
            row_names = people_matrix.Properties.RowNames;
            
            % Iterate over the column names
            for i = 1:length(row_names)
                
                % If the value for sponsorship is less than the filter
                if sponsorship_counts{row_names{i},'count'} < obj.sponsor_filter %#ok<BDSCA>
                    people_matrix.(row_names{i})  = []; % Clear the people matrix
                    possible_votes.(row_names{i}) = []; % Clear the possible vote matrix
                    fprintf('WARNING: %s did not meet the vote threshold with only %i\n',row_names{i},sponsorship_counts{i,'count'});
                end
            end
        end
        
        function sponsor_name = getSponsorName(obj,id_code)
            if iscell(id_code)
                if length(id_code) == 1
                    id_code = str2double(regexprep(id_code,'id',''));
                    sponsor_name = obj.people{id_code == obj.people.sponsor_id,'name'};
                    sponsor_name = sponsor_name{1};
                else
                    sponsor_name = {};
                    for i = 1:length(id_code)
                        specific_id = str2double(regexprep(id_code{i},'id',''));
                        specific_name = obj.people{specific_id == obj.people.sponsor_id,'name'};
                        sponsor_name = [sponsor_name specific_name{1}]; %#ok<AGROW>
                    end
                end
            else
                if length(id_code) == 1
                    sponsor_name = obj.people{id_code == obj.people.sponsor_id,'name'};
                    sponsor_name = sponsor_name{1};
                else
                    sponsor_name = {};
                    for i = 1:length(id_code)
                        specific_name = obj.people{id_code{i} == obj.people.sponsor_id,'name'};
                        sponsor_name = [sponsor_name specific_name{1}]; %#ok<AGROW>
                    end
                end
            end
        end
        
        function output = readAllFilesOfSubject(obj,type)
            % initialize the full file list and output matrix
            directory = sprintf('%s/%s/legiscan',obj.data_directory,obj.state);
            list   = dir(directory);
            output = [];
            
            % loop over the available files
            for i = 1:length(list)
                % if the file fits the format we're looking for
                if ~isempty(regexp(list(i).name,'(\d+)-(\d+)_*','once'))
                    if istable(output) % if the output file exists, append
                        output = [output;readtable(sprintf('%s/%s/csv/%s.csv',directory,list(i).name,type))]; %#ok<AGROW>
                    else % if it doesn't exist, create it
                        output = readtable(sprintf('%s/%s/csv/%s.csv',directory,list(i).name,type));
                    end
                end
            end
        end
        
        function vote_structure = addRollcallVotes(obj,new_rollcall,new_votelist)
            vote_structure.rollcall_id = new_rollcall.roll_call_id;
            vote_structure.description   = new_rollcall.description;
            vote_structure.date          = new_rollcall.date;
            vote_structure.yea = new_rollcall.yea;
            vote_structure.nay = new_rollcall.nay;
            vote_structure.nv  = new_rollcall.nv;
            vote_structure.total_vote  = new_rollcall.total_vote;
            vote_structure.yes_percent = new_rollcall.yes_percent;
            vote_structure.yes_list     = new_votelist{new_votelist.vote == obj.VOTE_KEY('yea'),'sponsor_id'};
            vote_structure.no_list      = new_votelist{new_votelist.vote == obj.VOTE_KEY('nay'),'sponsor_id'};
            vote_structure.abstain_list = new_votelist{new_votelist.vote == obj.VOTE_KEY('absent'),'sponsor_id'};
        end
        
        function chamber_data = processChamberRollcalls(obj,chamber_rollcalls,votes_create,committee_threshold)
            
            chamber_data = {};
            
            % chammber_data.committee_id = ??? how do I set this?
            committee_votes = obj.getVoteTemplate();
            if sum(chamber_rollcalls.total_vote < committee_threshold) > 0
                committee_votes(sum(chamber_rollcalls.total_vote < committee_threshold)).rollcall_id = 1;
            end
            
            chamber_votes = obj.getVoteTemplate();
            if sum(chamber_rollcalls.total_vote >= committee_threshold)
                chamber_votes(sum(chamber_rollcalls.total_vote >= committee_threshold)).rollcall_id = 1;
            end
            
            committee_vote_count = 0;
            chamber_vote_count = 0;
            for j = 1:size(chamber_rollcalls,1);
                
                specific_votes = votes_create(votes_create.roll_call_id == chamber_rollcalls{j,'roll_call_id'},:);
                
                if chamber_rollcalls{j,'total_vote'} < committee_threshold; %#ok<BDSCA>
                    committee_vote_count = committee_vote_count + 1;
                    committee_votes(committee_vote_count) = obj.addRollcallVotes(chamber_rollcalls(j,:),specific_votes);
                else % full chamber
                    chamber_vote_count = chamber_vote_count +1;
                    chamber_votes(chamber_vote_count) = obj.addRollcallVotes(chamber_rollcalls(j,:),specific_votes);
                end
            end
            
            chamber_data(end+1).committee_votes = committee_votes;
            chamber_data.chamber_votes = chamber_votes;
            if ~isempty(chamber_votes)
                chamber_data.final_yea = chamber_votes(end).yea;
                chamber_data.final_nay = chamber_votes(end).nay;
                chamber_data.final_nv = chamber_votes(end).nv;
                chamber_data.final_total_vote = chamber_votes(end).total_vote;
                chamber_data.final_yes_percentage = chamber_votes(end).yes_percent;
            else
                chamber_data.final_yes_percentage = -1;
            end
        end
        
        function proximity_matrix = processSeatProximity(obj,people)
            % Create the string array list (which allows for referencing variable names
            ids = util.createIDstrings(people{:,'sponsor_id'});
            
            x = people{:,'SEATROW'};
            y = people{:,'SEATCOLUMN'};
            dist = sqrt(bsxfun(@minus,x,x').^2 + bsxfun(@minus,y,y').^2);
            
            proximity_matrix = array2table(dist,'RowNames',ids,'VariableNames',ids);
            proximity_matrix.name = obj.getSponsorName(ids)';
        end
    end
    
    methods (Static)
        function [republican_ids, democrat_ids] = processParties(people)
            % Create republican ids
            republican_ids = util.createIDstrings(people{people.party == 1,'sponsor_id'});
            
            % Create democrat ids
            democrat_ids   = util.createIDstrings(people{people.party == 0,'sponsor_id'});
            
            % Check for bad party IDs
            bad_ids = util.createIDstrings(people{~ismember(people.party,[0 1]),'sponsor_id'});
            for i = 1:length(bad_ids)
                fprintf('WARNING: INCORRECT PARTY ID FOR %s\n',bad_ids{i});
            end
        end
        
        function id_codes = createIDcodes(sponsor_ids)
            id_codes = cellfun(@(x) str2double(regexprep(x,'id','')),sponsor_ids,'Uniform',0);
            id_codes = [id_codes{:}]';
        end
        
        function specific_impact = getSpecificImpact(revealed_preference,specific_impact)
            switch revealed_preference
                case 0 % preference revealed to be no
                    switch specific_impact
                        case 0
                            specific_impact = 0.99; % voted no, low consistency
                        case 1
                            specific_impact = 0.01; % voted no, high consistency
                        otherwise
                            specific_impact = 1 - specific_impact;
                    end
                case 1
                    switch specific_impact
                        case 0
                            specific_impact = 0.01; % voted yes, low consistency
                        case 1
                            specific_impact = 0.99; % voted yes, high consistency
                        otherwise
                            specific_impact = specific_impact; %#ok<ASGSL>
                    end
                otherwise
                    error('Functionality for non-binary revealed preferences not currently supported')
            end
        end
        
        function [people_matrix,possible_votes] = cleanVotes(people_matrix,possible_votes)
            % Clear People who didn't have votes
            % Generate the list of row names
            row_names = people_matrix.Properties.RowNames;
            
            % Iterate over the row names
            for i = 1:length(people_matrix.Properties.RowNames)
                % If there are votes (these two statements should always be equivalent)
                if all(isnan(people_matrix{row_names{i},:})) || all(isnan(possible_votes{row_names{i},:}))
                    people_matrix(row_names{i},:) = []; % Clear the people matrix row
                    people_matrix.(row_names{i})  = []; % Clear the people matrix column
                    
                    possible_votes(row_names{i},:) = []; % Clear the people matrix row
                    possible_votes.(row_names{i})  = []; % Clear the people matrix column
                    
                    fprintf('WARNING: NO VOTES RECORDED FOR %s\n',row_names{i});
                end
            end
        end
        
        function vote_matrix = addVotes(vote_matrix,row,column,varargin)
            in = inputParser;
            addOptional(in,'value',1,@isnumeric);
            parse(in,varargin{:});
            value = in.Results.value;
            
            if ~isempty(row) && ~isempty(column)
                
                % pull out the data from the vote matrix
                temp = vote_matrix{row,column};
                
                % if the value is NaN, make it one (for accounting)
                temp(isnan(vote_matrix{row,column})) = value;
                
                % if it's not NaN, add one to the existing value
                temp(~isnan(vote_matrix{row,column})) = temp(~isnan(vote_matrix{row,column})) + value;
                
                % put the data back into the matrix
                vote_matrix{row,column} = temp;
            end
        end
        
        function [people_matrix] = normalizeVotes(people_matrix,vote_matrix)
            % Element-wise divide. This will take divide each value by the
            % possible value (person-vote total)/(possible vote total)
            people_matrix{:,:} = people_matrix{:,:} ./ vote_matrix{:,:};
        end
        
        % these three probably can be moved to a separate "templates" function?
        function vote_template = getVoteTemplate()
            vote_template = struct('rollcall_id',{},...
                'description',{},...
                'date',{},...
                'yea',{},...
                'nay',{},...
                'nv',{},...
                'total_vote',{},...
                'yes_percent',{},...
                'yes_list',{},...
                'no_list',{},...
                'abstain_list',{});
        end
        
        function bill_template = getBillTemplate()
            bill_template = struct(...
                'bill_id',{},...
                'bill_number',{},...
                'title',{},...
                'issue_category',{},...
                'sponsors',{},... % first vs co, also authors
                'date_introduced',{},...
                'date_last_action',{},...
                'house_data',{},...
                'passed_house',{},...
                'senate_data',{},...
                'passed_senate',{},...
                'passed_both',{},...
                'signed_into_law',{},...
                'complete',{});
            % originated in house/senate?
        end
        
        function chamber_template = getChamberTemplate()
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
        end
    end
end