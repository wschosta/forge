classdef forge_legacy < handle
    properties
        bills 
        people
        rollcalls
        sponsors
        votes
        
        data_directory = '../../';
        
        state
        save_directory
        
        recompute
        make_gifs
        make_histograms
        
        sponsor_filter_all
        sponsor_filter
    end
    
    methods
        function obj = forge_legacy(recompute,make_gifs,state)
            in = inputParser;
            addRequired(in,'recompute',@islogical);
            addRequired(in,'make_gifs',@islogical);
            addRequired(in,'state',@(x) ischar(x) && length(x) == 2);
            parse(in,recompute,make_gifs,state);
            
            obj.recompute = in.Results.recompute;
            obj.make_gifs = in.Results.make_gifs;
            obj.state     = in.Results.state;
            
            obj.save_directory = sprintf('../../%s',state);
            
            obj.bills     = obj.readAllFilesOfSubject('bills');
            obj.people    = obj.readAllFilesOfSubject('people');
            obj.rollcalls = obj.readAllFilesOfSubject('rollcalls');
            obj.sponsors  = obj.readAllFilesOfSubject('sponsors');
            obj.votes     = obj.readAllFilesOfSubject('votes');
            
            obj.rollcalls.senate = strncmpi(obj.rollcalls{:,'description'},{'S'},1);
            obj.rollcalls.total_vote  = obj.rollcalls.yea + obj.rollcalls.nay;
            obj.rollcalls.yes_percent = obj.rollcalls.yea ./ obj.rollcalls.total_vote;
            
            obj.rollcalls.sponsors = cell(length(obj.rollcalls.bill_id),1);
            for i = 1:length(obj.rollcalls.bill_id)
                obj.rollcalls.sponsors(i) = {obj.sponsors{obj.sponsors.bill_id == obj.rollcalls.bill_id(i),'sponsor_id'}}; %#ok<CCAT1>
            end
            
            obj.bills.sponsors = cell(length(obj.bills.bill_id),1);
            obj.bills.senate_rollcall = nan(length(obj.bills.bill_id),1);
            obj.bills.house_rollcall  = nan(length(obj.bills.bill_id),1);
            obj.bills.vote_both       = zeros(length(obj.bills.bill_id),1);
            for i = 1:length(obj.bills.bill_id)
                obj.bills.sponsors(i) = {obj.sponsors{obj.sponsors.bill_id == obj.bills.bill_id(i),'sponsor_id'}}; %#ok<CCAT1>
                
                rollcall_subset = obj.rollcalls(obj.rollcalls.bill_id == obj.bills{i,'bill_id'},:);
                
                if ~isempty(rollcall_subset)
                    rollcall_subset = sortrows(rollcall_subset,'date');
                    
                    senate = false;
                    if any(rollcall_subset.senate)
                        obj.bills.senate_rollcall(i) = rollcall_subset.roll_call_id(find(rollcall_subset.senate,1,'last'));
                        senate = true;
                    end
                    
                    house = false;
                    if any(~rollcall_subset.senate)
                        obj.bills.house_rollcall(i)  = rollcall_subset.roll_call_id(find(~rollcall_subset.senate,1,'last'));
                        house = true;
                    end
                    
                    if senate && house
                        obj.bills.vote_both(i) = 1;
                    end
                end
            end
            
            obj.make_histograms = true;
        end
        
        function runner(obj)
            
            if exist('saved_data.mat','file') ~= 2 || obj.recompute
                
                % CODED SPECIFICALLY FOR THE INDIANA HOUSE AND SENATE. ABSTRACTABLE TO
                % OTHER STATES, WE JUST NEED TO ADJUST THE CHAMBER DESCTIPTIONS
                
                % Read in the specific 2013-2014 Indiana List
                house_people = readtable(sprintf('%s/%s/people_2013-2014.xlsx',obj.data_directory,obj.state));
                
                % EVERYTHING FROM THIS POINT ON IS WRITTEN FOR A SPECIFIC FOCUS ON THE
                % HOUSE. THE SAME COULD BE DONE WITH THE SENATE
                
                house_rollcall = obj.rollcalls(obj.rollcalls.senate == 0,:);
                
                % LIMITING CONDITIONS
                % Where the Yes percetnage is less than 85%
                house_rollcall = house_rollcall(house_rollcall.yes_percent < 0.85,:);
                % Where the number of votes is greater than 60 (effectively eliminating
                % comittee votes)
                house_rollcall = house_rollcall(house_rollcall.total_vote > 60,:);
                
                % PROCESS DATA
                house_seat_matrix = obj.processSeatProximity(house_people);
                
                [house_people_matrix, house_people_votes] = obj.processAllVotes(house_people,house_rollcall);
                [house_people_matrix] = obj.normalizeVotes(house_people_matrix, house_people_votes);
                
                % New method only looking at the final vote on a bill
                [house_sponsor_matrix, house_sponsor_votes, sponsor_counts] = obj.processSponsorVotesByBill(house_people,house_rollcall);
                [house_sponsor_matrix] = obj.normalizeVotes(house_sponsor_matrix, house_sponsor_votes);
                
                % Old method looking at all votes in the main chamber -
                % includes ammendements
                [house_sponsor_matrix_all, house_sponsor_votes_all, ~] = obj.processSponsorVotes(house_people,house_rollcall);
                [house_sponsor_matrix_all] = obj.normalizeVotes(house_sponsor_matrix_all, house_sponsor_votes_all);
                
                house_people.sponsorship_count = sponsor_counts;
                
                % Create Republican and Democrat Lists (makes accounting easier)
                [republican_ids, democrat_ids] = obj.processParties(house_people);
                 
                house_republicans_vote = house_people_matrix(ismember(house_people_matrix.Properties.RowNames,republican_ids),ismember(house_people_matrix.Properties.VariableNames,republican_ids));
                house_democrats_vote   = house_people_matrix(ismember(house_people_matrix.Properties.RowNames,democrat_ids),ismember(house_people_matrix.Properties.VariableNames,democrat_ids));
                
                house_republicans_sponsor = house_sponsor_matrix(ismember(house_sponsor_matrix.Properties.RowNames,republican_ids),ismember(house_sponsor_matrix.Properties.VariableNames,republican_ids));
                house_democrats_sponsor   = house_sponsor_matrix(ismember(house_sponsor_matrix.Properties.RowNames,democrat_ids),ismember(house_sponsor_matrix.Properties.VariableNames,democrat_ids));
                
                house_republicans_sponsor_all = house_sponsor_matrix_all(ismember(house_sponsor_matrix_all.Properties.RowNames,republican_ids),ismember(house_sponsor_matrix_all.Properties.VariableNames,republican_ids));
                house_democrats_sponsor_all   = house_sponsor_matrix_all(ismember(house_sponsor_matrix_all.Properties.RowNames,democrat_ids),ismember(house_sponsor_matrix_all.Properties.VariableNames,democrat_ids));
                
                
                var_list = who;
                var_list = var_list(~ismember(var_list,'obj'));
                save('saved_data',var_list{:})
                
                delete(sprintf('%s/house_*.xlsx',obj.save_directory));
                
                writetable(house_people_matrix,sprintf('%s/house_people_matrix.xlsx',obj.save_directory),'WriteRowNames',true);
                writetable(house_people_votes,sprintf('%s/house_people_votes.xlsx',obj.save_directory),'WriteRowNames',true);
                writetable(house_republicans_vote,sprintf('%s/house_republicans_vote.xlsx',obj.save_directory),'WriteRowNames',true);
                writetable(house_democrats_vote,sprintf('%s/house_democrats_vote.xlsx',obj.save_directory),'WriteRowNames',true);
                
                writetable(house_sponsor_matrix,sprintf('%s/house_sponsor_matrix.xlsx',obj.save_directory),'WriteRowNames',true);
                writetable(house_sponsor_votes,sprintf('%s/house_sponsor_votes.xlsx',obj.save_directory),'WriteRowNames',true);
                writetable(house_republicans_sponsor,sprintf('%s/house_republicans_sponsor.xlsx',obj.save_directory),'WriteRowNames',true);
                writetable(house_democrats_sponsor,sprintf('%s/house_democrats_sponsor.xlsx',obj.save_directory),'WriteRowNames',true);
                
                writetable(house_sponsor_matrix,sprintf('%s/house_sponsor_matrix_all.xlsx',obj.save_directory),'WriteRowNames',true);
                writetable(house_sponsor_votes,sprintf('%s/house_sponsor_votes_all.xlsx',obj.save_directory),'WriteRowNames',true);
                writetable(house_republicans_sponsor,sprintf('%s/house_republicans_sponsor_all.xlsx',obj.save_directory),'WriteRowNames',true);
                writetable(house_democrats_sponsor,sprintf('%s/house_democrats_sponsor_all.xlsx',obj.save_directory),'WriteRowNames',true);
                
                writetable(house_seat_matrix,sprintf('%s/house_seat_matrix.xlsx',obj.save_directory),'WriteRowNames',true);
                
                [~,~,~] = rmdir('gif','s');
                [~,~,~] = rmdir('histograms','s');
                obj.make_gifs = true;
                obj.make_histograms = true;
            else
                load('saved_data');
            end
            
            % PLOTTING
            % Vote Data
            tic
            obj.generatePlots(house_people_matrix,'House','','Legislators','Legislators','Agreement Score','all')
            obj.generatePlots(house_republicans_vote,'House','Republicans','Legislators','Legislators','Agreement Score','R')
            obj.generatePlots(house_democrats_vote,'House','Democrats','Legislators','Legislators','Agreement Score','D')
            toc
            
            % Sponsorship Data
            tic
            obj.generatePlots(house_sponsor_matrix,'House','Sponsorship','Sponsors','Legislators','Sponsorship Score','sponsor_all')
            obj.generatePlots(house_republicans_sponsor,'House','Republican Sponsorship','Sponsors','Legislators','Sponsorship Score','sponsor_R')
            obj.generatePlots(house_democrats_sponsor,'House','Democrat Sponsorship','Sponsors','Legislators','Sponsorship Score','sponsor_D')
            toc
            
            % All Sponsorship Data
            tic
            obj.generatePlots(house_sponsor_matrix_all,'House','Sponsorship','Sponsors','Legislators','Sponsorship Score','all_sponsor_all')
            obj.generatePlots(house_republicans_sponsor_all,'House','Republican Sponsorship','Sponsors','Legislators','Sponsorship Score','all_sponsor_R')
            obj.generatePlots(house_democrats_sponsor_all,'House','Democrat Sponsorship','Sponsors','Legislators','Sponsorship Score','all_sponsor_D')
            toc
            
            var_list = who;
            var_list = var_list(~ismember(var_list,'obj'));
            for i = 1:length(var_list)
                assignin('base',var_list{i},eval(var_list{i}));
            end
        end
                
        function [people_matrix, possible_votes] = processAllVotes(obj,people,rollcalls)
            % Find the unique roll call ids, this identifies unique votes
            unique_rollcall_ids = unique(rollcalls.roll_call_id);
            
            % Create the string array list (which allows for referencing variable names
            ids = arrayfun(@(x) ['id' num2str(x)], people{:,'sponsor_id'}, 'Uniform', 0);
            
            % Initialize the people_matrix and possible_votes matrix
            people_matrix  = obj.createTable(unique(ids),unique(ids),'NaN');
            possible_votes = obj.createTable(unique(ids),unique(ids),'NaN');
            
            % Now we're going to iterate over all the roll calls
            delete_str = '';
            for i = 1:length(unique_rollcall_ids)

                % Match all the votes based on the roll call id
                specific_vote = obj.votes(obj.votes.roll_call_id == unique_rollcall_ids(i),:);
                
                % Loop over the two vote types under examination
                for j = [1 2] % possible votes - 1=yes 2=no 3=no vote 4=absent/excused
                    % Generate the variable IDs of the relevant voters
                    group_votes_string = obj.filterIDs(specific_vote,people_matrix,j);
                    
                    % Place that information into the people matrix
                    people_matrix = obj.addVotes(people_matrix,group_votes_string,group_votes_string);
                    
                    % Print status message
                    print_str = sprintf('%i %i',i,j);
                    fprintf([delete_str,print_str]);
                    delete_str = repmat(sprintf('\b'),1,length(print_str));
                end
                
                % Total Possible Votes
                % Generate the variable IDs of the relevant voters (yes and no)
                group_votes_string = obj.filterIDs(specific_vote,people_matrix,[1 2]);
                
                % Place that information into possible votes matrix
                possible_votes = obj.addVotes(possible_votes,group_votes_string,group_votes_string);
            end
            print_str = 'Done!\n';
            fprintf([delete_str,print_str]);
            
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
        
        function [people_matrix, possible_votes, sponsorship_counts] = processSponsorVotesByBill(obj,people,rollcalls)
        
            % Create the string array list (which allows for referencing variable names
            ids = arrayfun(@(x) ['id' num2str(x)], people{:,'sponsor_id'}, 'Uniform', 0);
            
            % Initialize the people_matrix and possible_votes matrix
            people_matrix  = obj.createTable(unique(ids),unique(ids),'zero');
            possible_votes = obj.createTable(unique(ids),unique(ids),'zero');
            
            % Create a table to keep track of the unique sponsorships
            sponsorship_counts = array2table(zeros(length(unique(ids)),1),'RowNames',unique(ids),'VariableNames',{'count'});
            
            delete_str = '';
            for i = 1:size(obj.bills,1)
                rollcall_subset = rollcalls(rollcalls.bill_id == obj.bills{i,'bill_id'},:);
                
                if size(rollcall_subset,1) > 0
                    rollcall_subset = sortrows(rollcall_subset,'date');
                    
                    final_bill = rollcall_subset(end,:);
                    
                    % Match all the votes based on the roll call id
                    specific_vote = obj.votes(obj.votes.roll_call_id == final_bill.roll_call_id,:);
                    
                    % Identify the specific sponsors of the bill being voted on
                    sponsor = final_bill.sponsors{:};
                    
                    % Create the sponsor variable names
                    sponsor_ids = arrayfun(@(x) ['id' num2str(x)], sponsor, 'Uniform', 0);
                    sponsor_ids = sponsor_ids(ismember(sponsor_ids,possible_votes.Properties.VariableNames));
                    
                    % If the sponsor ids are empty, we can skip this vote
                    if isempty(sponsor_ids)
                        continue
                    end
                    
                    % Increase the sponsorship count by one
                    sponsorship_counts{ismember(sponsorship_counts.Properties.RowNames,sponsor_ids),'count'} = sponsorship_counts{ismember(sponsorship_counts.Properties.RowNames,sponsor_ids),'count'} + 1;
                    
                    % possible votes - 1=yes 2=no 3=no vote 4=absent/excused
                    % since we're looking at sponsorship agreement we're only looking at
                    % Yes votes
                    group_votes_string = obj.filterIDs(specific_vote,people_matrix,1);
                    
                    % Place that information into possible votes matrix
                    people_matrix = obj.addVotes(people_matrix,group_votes_string,sponsor_ids);
                    
                    % For total possible votes we're looking at each type: yes, no
                    group_votes_string = obj.filterIDs(specific_vote,possible_votes,[1 2]);
                    
                    % Place that information into possible votes matrix
                    possible_votes = obj.addVotes(possible_votes,group_votes_string,sponsor_ids);
                    
                    % Print status message
                    print_str = sprintf('%i',i);
                    fprintf([delete_str,print_str]);
                    delete_str = repmat(sprintf('\b'),1,length(print_str));
                end
            end
            print_str = 'Done!\n';
            fprintf([delete_str,print_str]);
            
            % Clear People who didn't have votes
            
            % Generate the list of row names
            row_names = people_matrix.Properties.RowNames;
            
            % Iterate over the row names
            for i = 1:length(row_names)
                
                % If there are not votes
                if sum(possible_votes{row_names{i},:}) == 0
                    people_matrix(row_names{i},:)  = []; % Clear the people matrix
                    possible_votes(row_names{i},:) = []; % Clar the possible vote matrix
                    fprintf('WARNING: NO VOTES RECORDED FOR %s\n',row_names{i});
                end
            end
            
            % Filter out sponsors that don't meet the minimum vote threshold
            % Create the filter
            obj.sponsor_filter = mean(sponsorship_counts.count) - std(sponsorship_counts.count)/2;
            
            % Generate the list of column names
            column_names = people_matrix.Properties.VariableNames;
            
            % Iterate over the column names
            for i = 1:length(column_names)
                
                % If the value for sponsorship is less than the filter
                if sponsorship_counts{column_names{i},'count'} < obj.sponsor_filter %#ok<BDSCA>
                    people_matrix.(column_names{i})  = []; % Clear the people matrix
                    possible_votes.(column_names{i}) = []; % Clear the possible vote matrix
                    fprintf('WARNING: %s did not meet the vote threshold with only %i\n',column_names{i},sponsorship_counts{i,'count'});
                end
            end
        end
        
        function [people_matrix, possible_votes, sponsorship_counts] = processSponsorVotes(obj,people,rollcalls)
            % Find the unique roll call ids, this identifies unique votes
            unique_rollcall_ids = unique(rollcalls.roll_call_id);
            
            % Create the string array list (which allows for referencing variable names
            ids = arrayfun(@(x) ['id' num2str(x)], people{:,'sponsor_id'}, 'Uniform', 0);
            
            % Initialize the people_matrix and possible_votes matrix
            people_matrix  = obj.createTable(unique(ids),unique(ids),'zero');
            possible_votes = obj.createTable(unique(ids),unique(ids),'zero');
            
            % Create a table to keep track of the unique sponsorships
            sponsorship_counts = array2table(zeros(length(unique(ids)),1),'RowNames',unique(ids),'VariableNames',{'count'});
            
            % Now we're going to iterate over all the roll calls
            delete_str = '';
            for i = 1:length(unique_rollcall_ids)
                % Match all the votes based on the roll call id
                specific_vote = obj.votes(obj.votes.roll_call_id == unique_rollcall_ids(i),:);
                
                % Identify the specific sponsors of the bill being voted on
                sponsor = rollcalls{rollcalls.roll_call_id == unique_rollcall_ids(i),'sponsors'}{:};
                
                % Create the sponsor variable names
                sponsor_ids = arrayfun(@(x) ['id' num2str(x)], sponsor, 'Uniform', 0);
                sponsor_ids = sponsor_ids(ismember(sponsor_ids,possible_votes.Properties.VariableNames));
                
                % If the sponsor ids are empty, we can skip this vote
                if isempty(sponsor_ids)
                    continue
                end
                
                % Increase the sponsorship count by one
                sponsorship_counts{ismember(sponsorship_counts.Properties.RowNames,sponsor_ids),'count'} = sponsorship_counts{ismember(sponsorship_counts.Properties.RowNames,sponsor_ids),'count'} + 1;
                
                % possible votes - 1=yes 2=no 3=no vote 4=absent/excused
                % since we're looking at sponsorship agreement we're only looking at
                % Yes votes
                group_votes_string = obj.filterIDs(specific_vote,people_matrix,1);
                
                % Place that information into possible votes matrix
                people_matrix = obj.addVotes(people_matrix,group_votes_string,sponsor_ids);
                
                % For total possible votes we're looking at each type: yes, no
                group_votes_string = obj.filterIDs(specific_vote,possible_votes,[1 2]);
                
                % Place that information into possible votes matrix
                possible_votes = obj.addVotes(possible_votes,group_votes_string,sponsor_ids);
                
                % Print status message
                print_str = sprintf('%i',i);
                fprintf([delete_str,print_str]);
                delete_str = repmat(sprintf('\b'),1,length(print_str));
            end
            print_str = 'Done!\n';
            fprintf([delete_str,print_str]);
            
            % Clear People who didn't have votes
            
            % Generate the list of row names
            row_names = people_matrix.Properties.RowNames;
            
            % Iterate over the row names
            for i = 1:length(row_names)
                
                % If there are not votes
                if sum(possible_votes{row_names{i},:}) == 0
                    people_matrix(row_names{i},:)  = []; % Clear the people matrix
                    possible_votes(row_names{i},:) = []; % Clar the possible vote matrix
                    fprintf('WARNING: NO VOTES RECORDED FOR %s\n',row_names{i});
                end
            end
            
            % Filter out sponsors that don't meet the minimum vote threshold
            % Create the filter
            obj.sponsor_filter_all = mean(sponsorship_counts.count) - std(sponsorship_counts.count)/2;
            
            % Generate the list of column names
            column_names = people_matrix.Properties.VariableNames;
            
            % Iterate over the column names
            for i = 1:length(column_names)
                
                % If the value for sponsorship is less than the filter
                if sponsorship_counts{column_names{i},'count'} < obj.sponsor_filter_all %#ok<BDSCA>
                    people_matrix.(column_names{i})  = []; % Clear the people matrix
                    possible_votes.(column_names{i}) = []; % Clear the possible vote matrix
                    fprintf('WARNING: %s did not meet the vote threshold with only %i\n',column_names{i},sponsorship_counts{i,'count'});
                end
            end
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
            saveas(h,sprintf('%s/%s_%s',obj.save_directory,label_string,tag),'png')
            
            view(2)
            saveas(h,sprintf('%s/%s_%s_flat',obj.save_directory,label_string,tag),'png')
            
            if obj.make_gifs
                directory = sprintf('%s/gif/%s_%s/',obj.save_directory,label_string,tag);
                [~, ~, ~] = mkdir(directory);
                
                for i = 0:4:360
                    view(i,48)
                    saveas(h,sprintf('%s/%03i',directory,i),'png')
                end
                
                obj.makeGif(directory,sprintf('%s_%s.gif',label_string,tag),obj.save_directory);
            end
            
            if obj.make_histograms
                directory = sprintf('%s/histograms',obj.save_directory);
                [~, ~, ~] = mkdir(directory);
                obj.generateHistograms(people_matrix,directory,label_string,specific_label,tag)
            end
        end
        
        function output = readAllFilesOfSubject(obj,type)
            % initialize the full file list and output matrix
            list   = dir(obj.save_directory);
            output = [];
            
            % loop over the available files
            for i = 1:length(list)
                % if the file fits the format we're looking for
                if ~isempty(regexp(list(i).name,'(\d+)-(\d+)_Regular_Session','once'))
                    if istable(output) % if the output file exists, append
                        output = [output;readtable(sprintf('%s/%s/csv/%s.csv',obj.save_directory,list(i).name,type))]; %#ok<AGROW>
                    else % if it doesn't exist, create it
                        output = readtable(sprintf('%s/%s/csv/%s.csv',obj.save_directory,list(i).name,type));
                    end
                end
            end
        end
        
        function generateHouseBillSubset(obj)
            
            % Generate the list of bills 
            house_bill_idx = find(~isnan(obj.bills.house_rollcall));
            house_rollcall_list = obj.bills.house_rollcall;
            
            total_bill_list = table();
            
            for i = 1:length(house_bill_idx)
                
                
                specific_vote = house_rollcall_list(house_bill_idx(i));
                
                specific_vote_details = obj.rollcalls(obj.rollcalls.roll_call_id == specific_vote,:);

                total_vote_details = [obj.bills(house_bill_idx(i),:) specific_vote_details(:,'date')];
                
                if specific_vote_details.yes_percent < 0.85
                    if isempty(total_bill_list)
                        total_bill_list = total_vote_details;
                    else
                        total_bill_list = [total_bill_list ; total_vote_details]; %#ok<AGROW>
                    end
                end
            end
            
            writetable(total_bill_list,sprintf('%s/bills_meeting_specs.xlsx',obj.save_directory),'WriteRowNames',false);
            
            values = unique(randi(size(obj.bills,1),ceil(0.02*size(obj.bills,1)),1));
            random_subset = obj.bills(values,:);
            
            writetable(random_subset,sprintf('%s/bills_random_subset.xlsx',obj.save_directory),'WriteRowNames',false);
        end
    end
    
    methods (Static)
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
        
        function vote_matrix = addVotes(vote_matrix,row,column)
            % pull out the data from the vote matrix
            temp = vote_matrix{row,column};
            
            % if the value is NaN, make it one (for accounting)
            temp(isnan(vote_matrix{row,column})) = 1;
            
            % if it's not NaN, add one to th existing value
            temp(~isnan(vote_matrix{row,column})) = temp(~isnan(vote_matrix{row,column})) + 1;
            
            % put the data back into the matrix
            vote_matrix{row,column} = temp;
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
        
        function relevant_ids = filterIDs(specific_vote,people_matrix,parameter)
            % Identif the specific list of ids we're going to examine
            relevant_ids = num2cell(specific_vote{ismember(specific_vote.vote,parameter),'sponsor_id'});
            relevant_ids = strcat('id',cellfun(@num2str,relevant_ids,'UniformOutput',false));
            relevant_ids = relevant_ids(ismember(relevant_ids,people_matrix.Properties.VariableNames));
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

    end
end