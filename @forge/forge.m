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
                
        make_gifs
        make_histograms
        
        data_directory
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
        
        function init(obj)
            if obj.reprocess || exist(sprintf('data/%s/processed_data.mat',obj.state),'file') ~= 2
                
                bills_create     = obj.readAllFilesOfSubject('bills',obj.state);
                people_create    = obj.readAllFilesOfSubject('people',obj.state);
                rollcalls_create = obj.readAllFilesOfSubject('rollcalls',obj.state);
                
                rollcalls_create.senate      = strncmpi(rollcalls_create{:,'description'},{'S'},1);
                rollcalls_create.total_vote  = rollcalls_create.yea + rollcalls_create.nay;
                rollcalls_create.yes_percent = rollcalls_create.yea ./ rollcalls_create.total_vote;
                
                sponsors_create = obj.readAllFilesOfSubject('sponsors',obj.state);
                votes_create    = obj.readAllFilesOfSubject('votes',obj.state);
                history_create  = obj.readAllFilesOfSubject('history',obj.state);
                
                bill_set_create = containers.Map('KeyType','int32','ValueType','any');
                
                complete_check = table(bills_create.bill_id,zeros(length(bills_create.bill_id),1),zeros(length(bills_create.bill_id),1),'VariableNames',{'bill_id','complete','semi'});
                
                delete_str = '';
                for i = 1:length(bills_create.bill_id)
                    
                    % Screen updates
                    print_str = sprintf('%i',i);
                    fprintf([delete_str,print_str]);
                    delete_str = repmat(sprintf('\b'),1,length(print_str));
                    
                    template = obj.getBillTemplate();
                    
                    complete = 1;
                    
                    template(end+1).bill_id = bills_create{i,'bill_id'}; %#ok<AGROW>
                    template.bill_number    = bills_create{i,'bill_number'};
                    template.title          = bills_create{i,'title'};
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
                        
                        template.house_data   = house_data;
                        template.passed_house = (house_data.final_yes_percentage > 0.5);
                    else
                        template.passed_house = -1;
                        complete = 0;
                    end
                    
                    % ------------------ Senate Data -------------------- %
                    senate_rollcalls = bill_rollcalls(bill_rollcalls.senate == 1,:);
                    
                    if ~isempty(senate_rollcalls)
                        
                        senate_data = obj.processChamberRollcalls(senate_rollcalls,votes_create,obj.senate_size*0.75);
                        
                        template.senate_data   = senate_data;
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
                print_str = sprintf('Done! %i bills\n',i);
                fprintf([delete_str,print_str]);
            
                clear print_str complete chamber_votes committee_votes bill_history bill_rollcalls i j house_data house_rollcalls senate_data senate_rollcalls template
                
                var_list = who;
                var_list = var_list(~ismember(var_list,'obj'));
                save(sprintf('data/%s/processed_data.mat',obj.state),var_list{:})
            else
                load(sprintf('data/%s/processed_data',obj.state))
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
        function [chamber_matrix,chamber_votes,...
                chamber_sponsor_matrix,chamber_sponsor_votes,...
                committee_matrix,committee_votes,...
                committee_sponsor_matrix,committee_sponsor_votes,...
                consistency_matrix,bill_ids] = processChamberVotes(obj,people,chamber)
            
            chamber_data = sprintf('%s_data',chamber);
            
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
                if obj.bill_set(i).(sprintf('passed_%s',chamber)) >= 0 && obj.bill_set(i).(chamber_data).final_yes_percentage < agreement_threshold && obj.bill_set(i).(chamber_data).final_yes_percentage > (1 - agreement_threshold)
                    
                    % Sponsor information
                    sponsor_ids = util.createIDstrings(obj.bill_set(i).sponsors,ids);
                    
                    % Increase the sponsorship count by one
                    sponsorship_counts{ismember(sponsorship_counts.Properties.RowNames,sponsor_ids),'count'} = sponsorship_counts{ismember(sponsorship_counts.Properties.RowNames,sponsor_ids),'count'} + 1;
                    
                    %%% COMMITTEE INFORMATION - TODO probably can collapse this into a common function with the chamber data
                    is_committee_votes = 0;
                    for j = 1:length(obj.bill_set(i).(chamber_data).committee_votes)
                        
                        % so it's sort of pointless to do the loop and then
                        % only process the last bill but I want to preserve
                        % the functionality
                        if j < length(obj.bill_set(i).(chamber_data).committee_votes)
                            continue
                        end
                        
                        committee_count = committee_count + 1;
                        
                        % Yes/No votes
                        committee_yes_ids = util.createIDstrings(obj.bill_set(i).(chamber_data).committee_votes(j).yes_list,ids);
                        committee_no_ids  = util.createIDstrings(obj.bill_set(i).(chamber_data).committee_votes(j).no_list,ids);

                        % STRAIGHT VOTES
                        committee_matrix = obj.addVotes(committee_matrix,committee_yes_ids,committee_yes_ids);
                        committee_matrix = obj.addVotes(committee_matrix,committee_no_ids,committee_no_ids);
                        committee_matrix = obj.addVotes(committee_matrix,committee_yes_ids,committee_no_ids,'value',0);
                        committee_matrix = obj.addVotes(committee_matrix,committee_no_ids,committee_yes_ids,'value',0);
                        
                        % Place that information into possible votes matrix
                        committee_votes = obj.addVotes(committee_votes,[committee_yes_ids ; committee_no_ids],[committee_yes_ids ; committee_no_ids]);
                        
                        print_str = sprintf('%i %i',i,j);
                        fprintf([delete_str,print_str]);
                        delete_str = repmat(sprintf('\b'),1,length(print_str));
                        
                        is_committee_votes = 1;
                    end
                    
                    if is_committee_votes % could also do a ~isempty(j)
                        % SPONSORS - take the last *committee* vote - TODO is this really what we want to do here?
                        committee_sponsor_matrix = obj.addVotes(committee_sponsor_matrix,sponsor_ids,yes_ids);
                        committee_sponsor_matrix = obj.addVotes(committee_sponsor_matrix,sponsor_ids,no_ids,'value',0);
                        
                        % Place that information into possible votes matrix
                        committee_sponsor_votes = obj.addVotes(committee_sponsor_votes,sponsor_ids,[yes_ids ; no_ids]);
                    end
                    
                    %%% CHAMBER INFORMATION
                    is_chamber_votes = 0;
                    for j = 1:length(obj.bill_set(i).(chamber_data).chamber_votes)
                        % so it's sort of pointless to do the loop and then
                        % only process the last bill but I want to preserve
                        % the functionality
                        if isempty(regexp(upper(obj.bill_set(i).(chamber_data).chamber_votes(j).description{:}),'THIRD','once'))
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
                        chamber_sponsor_votes = obj.addVotes(chamber_sponsor_votes,sponsor_ids,[yes_ids ; no_ids]);
                    end
                    
                    if is_chamber_votes && is_committee_votes
                        % Generate the consistency information
                        joined_set = [committee_yes_ids;committee_no_ids];
                        joined_set = joined_set(ismember(joined_set,[yes_ids;no_ids]));
                        
                        consistency_matrix{joined_set,'opportunity'} = consistency_matrix{joined_set,'opportunity'} + 1;
                        
                        matched_set = [committee_yes_ids(ismember(committee_yes_ids,yes_ids)) ; committee_no_ids(ismember(committee_no_ids,no_ids))];
                        consistency_matrix{matched_set,'consistency'} = consistency_matrix{matched_set,'consistency'} + 1;
                        
                        bill_count = bill_count + 1;
                        
                        bill_ids(end+1) = i; %#ok<AGROW>
                    end
                end
                
            end
            print_str = sprintf('Done! %i bills\n',length(bill_keys));
            fprintf([delete_str,print_str]);
            
            fprintf('Complete Bill Count: %i\n',bill_count)
            
            [chamber_matrix, chamber_votes] = obj.cleanVotes(chamber_matrix, chamber_votes);
            [chamber_sponsor_matrix, chamber_sponsor_votes] = obj.cleanSponsorVotes(chamber_sponsor_matrix,chamber_sponsor_votes,sponsorship_counts);
            
            [committee_matrix, committee_votes] = obj.cleanVotes(committee_matrix, committee_votes);
            [committee_sponsor_matrix, committee_sponsor_votes] = obj.cleanSponsorVotes(committee_sponsor_matrix,committee_sponsor_votes,sponsorship_counts);
            
            [chamber_matrix]           = obj.normalizeVotes(chamber_matrix, chamber_votes);
            [chamber_sponsor_matrix]   = obj.normalizeVotes(chamber_sponsor_matrix, chamber_sponsor_votes);
            [committee_matrix]         = obj.normalizeVotes(committee_matrix,committee_votes);
            [committee_sponsor_matrix] = obj.normalizeVotes(committee_sponsor_matrix,committee_sponsor_votes);
        end
        
        function [accuracy, number_sponsors, number_committee, varargout] = predictOutcomes(obj,bill_id,ids,chamber_sponsor_matrix,chamber_consistency_matrix,committee_sponsor_matrix,chamber_specifics,generate_outputs,chamber,varargin)
            % at some point it would probably be a good idea to spin this
            % out into its own file structure, just like the learning
            % algorithm
            
            monte_carlo_number = 1;
            if length(varargin) == 1
                monte_carlo_number = varargin{1};
            end
            
            % number of legislators to randomly pick to do out-step
            % predictions
            number_of_legislators = 8;
            varargout{1} = [];
            varargout{2} = [];
            
            chamber_data = sprintf('%s_data',chamber);
            
            bill_information = obj.bill_set(bill_id);
            sponsor_ids      = util.createIDstrings(bill_information.sponsors,ids);
            number_sponsors  = size(sponsor_ids,1);
            
            % this is cheating, eventually we'll need the committee
            % membership but this is fine for now (taking the people that
            % vote and working back) since we have perfect information
            
            if isempty(bill_information.(chamber_data).committee_votes) % no committee information available
                accuracy         = NaN;
                number_sponsors  = NaN;
                number_committee = NaN;
                varargout{1}     = {};
                return
            end
            
            committee_yes     = bill_information.(chamber_data).committee_votes.yes_list;
            committee_no      = bill_information.(chamber_data).committee_votes.no_list;
            committee_members = [committee_yes ; committee_no];
            committee_ids     = util.createIDstrings(committee_members,ids);
            committee_ids_yes = util.createIDstrings(committee_yes,ids);
            committee_ids_no  = util.createIDstrings(committee_no,ids);
            number_committee  = size(committee_ids,1);
            
            found_it = 0;
            for i = length(bill_information.(chamber_data).chamber_votes):-1:1
                if ~isempty(regexp(upper(bill_information.(chamber_data).chamber_votes(i).description{:}),'THIRD READING','once'))
                    bill_yes = bill_information.(chamber_data).chamber_votes(i).yes_list;
                    bill_no  = bill_information.(chamber_data).chamber_votes(i).no_list;
                    found_it = 1;
                    break
                end
            end
            
            if ~found_it % no third reading vote found
                accuracy         = NaN;
                number_sponsors  = NaN;
                number_committee = NaN;
                varargout{1}     = {};
                return
            end
            
            bill_yes_ids = util.createIDstrings(bill_yes,ids);
            bill_no_ids  = util.createIDstrings(bill_no,ids);           
            
            % initial assumption, eveyone is equally likely to vote yes as
            % to vote no. This is probably not true, I'll have to figure
            % out how to figure this out.
            
            % so we make a table for the bayes, we'll keep track of effects
            % here and then update at each time t. New column for every
            % update, new time t for every update
            bayes_initial = 0.5; 
            t_set = array2table(NaN(length(ids),1),'VariableNames',{'final'},'RowNames',ids);
            accuracy_table = array2table(NaN(1,5),'VariableNames',{'final','name','t1','committee_vote','committee_consistency'},'RowNames',{'accuracy'});

            t_set.name = obj.getSponsorName(ids);
            t_set.t1   = NaN(length(ids),1);
            t_set{bill_yes_ids,'final'} = 1;
            t_set{bill_no_ids,'final'}  = 0;
            
            % --------- COMMITTEE EFFECT ---------
            % Calculate sponsor effect and set t1
            committee_specific = NaN(length(committee_ids),1);
            committee_sponsor_match = sponsor_ids(ismember(sponsor_ids,committee_sponsor_matrix.Properties.VariableNames));
            for i = 1:length(committee_ids)

                if ismember(committee_ids{i},committee_sponsor_matrix.Properties.RowNames)
                    sponsor_specific_effect = 1;
                    
                    for k = 1:length(committee_sponsor_match)
                        sponsor_specific_effect = sponsor_specific_effect*predict.getSpecificImpact(1,committee_sponsor_matrix{committee_ids{i},committee_sponsor_match{k}});
                    end
                    
                    committee_specific(i) = sponsor_specific_effect*bayes_initial / (sponsor_specific_effect*bayes_initial + (1-sponsor_specific_effect)*(1-bayes_initial));
                else
                    committee_specific(i) = bayes_initial;
                end
            end
            t_set{committee_ids,'t1'} = committee_specific;
            
            
            t_set.committee_vote = NaN(length(t_set.Properties.RowNames),1);
            t_set{committee_ids_yes,'committee_vote'} = 1;
            t_set{committee_ids_no,'committee_vote'}  = 0;
            
            t_set.committee_consistency = NaN(length(t_set.Properties.RowNames),1);
            t_set{committee_ids_yes,'committee_consistency'} = chamber_consistency_matrix{committee_ids_yes,'percentage'};
            t_set{committee_ids_no,'committee_consistency'}  = chamber_consistency_matrix{committee_ids_no,'percentage'};
            
            % So now we only update based on expressed preference for t2
            % calculate t2
            t_set_current_value  = NaN(length(ids),1);
            
            matched_ids = find(ismember(ids,[sponsor_ids;committee_ids]));
            
            for j = 1:length(ids)
                if ~any(j == matched_ids)
                    combined_impact = 1;
                    
                    for k = 1:length(matched_ids)
                        combined_impact = combined_impact*predict.getSpecificImpact(1,chamber_specifics(j,k));
                    end
                        
                    t_set_current_value(j) = (combined_impact*bayes_initial)/(combined_impact*bayes_initial + (1-combined_impact)*(1-bayes_initial));
                else
                    if ~isnan(t_set.committee_vote(j))
                        t_set_current_value(j) = predict.getSpecificImpact(t_set.committee_vote(j),t_set.committee_consistency(j));
                    elseif ismember(ids(j),chamber_sponsor_matrix.Properties.RowNames) && ismember(ids(j),chamber_sponsor_matrix.Properties.VariableNames)
                        t_set_current_value(j) = predict.getSpecificImpact(1,chamber_specifics(j,j));
                    else
                        t_set_current_value(j) = 0.5;
                    end
                end
            end
            
            t_set.t2 = t_set_current_value;
            t2_check = (round(t_set.t2) == t_set.final);
            
            incorrect = sum(t2_check == false);
            are_nan   = sum(isnan(t_set{t2_check == false,'final'}));
            accuracy_table.t2 = 100*(1-(incorrect-are_nan)/(100-are_nan));
            
            % here is where the updating comes in, need to mock up some
            % data whereby people declare preferences. However, things are
            % pretty damn solid at this point
            
            % at this point, for t3, we do basically the same thing as t2
            % but we just update everything            
            legislator_list = [bill_yes_ids ; bill_no_ids];
            
            if length(varargin) == 1
                accuracy_list = zeros(2,monte_carlo_number);
                legislators_list = cell(monte_carlo_number,1);
                accuracy_steps_list = cell(monte_carlo_number,1);
            end
            
            t_final_results = t_set.final;
            
            for j = 1:monte_carlo_number
                rng(j)
                
                legislator_id  = legislator_list(randperm(length(legislator_list),number_of_legislators));
                direction      = ismember(legislator_id,bill_yes_ids);
                accuracy_steps = zeros(1,length(legislator_id)+1);
                accuracy_steps(1) = accuracy_table.t2;
                
                t_count = 2;
                
                for i = 1:length(legislator_id)
                    
                    [t_set,t_count,t_current,accuracy_steps(i+1)] = predict.updateBayes(legislator_id{i},direction(i),t_set,chamber_specifics,t_count,ids,t_final_results);
                    
                end
                
                t_set.(sprintf('%s_check',t_current)) = round(t_set.(t_current)) == t_set.final;
                incorrect = sum(t_set.(sprintf('%s_check',t_current)) == false);
                are_nan   = sum(isnan(t_set{t_set.(sprintf('%s_check',t_current)) == false,'final'}));
                accuracy  = 100*(1-(incorrect-are_nan)/(100-are_nan));
                
                if length(varargin) == 1
                    accuracy_list(1,j)     = accuracy;
                    accuracy_list(2,j)     = (accuracy - accuracy_table.t2);
                    legislators_list{j}    = legislator_id;
                    
                    accuracy_steps_delta = zeros(1,length(legislator_id));
                    for i = 1:length(accuracy_steps)-1
                        accuracy_steps_delta(i) = accuracy_steps(i+1) - accuracy_steps(i);
                    end
                    
                    accuracy_steps_list{j} = accuracy_steps_delta;
                end
            end
            
            if any(bill_id == [590034 583138 587734 590009]) && generate_outputs
                save_directory = sprintf('%s/%i',obj.outputs_directory,bill_id);
                [~,~,~] = mkdir(save_directory);
                
                obj.plotTSet(t_set(:,'t1'),'t1 - Predicting the Committee Vote')
                saveas(gcf,sprintf('%s/t1',save_directory),'png');
                
                obj.plotTSet(t_set(:,'t2'),'t2 - Predicting chamber vote with committee and sponsor vote')
                saveas(gcf,sprintf('%s/t2',save_directory),'png');
                
                for i = 3:t_count;
                    t_current = sprintf('t%i',i);
                    obj.plotTSet(t_set(:,t_current),sprintf('%s - %s, %s',t_current,obj.getSponsorName(legislator_id{i-2}),direction(i-2)));
                    saveas(gcf,sprintf('%s/%s',save_directory,t_current),'png');
                end
                
                writetable(t_set,sprintf('%s/t_set_test.xlsx',save_directory),'WriteRowNames',true)
            end
            
            if nargout > 3
                accuracy     = accuracy_list;
                varargout{1} = legislators_list;
                varargout{2} = accuracy_steps_list;
            end
        end
        
        function [accuracy_list, accuracy_delta, legislators_list, accuracy_steps_list, bill_ids] = runMonteCarlo(obj,chamber_bill_ids,chamber_people,chamber_sponsor_matrix,chamber_consistency_matrix,committee_sponsor_matrix,chamber_matrix,generate_outputs,chamber,monte_carlo_number)
            
            tic
            bill_target = length(chamber_bill_ids);
            
            delete_str = '';
            
            accuracy_list       = zeros(bill_target,monte_carlo_number);
            accuracy_delta      = zeros(bill_target,monte_carlo_number);
            legislators_list    = cell(bill_target,monte_carlo_number);
            accuracy_steps_list = cell(bill_target,monte_carlo_number);
            bill_ids            = zeros(1,bill_target);
            
            % These will reduce the runtime in the the predictOutcomes
            % function
            ids               = util.createIDstrings(chamber_people.sponsor_id);
            chamber_specifics = chamber_matrix{:,:};
            
            bill_hit = 1;
            i = 1;
            while bill_hit <= bill_target && i <= length(chamber_bill_ids)
                
                [accuracy,~,~,legislators,accuracy_steps] = obj.predictOutcomes(chamber_bill_ids(i),ids,chamber_sponsor_matrix,chamber_consistency_matrix,committee_sponsor_matrix,chamber_specifics,generate_outputs,lower(chamber),monte_carlo_number);
                
                if ~isempty(legislators)
                    accuracy_list(bill_hit,:)       = accuracy(1,:);
                    accuracy_delta(bill_hit,:)      = accuracy(2,:);
                    accuracy_steps_list(bill_hit,:) = accuracy_steps;
                    legislators_list(bill_hit,:)    = legislators;
                else
                    i = i + 1;
                    continue
                end
                
                print_str = sprintf('%i %i',bill_hit,chamber_bill_ids(i));
                fprintf([delete_str,print_str]);
                delete_str = repmat(sprintf('\b'),1,length(print_str));
                
                bill_ids(bill_hit) = chamber_bill_ids(i);
                bill_hit = bill_hit + 1;
                i = i + 1;
            end
            bill_hit = bill_hit - 1;
            
            accuracy_list       = accuracy_list(1:bill_hit,1:monte_carlo_number);
            accuracy_delta      = accuracy_delta(1:bill_hit,1:monte_carlo_number);
            legislators_list    = legislators_list(1:bill_hit,1:monte_carlo_number);
            accuracy_steps_list = accuracy_steps_list(1:bill_hit,1:monte_carlo_number);
            bill_ids = bill_ids(1:bill_hit);
            
            h = figure();
            hold on
            title(sprintf('%s Prediction Boxplot',chamber))
            boxplot(accuracy_list',bill_ids)
            xlabel('Bills')
            ylabel('Accuracy')
            hold off
            saveas(h,sprintf('%s/%s_prediction_boxplot',obj.outputs_directory,lower(chamber)),'png')
            
            h = figure();
            hold on
            title(sprintf('%s Prediction Boxplot - Delta',chamber))
            boxplot(accuracy_delta',bill_ids)
            xlabel('Bills')
            ylabel('Change in Accuracy')
            hold off
            saveas(h,sprintf('%s/%s_prediction_delta_boxplot',obj.outputs_directory,lower(chamber)),'png')
                  
            h = figure();
            hold on
            title(sprintf('%s Total Prediction Boxplot',chamber))
            boxplot(accuracy_list(1:numel(accuracy_list)))
            xlabel('All Bills')
            ylabel('Accuracy')
            hold off
            saveas(h,sprintf('%s/%s_total_prediction_boxplot',obj.outputs_directory,lower(chamber)),'png')
            
            h = figure();
            hold on
            title(sprintf('%s Total Prediction Boxplot - Delta',chamber))
            boxplot(accuracy_delta(1:numel(accuracy_delta)))
            xlabel('All Bills')
            ylabel('Change in Accuracy')
            hold off
            saveas(h,sprintf('%s/%s_total_prediction_delta_boxplot',obj.outputs_directory,lower(chamber)),'png')
            
            save(sprintf('%s/%s_predictive_model.mat',obj.outputs_directory,lower(chamber)),'accuracy_list','accuracy_delta','legislators_list','accuracy_steps_list','bill_ids')
            
            timed = toc;
            
            print_str = sprintf('%s Done - %i bills! %0.3f\n',chamber,bill_hit,timed);
            fprintf([delete_str,print_str]);
        end
        
        function results_table = processLegislatorImpacts(obj,accuracy_list,accuracy_list_delta,legislators_list,accuracy_steps_list,bill_list,chamber)
            
            master_list = [];
            
            for i = 1:size(legislators_list,1)
                
                specific_legislators   = cell(size(legislators_list{i,1},1),size(legislators_list,2));
                specific_accuracy_list = zeros(size(legislators_list{i,1},1)+1,size(legislators_list,2));
                specific_delta_list    = zeros(size(legislators_list{i,1},1),size(legislators_list,2));
                
                for j = 1:size(legislators_list,2)
                    
                    specific_accuracy_list(1,j) = accuracy_list(i,j) - accuracy_list_delta(i,j);
                    for k = 1:length(accuracy_steps_list{i,j})
                        specific_accuracy_list(k+1,j) = specific_accuracy_list(k) + accuracy_steps_list{i,j}(k);
                        specific_delta_list(k,j)      = accuracy_steps_list{i,j}(k);
                    end
                    specific_legislators(:,j) = legislators_list{i,j};
                    
                end
                
                % A neat way to generate the monte carlo spread for a single
                % bill, not sure it's super useful for the massive number of
                % bills but neat on a single bill basis
                
                %                 figure()
                %                 hold on ; grid on ;
                %                 title('Accuracy Over Predictive Set')               
                %                 plot(specific_accuracy_list)
                %                 xlabel('Revealed preference points')
                %                 ylabel('Accuracy')
                %                 hold off
                
                %                 figure()
                %                 title('Delta Accuracy Over Predictive Set')
                %                 hold on ; grid on ;
                %                 plot(specific_delta_list)
                %                 xlabel('Revealed preference points')
                %                 ylabel('Change in Accuracy')
                %                 hold off
                
                % I need to come up with some equation to relate initial 
                % accuracy revealed, preference posiition (1-8), change in
                % accuracy as a result of their revealed preference...
                % maybe others? average agreement score with other
                % legislators?
                
                unique_legislators = unique(specific_legislators);
                impact_score       = cell(1,length(unique_legislators));
                placement          = cell(1,length(unique_legislators));
                legislator_score   = cell(length(unique_legislators),1);
                placement_points   = linspace(size(specific_legislators,1),1,size(specific_legislators,1))';
                for j = 1:length(unique_legislators)
                    impact_score{j} = specific_delta_list(ismember(specific_legislators,unique_legislators(j)));
                    placement{j}    = sum(ismember(specific_legislators,unique_legislators(j)),2);
                    
                    legislator_score{j} = mean(impact_score{j})/specific_accuracy_list(1,1)*mean(placement{j}.*placement_points);
                end
                
                master_list = [master_list ; unique_legislators legislator_score];
            end
            
            master_unique_legislators = unique(master_list(:,1));
            coverage = NaN(length(master_unique_legislators),1);
            results  = NaN(length(master_unique_legislators),1);
            for i = 1:length(master_unique_legislators)
                index = ismember(master_list(:,1),master_unique_legislators{i});
                coverage(i) = sum(index);
                results(i) = mean([master_list{index,2}]);
            end
            coverage = coverage / length(bill_list);
            
            sponsor_names = obj.getSponsorName(master_unique_legislators);
            results_table = table(master_unique_legislators,sponsor_names,coverage,results);
        end
        
        function stepwisePrediction(obj,chamber_bill_ids,chamber_people,chamber_sponsor_matrix,chamber_consistency_matrix,committee_sponsor_matrix,chamber_matrix,chamber)
            
            accuracy_list = zeros(1,length(senate_bill_ids));
            sponsor_list = zeros(1,length(senate_bill_ids));
            committee_list = zeros(1,length(senate_bill_ids));
            
            chamber_data = sprintf('%s_data',chamber);
            
            ids               = util.createIDstrings(chamber_people.sponsor_id);
            chamber_specifics = chamber_matrix{:,:};
            competitive_bills = cell2table(cell(length(senate_bill_ids),8),'VariableNames',{'bill_id' 'bill_number' 'title' 'introduced' 'last_action' 'issue_id','sponsors','committee_members'});
            
            for i = 1:length(chamber_bill_ids)
                competitive_bills{i,'bill_id'}     = {obj.bill_set(chamber_bill_ids(i)).bill_id};
                competitive_bills{i,'bill_number'} = obj.bill_set(chamber_bill_ids(i)).bill_number;
                competitive_bills{i,'title'}       = obj.bill_set(chamber_bill_ids(i)).title;
                competitive_bills{i,'introduced'}  = obj.bill_set(chamber_bill_ids(i)).date_introduced;
                competitive_bills{i,'last_action'} = obj.bill_set(chamber_bill_ids(i)).date_last_action;
                competitive_bills{i,'issue_id'}    = {obj.ISSUE_KEY(obj.bill_set(chamber_bill_ids(i)).issue_category)};
                
                sponsors_names = obj.getSponsorName(obj.bill_set(chamber_bill_ids(i)).sponsors(1));
                for j = 2:length(obj.bill_set(chamber_bill_ids(i)).sponsors)
                    sponsors_names = [sponsors_names ',' obj.getSponsorName(obj.bill_set(chamber_bill_ids(i)).sponsors(j))]; %#ok<AGROW>
                end
                competitive_bills{i,'sponsors'} = {sponsors_names};
                
                comittee_ids = [obj.bill_set(chamber_bill_ids(i)).(chamber_data).committee_votes(end).yes_list ; obj.bill_set(chamber_bill_ids(i)).(chamber_data).committee_votes(end).no_list];
                committee_names = obj.getSponsorName(comittee_ids(1));
                for j = 2:length(comittee_ids)
                    committee_names = [committee_names ',' obj.getSponsorName(comittee_ids(j))]; %#ok<AGROW>
                end
                competitive_bills{i,'committee_members'} = {committee_names};
                
                
                [accuracy, sponsor, committee] = obj.predictOutcomes(chamber_bill_ids(i),ids,chamber_sponsor_matrix,chamber_consistency_matrix,committee_sponsor_matrix,chamber_specifics,obj.generate_outputs,chamber);
                accuracy_list(i) = accuracy;
                sponsor_list(i) = sponsor;
                committee_list(i) = committee;
            end
            
            if obj.generate_outputs
                writetable(competitive_bills,sprintf('%s/%s_competitive_bills.xlsx',obj.outputs_directory,chamber),'WriteRowNames',false);
            end
            
            if ~isempty(accuracy_list) && obj.generate_outputs
                h = figure();
                hold on
                title(sprintf('%s Predictive Model Accuracy at t2',chamber))
                xlabel('Accuracy')
                ylabel('Frequency')
                grid on
                histfit(accuracy_list,20)
                axis([0 100 0 inf])
                hold off
                saveas(h,sprintf('%s/%s_accuracy_histogram_t2',obj.outputs_directory,chamber),'png')
            end
            
            if ~isempty(sponsor_list) && obj.generate_outputs
                h = figure();
                hold on
                title(sprintf('%s Sponsor Count',chamber))
                xlabel('Number of Sponsors')
                ylabel('Frequency')
                grid on
                histfit(sponsor_list,10)
                axis([0 max(sponsor_list) 0 inf])
                hold off
                saveas(h,sprintf('%s/%s_sponsor_histogram',obj.outputs_directory,chamber),'png')
            end
            
            if ~isempty(committee_list) && obj.generate_outputs
                h = figure();
                hold on
                title(sprintf('%s Committee Member Count',chamber))
                xlabel('Number of Committee Members')
                ylabel('Frequency')
                grid on
                histfit(committee_list,10)
                axis([0 max(committee_list) 0 inf])
                hold off
                saveas(h,sprintf('%s/%s_committee_histogram',obj.outputs_directory,chamber),'png')
            end
        end
        
        function plotTSet(obj,t_set_values,title_text)
            
            label_text  = t_set_values.Properties.RowNames(~isnan(t_set_values{:,:}));
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
                specific_id = cellfun(@str2double,regexprep(id_code,'id',''));
                sponsor_name = obj.people.name(arrayfun(@(x)find(obj.people.sponsor_id==x,1),specific_id));
            else
                sponsor_name = obj.people.name(arrayfun(@(x)find(obj.people.sponsor_id==x,1),id_code));
            end
        end
        
        function vote_structure = addRollcallVotes(obj,new_rollcall,new_votelist)
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
            chamber_vote_count   = 0;
            
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
                chamber_data.final_nv  = chamber_votes(end).nv;
                chamber_data.final_total_vote     = chamber_votes(end).total_vote;
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
        function output = readAllFilesOfSubject(type,state)
            % initialize the full file list and output matrix
            directory = sprintf('data/%s/legiscan',state);
            list   = dir(directory);
            output = [];
            
            % loop over the available files
            for i = length(list):-1:1
                % if the file fits the format we're looking for
                if ~isempty(regexp(list(i).name,'(\d+)-(\d+)_.*','once'))
                    if istable(output) % if the output file exists, append
                        new_table = readtable(sprintf('%s/%s/csv/%s.csv',directory,list(i).name,type));
                        new_table.year = ones(height(new_table),1)*str2double(regexprep(list(i).name,'-(\d+)_.*',''));
                        
                        field_match = ismember(output.Properties.VariableNames,new_table.Properties.VariableNames);
                        
                        if any(~field_match)
                            for j = 1:length(field_match)
                                if ~field_match(j)
                                    if isa(output.(output.Properties.VariableNames{j})(1),'cell')
                                        new_table.(output.Properties.VariableNames{j}) = cell(height(new_table),1);
                                    elseif isa(output.(output.Properties.VariableNames{j})(1),'double')
                                        new_table.(output.Properties.VariableNames{j}) = NaN(height(new_table),1);
                                    else
                                        error('DATA TYPE NOT RECOGNIZED!')
                                    end
                                end
                            end
                        end
                        
                        output = [output;new_table]; %#ok<AGROW>
                    else % if it doesn't exist, create it
                        output = readtable(sprintf('%s/%s/csv/%s.csv',directory,list(i).name,type));
                        output.year = ones(height(output),1)*str2double(regexprep(list(i).name,'-(\d+)_.*',''));
                    end
                end
            end
        end
        
        function [republican_ids, democrat_ids] = processParties(people)
            % Create party ids
            republican_ids = util.createIDstrings(people{people.party_id == 1,'sponsor_id'});
            democrat_ids   = util.createIDstrings(people{people.party_id == 0,'sponsor_id'});
            
            % Check for bad party IDs
            bad_ids = util.createIDstrings(people{~ismember(people.party_id,[0 1]),'sponsor_id'});
            for i = 1:length(bad_ids)
                fprintf('WARNING: INCORRECT PARTY ID FOR %s\n',bad_ids{i});
            end
        end
        
        function id_codes = createIDcodes(sponsor_ids)
            id_codes = cellfun(@(x) str2double(regexprep(x,'id','')),sponsor_ids,'Uniform',0);
            id_codes = [id_codes{:}]';
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
                    
                    possible_votes(row_names{i},:) = []; % Clear the possible votes row
                    possible_votes.(row_names{i})  = []; % Clear the possible votes column
                    
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