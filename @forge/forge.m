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
        % - generate committee membership lists
        function obj = forge(varargin)
            in = inputParser;
            addOptional(in,'recompute',0,@islogical);
            addOptional(in,'reprocess',0,@islogical);
            addOptional(in,'state','IN',@(x) ischar(x) && length(x) == 2);
            parse(in,varargin{:});
            
            obj.recompute = in.Results.recompute;
            obj.reprocess = in.Results.reprocess;
            obj.state     = in.Results.state;
            
            obj.state = 'IN';
            obj.data_directory = 'data';
            
            obj.outputs_directory = 'outputs';
            obj.gif_directory = sprintf('%s/gif',obj.outputs_directory);
            obj.histogram_directory = sprintf('%s/histograms',obj.outputs_directory);
            
            obj.learning_algorithm_data = la.loadLearnedMaterials();
            
            obj.senate_size = 50;
            obj.house_size = 100;
            
            if obj.reprocess || exist('processed_data.mat','file') ~= 2
                
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
                        
                        house_data = obj.processChamberRollcalls(house_rollcalls,votes_create,obj.house_size*0.6);
                        
                        template.house_data = house_data;
                        template.passed_house = (house_data.final_yes_percentage > 0.5);
                    else
                        template.passed_house = -1;
                        complete = 0;
                    end
                    
                    % ------------------ Senate Data -------------------- %
                    senate_rollcalls = bill_rollcalls(bill_rollcalls.senate == 1,:);
                    
                    if ~isempty(senate_rollcalls)
                        
                        senate_data = obj.processChamberRollcalls(senate_rollcalls,votes_create,obj.senate_size*0.6);
                        
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
                save('processed_data',var_list{:})
            else
                load('processed_data') %
            end
            
            obj.bills     = bills_create;
            obj.history   = history_create;
            obj.people    = people_create;
            obj.rollcalls = rollcalls_create;
            obj.sponsors  = sponsors_create;
            obj.votes     = votes_create;
            
            obj.bill_set = bill_set_create;
        end
        
        function run(obj)
            
            if exist('saved_data.mat','file') ~= 2 || obj.recompute
                
                % CODED SPECIFICALLY FOR THE INDIANA HOUSE AND SENATE.
                % ABSTRACTABLE TO OTHER STATES, WE JUST NEED TO ADJUST THE
                % CHAMBER DESCRIPTIONS
                
                % Read in the specific 2013-2014 Indiana List
                house_people = readtable(sprintf('%s/%s/people_2013-2014.xlsx',obj.data_directory,obj.state));
                
                [house_chamber_matrix,house_chamber_votes,...
                    house_sponsor_chamber_matrix,house_sponsor_chamber_votes,...
                    house_committee_matrix,house_committee_votes,...
                    house_sponsor_committee_matrix,house_sponsor_committee_votes,...
                    house_consistency_matrix]  = obj.processHouseVotes(house_people);
                [house_chamber_matrix]           = obj.normalizeVotes(house_chamber_matrix, house_chamber_votes);
                [house_sponsor_chamber_matrix]   = obj.normalizeVotes(house_sponsor_chamber_matrix, house_sponsor_chamber_votes);
                [house_committee_matrix]         = obj.normalizeVotes(house_committee_matrix,house_committee_votes);
                [house_sponsor_committee_matrix] = obj.normalizeVotes(house_sponsor_committee_matrix,house_sponsor_committee_votes);
                
                house_seat_matrix = obj.processSeatProximity(house_people);
                
                house_consistency_matrix.percentage = house_consistency_matrix.consistency ./ house_consistency_matrix.opportunity;
                
                % Create Republican and Democrat Lists (makes accounting easier)
                [republican_ids, democrat_ids] = obj.processParties(house_people);
                
                
                house_republicans_chamber_votes = house_chamber_matrix(ismember(house_chamber_matrix.Properties.RowNames,republican_ids),ismember(house_chamber_matrix.Properties.VariableNames,republican_ids));
                house_democrats_chamber_votes   = house_chamber_matrix(ismember(house_chamber_matrix.Properties.RowNames,democrat_ids),ismember(house_chamber_matrix.Properties.VariableNames,democrat_ids));
                
                house_republicans_chamber_sponsor = house_sponsor_chamber_matrix(ismember(house_sponsor_chamber_matrix.Properties.RowNames,republican_ids),ismember(house_sponsor_chamber_matrix.Properties.VariableNames,republican_ids));
                house_democrats_chamber_sponsor   = house_sponsor_chamber_matrix(ismember(house_sponsor_chamber_matrix.Properties.RowNames,democrat_ids),ismember(house_sponsor_chamber_matrix.Properties.VariableNames,democrat_ids));
                
                house_republicans_committee_votes = house_committee_matrix(ismember(house_committee_matrix.Properties.RowNames,republican_ids),ismember(house_committee_matrix.Properties.VariableNames,republican_ids));
                house_democrats_committee_votes   = house_committee_matrix(ismember(house_committee_matrix.Properties.RowNames,democrat_ids),ismember(house_committee_matrix.Properties.VariableNames,democrat_ids));
                
                house_republicans_committee_sponsor = house_sponsor_committee_matrix(ismember(house_sponsor_committee_matrix.Properties.RowNames,republican_ids),ismember(house_sponsor_committee_matrix.Properties.VariableNames,republican_ids));
                house_democrats_committee_sponsor   = house_sponsor_committee_matrix(ismember(house_sponsor_committee_matrix.Properties.RowNames,democrat_ids),ismember(house_sponsor_committee_matrix.Properties.VariableNames,democrat_ids));
                
                
                var_list = who;
                var_list = var_list(~ismember(var_list,'obj'));
                save('saved_data',var_list{:})
                
                delete(sprintf('%s/house_*.xlsx',obj.outputs_directory));
                
                writetable(house_chamber_matrix,sprintf('%s/house_all_chamber_matrix.xlsx',obj.outputs_directory),'WriteRowNames',true);
                writetable(house_chamber_votes,sprintf('%s/house_all_chamber_votes.xlsx',obj.outputs_directory),'WriteRowNames',true);
                writetable(house_republicans_chamber_votes,sprintf('%s/house_republicans_chamber_votes.xlsx',obj.outputs_directory),'WriteRowNames',true);
                writetable(house_democrats_chamber_votes,sprintf('%s/house_democrats_chamber_votes.xlsx',obj.outputs_directory),'WriteRowNames',true);
                
                writetable(house_sponsor_chamber_matrix,sprintf('%s/house_all_sponsor_chamber_matrix.xlsx',obj.outputs_directory),'WriteRowNames',true);
                writetable(house_sponsor_chamber_votes,sprintf('%s/house_all_sponsor_chamber_votes.xlsx',obj.outputs_directory),'WriteRowNames',true);
                writetable(house_republicans_chamber_sponsor,sprintf('%s/house_republicans_chamber_sponsor.xlsx',obj.outputs_directory),'WriteRowNames',true);
                writetable(house_democrats_chamber_sponsor,sprintf('%s/house_democrats_chamber_sponsor.xlsx',obj.outputs_directory),'WriteRowNames',true);
                
                writetable(house_committee_matrix,sprintf('%s/house_all_committee_matrix.xlsx',obj.outputs_directory),'WriteRowNames',true);
                writetable(house_committee_votes,sprintf('%s/house_all_committee_votes.xlsx',obj.outputs_directory),'WriteRowNames',true);
                writetable(house_republicans_committee_votes,sprintf('%s/house_republicans_committee_votes.xlsx',obj.outputs_directory),'WriteRowNames',true);
                writetable(house_democrats_committee_votes,sprintf('%s/house_democrats_committee_votes.xlsx',obj.outputs_directory),'WriteRowNames',true);
                
                writetable(house_sponsor_committee_matrix,sprintf('%s/house_all_sponsor_committee_matrix.xlsx',obj.outputs_directory),'WriteRowNames',true);
                writetable(house_sponsor_committee_votes,sprintf('%s/house_all_sponsor_committee_votes.xlsx',obj.outputs_directory),'WriteRowNames',true);
                writetable(house_republicans_committee_sponsor,sprintf('%s/house_republicans_committee_sponsor.xlsx',obj.outputs_directory),'WriteRowNames',true);
                writetable(house_democrats_committee_sponsor,sprintf('%s/house_democrats_committee_sponsor.xlsx',obj.outputs_directory),'WriteRowNames',true);
                
                writetable(house_consistency_matrix,sprintf('%s/house_consistency_matrix.xlsx',obj.outputs_directory),'WriteRowNames',true);
                
                writetable(house_seat_matrix,sprintf('%s/house_seat_matrix.xlsx',obj.outputs_directory),'WriteRowNames',true);
                
                [~,~,~] = rmdir(obj.gif_directory,'s');
                [~,~,~] = rmdir(obj.histogram_directory,'s');
                obj.make_gifs = true;
                obj.make_histograms = true;
            else
                load('saved_data');
            end
            
            % PLOTTING
            % Chamber Vote Data
            tic
            obj.generatePlots(house_chamber_matrix,'House','','Legislators','Legislators','Agreement Score','chamber_all')
            obj.generatePlots(house_republicans_chamber_votes,'House','Republicans','Legislators','Legislators','Agreement Score','chamber_R')
            obj.generatePlots(house_democrats_chamber_votes,'House','Democrats','Legislators','Legislators','Agreement Score','chamber_D')
            toc
            
            % Chamber Sponsorship Data
            tic
            obj.generatePlots(house_sponsor_chamber_matrix,'House','Sponsorship','Sponsors','Legislators','Sponsorship Score','chamber_sponsor_all')
            obj.generatePlots(house_republicans_chamber_sponsor,'House','Republican Sponsorship','Sponsors','Legislators','Sponsorship Score','chamber_sponsor_R')
            obj.generatePlots(house_democrats_chamber_sponsor,'House','Democrat Sponsorship','Sponsors','Legislators','Sponsorship Score','chamber_sponsor_D')
            toc
            
            % Committee Vote Data
            tic
            obj.generatePlots(house_committee_matrix,'House Committee','','Legislators','Legislators','Agreement Score','committee_all')
            obj.generatePlots(house_republicans_committee_votes,'House Committee','Republicans','Legislators','Legislators','Agreement Score','committee_R')
            obj.generatePlots(house_democrats_committee_votes,'House Committee','Democrats','Legislators','Legislators','Agreement Score','committee_D')
            toc
            
            % Committee Sponsorship Data
            tic
            obj.generatePlots(house_sponsor_committee_matrix,'House Committee','Sponsorship','Sponsors','Legislators','Sponsorship Score','committee_sponsor_all')
            obj.generatePlots(house_republicans_committee_sponsor,'House Committee','Republican Sponsorship','Sponsors','Legislators','Sponsorship Score','committee_sponsor_R')
            obj.generatePlots(house_democrats_committee_sponsor,'House Committee','Democrat Sponsorship','Sponsors','Legislators','Sponsorship Score','committee_sponsor_D')
            toc
            
            % Chamber-Committee Consistency
            h = figure();
            hold on
            title('Chamber-Committee Consistency')
            xlabel('Agreement')
            ylabel('Frequency')
            grid on
            histfit(house_consistency_matrix.percentage)
            axis([0 1 0 inf])
            hold off
            saveas(h,sprintf('%s/histogram_chamber_committee_consistency',obj.outputs_directory),'png')
            
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
            
            var_list = who;
            var_list = var_list(~ismember(var_list,'obj'));
            for i = 1:length(var_list)
                assignin('base',var_list{i},eval(var_list{i}));
            end
        end
        
        % There is probably a better, abstractable way to do this but it's a
        % good rough cut way
        function [house_chamber_matrix,house_chamber_votes,...
                house_sponsor_chamber_matrix,house_sponsor_chamber_votes,...
                house_committee_matrix,house_committee_votes,...
                house_sponsor_committee_matrix,house_sponsor_committee_votes,...
                house_consistency_matrix] = processHouseVotes(obj,house_people)
            
            ids = arrayfun(@(x) ['id' num2str(x)], house_people{:,'sponsor_id'}, 'Uniform', 0);
            
            % Initialize the people_matrix and possible_votes matrix
            house_chamber_matrix = obj.createTable(unique(ids),unique(ids),'NaN');
            house_chamber_votes  = obj.createTable(unique(ids),unique(ids),'NaN');
            
            house_committee_matrix = obj.createTable(unique(ids),unique(ids),'NaN');
            house_committee_votes  = obj.createTable(unique(ids),unique(ids),'NaN');
            
            house_sponsor_chamber_matrix = obj.createTable(unique(ids),unique(ids),'NaN');
            house_sponsor_chamber_votes  = obj.createTable(unique(ids),unique(ids),'NaN');
            
            house_sponsor_committee_matrix = obj.createTable(unique(ids),unique(ids),'NaN');
            house_sponsor_committee_votes  = obj.createTable(unique(ids),unique(ids),'NaN');
            
            % Create a table to keep track of the unique sponsorships
            sponsorship_counts = obj.createTable(unique(ids),{'count'},'zero');
            
            % Create a table to keep track of the unique sponsorships
            house_consistency_matrix = obj.createTable(unique(ids),{'consistency' 'opportunity'},'zero');
            
            
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
                if obj.bill_set(i).passed_house >= 0 && obj.bill_set(i).house_data.final_yes_percentage < agreement_threshold
                    bill_count = bill_count + 1;
                    
                    % Sponsor information
                    sponsor_ids = arrayfun(@(x) ['id' num2str(x)], obj.bill_set(i).sponsors, 'Uniform', 0);
                    sponsor_ids = sponsor_ids(ismember(sponsor_ids,ids));
                    
                    % Increase the sponsorship count by one
                    sponsorship_counts{ismember(sponsorship_counts.Properties.RowNames,sponsor_ids),'count'} = sponsorship_counts{ismember(sponsorship_counts.Properties.RowNames,sponsor_ids),'count'} + 1;
                    
                    %%% COMMITTEE INFORMATION - TODO probably can collapse this into a common function with the chamber data
                    committee_votes = 0;
                    for j = 1:length(obj.bill_set(i).house_data.committee_votes)
                        
                        % so it's sort of pointless to do the loop and then
                        % only process the last bill but I want to preserve
                        % the functionality
                        if j ~= length(obj.bill_set(i).house_data.committee_votes)
                            continue
                        end
                        
                        committee_count = committee_count + 1;
                        
                        % Yes/No votes
                        committee_yes_ids = arrayfun(@(x) ['id' num2str(x)], obj.bill_set(i).house_data.committee_votes(j).yes_list, 'Uniform', 0);
                        committee_yes_ids = committee_yes_ids(ismember(committee_yes_ids,ids));
                        
                        committee_no_ids = arrayfun(@(x) ['id' num2str(x)], obj.bill_set(i).house_data.committee_votes(j).no_list, 'Uniform', 0);
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
                        if j ~= length(obj.bill_set(i).house_data.chamber_votes)
                            continue
                        end
                        
                        % Yes/No votes
                        yes_ids = arrayfun(@(x) ['id' num2str(x)], obj.bill_set(i).house_data.chamber_votes(j).yes_list, 'Uniform', 0);
                        yes_ids = yes_ids(ismember(yes_ids,ids));
                        
                        no_ids = arrayfun(@(x) ['id' num2str(x)], obj.bill_set(i).house_data.chamber_votes(j).no_list, 'Uniform', 0);
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
        
        function generatePlots(obj,people_matrix,label_string,specific_label,x_specific,y_specific,z_specific,tag)
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
                
                obj.makeGif(directory,sprintf('%s_%s.gif',label_string,tag),obj.outputs_directory);
            end
            
            if obj.make_histograms
                directory = sprintf(obj.histogram_directory);
                [~, ~, ~] = mkdir(directory);
                obj.generateHistograms(people_matrix,directory,label_string,specific_label,tag)
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
        
        function output = readAllFilesOfSubject(obj,type)
            % initialize the full file list and output matrix
            directory = sprintf('%s/%s/legiscan',obj.data_directory,obj.state);
            list   = dir(directory);
            output = [];
            
            % loop over the available files
            for i = 1:length(list)
                % if the file fits the format we're looking for
                if ~isempty(regexp(list(i).name,'(\d+)-(\d+)_Regular_Session','once'))
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
    end
    
    methods (Static)
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
        
        function [republican_ids, democrat_ids] = processParties(people)
            % Create republican ids
            republican_ids = arrayfun(@(x) ['id' num2str(x)], people{people.party == 1,'sponsor_id'}, 'Uniform', 0);
            
            % Create democrat ids
            democrat_ids   = arrayfun(@(x) ['id' num2str(x)], people{people.party == 0,'sponsor_id'}, 'Uniform', 0);
            
            % Check for bad party IDs
            bad_ids = arrayfun(@(x) ['id' num2str(x)], people{~ismember(people.party,[0 1]),'sponsor_id'}, 'Uniform', 0);
            for i = 1:length(bad_ids)
                fprintf('WARNING: INCORRECT PARTY ID FOR %s\n',bad_ids{i});
            end
        end
        
        function proximity_matrix = processSeatProximity(people)
            % Create the string array list (which allows for referencing variable names
            ids = arrayfun(@(x) ['id' num2str(x)], people{:,'sponsor_id'}, 'Uniform', 0);
            
            x = people{:,'SEATROW'};
            y = people{:,'SEATCOLUMN'};
            dist = sqrt(bsxfun(@minus,x,x').^2 + bsxfun(@minus,y,y').^2);
            
            proximity_matrix = array2table(dist,'RowNames',ids,'VariableNames',ids);
        end
        
        function generateHistograms(people_matrix,save_directory,label_string,specific_label,tag)
            
            rows = people_matrix.Properties.RowNames;
            columns = people_matrix.Properties.VariableNames;
            [~,match_index] = ismember(rows,columns);
            match_index = match_index(match_index > 0);
            
            secondary_plot = nan(1,length(match_index));
            for i = 1:length(match_index)
                secondary_plot(i) = people_matrix{columns{match_index(i)},columns{match_index(i)}};
                people_matrix{columns{match_index(i)},columns{match_index(i)}} = NaN;
            end
            
            main_plot = reshape(people_matrix{:,:},[numel(people_matrix{:,:}),1]);
            
            h = figure();
            hold on
            title(sprintf('%s %s histogram with non-matching legislators',label_string,specific_label))
            xlabel('Agreement')
            ylabel('Frequency')
            grid on
            histfit(main_plot)
            axis([0 1 0 inf])
            hold off
            saveas(h,sprintf('%s/%s_%s_histogram_all',save_directory,label_string,tag),'png')
            
            h = figure();
            hold on
            title(sprintf('%s %s histogram with matching legislators',label_string,specific_label))
            xlabel('Agreement')
            ylabel('Frequency')
            grid on
            histfit(secondary_plot)
            axis([0 1 0 inf])
            hold off
            saveas(h,sprintf('%s/%s_%s_histogram_match',save_directory,label_string,tag),'png')
        end
        
        function [people_matrix] = normalizeVotes(people_matrix,vote_matrix)
            % Element-wise divide. This will take divide each value by the
            % possible value (person-vote total)/(possible vote total)
            people_matrix{:,:} = people_matrix{:,:} ./ vote_matrix{:,:};
        end
        
        function makeGif(file_path,save_name,save_path)
            
            results   = dir(sprintf('%s/*.png',file_path));
            file_name = {results(:).name}';
            save_path = [save_path, '\'];
            loops = 65535;
            delay = 0.2;
            
            h = waitbar(0,'0% done','name','Progress') ;
            for i = 1:length(file_name)
                
                a = imread([file_path,file_name{i}]);
                [M,c_map] = rgb2ind(a,256);
                if i == 1
                    imwrite(M,c_map,[save_path,save_name],'gif','LoopCount',loops,'DelayTime',delay)
                else
                    imwrite(M,c_map,[save_path,save_name],'gif','WriteMode','append','DelayTime',delay)
                end
                waitbar(i/length(file_name),h,[num2str(round(100*i/length(file_name))),'% done']) ;
            end
            close(h);
        end
        
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
        
        function return_table = createTable(rows,columns,type)
            % Switch by type of table being created
            switch type
                case 'NaN'  % initalized with NaNs
                    return_table = array2table(NaN(length(rows),length(columns)),'RowNames',rows,'VariableNames',columns);
                case 'zero' % initialied with zeros
                    return_table = array2table(zeros(length(rows),length(columns)),'RowNames',rows,'VariableNames',columns);
                otherwise   % throw an error
                    error('TABLE TYPE NOT FOUND');
            end
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
    end
end