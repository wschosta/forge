classdef forge < handle
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
            'title',{},...
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
        history
        rollcalls
        sponsors
        votes
        
        bill_set
        
        party_key = containers.Map([0,1],{'Democrat','Republican'})
        vote_key = containers.Map([1,2,3,4],{'yea','nay','absent','no vote'});
        issue_key = containers.Map([1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16],{...
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
        
        chamber_leadership_key % key for leadership codes
        committee_key
        committee_leadership_key % key for committee leadership
        
        state
        data_directory
        
        gif_directory
        histogram_directory
    end
    
    methods
        function obj = forge(recompute)
            obj.state = 'IN';
            obj.data_directory = 'data';
            
            obj.gif_directory = 'outputs/gif';
            obj.histogram_directory = 'outputs/histograms';
            
            if recompute ||  exist('saved_data.mat','file') ~= 2
                
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
                
                for i = 1:length(bills_create.bill_id)
                    
                    template = obj.bill_template;
                    
                    template(end+1).bill_id = bills_create{i,'bill_id'}; %#ok<AGROW>
                    template.bill_number = bills_create{i,'bill_number'};
                    template.title = bills_create{i,'title'};
                    % template.issue_category = ??? learning algorithm
                    % which takes the title as input?
                    
                    template.sponsors = sponsors_create{sponsors_create.bill_id == bills_create{i,'bill_id'},'sponsor_id'};
                    
                    bill_history = history_create(bills_create{i,'bill_id'} == history_create.bill_id,:);
                    if ~isempty(bill_history)
                        template.history = bill_history;
                        
                        % date introduced?
                        % date of last vote?
                    end
                    
                    bill_rollcalls = rollcalls_create(rollcalls_create.bill_id == bills_create{i,'bill_id'},:);
                    
                    % ------------------ House Data --------------------- %
                    house_rollcalls = bill_rollcalls(bill_rollcalls.senate == 0,:);
                    
                    house_data = {}; %#ok<NASGU>
                    if ~isempty(house_rollcalls)
                        
                        house_data = obj.chamber_template;
                        % house_data.committee_id = ??? how do I set this?
                        
                        committee_votes = {};
                        chamber_votes = {};
                        for j = 1:size(house_rollcalls,1);
                            if house_rollcalls{j,'total_vote'} < 50; %#ok<BDSCA>
                                if isempty(committee_votes)
                                    committee_votes = house_rollcalls(j,:);
                                else
                                    committee_votes = [committee_votes ; house_rollcalls(j,:)];  %#ok<AGROW>
                                end
                            else % full chamber
                                if isempty(chamber_votes)
                                    chamber_votes = house_rollcalls(j,:);
                                else
                                    chamber_votes = [chamber_votes ; house_rollcalls(j,:)];  %#ok<AGROW>
                                end
                            end
                        end

                        house_data(end+1).committee_votes = committee_votes; %#ok<AGROW>
                        house_data.chamber_votes = chamber_votes;
                        if ~isempty(chamber_votes)
                            house_data.final_yes = chamber_votes{end,'yea'};
                            house_data.final_no = chamber_votes{end,'nay'};
                            house_data.final_abstain = chamber_votes{end,'nv'};
                            house_data.final_yes_percentage = chamber_votes{end,'yea'};
                        end
                        
                        template.house_data = house_data;
                        template.passed_house = (house_data.final_yes_percentage > 0.5);
                    end
                    
                    % ------------------ Senate Data -------------------- %
                    senate_rollcalls = bill_rollcalls(bill_rollcalls.senate == 0,:);
                    
                    senate_data = {}; %#ok<NASGU>
                    if ~isempty(senate_rollcalls)
                        senate_data = obj.chamber_template;
                        
                        committee_votes = {};
                        chamber_votes = {};
                        for j = 1:size(senate_rollcalls,1);
                            if senate_rollcalls{j,'total_vote'} < 50; %#ok<BDSCA>
                                if isempty(committee_votes)
                                    committee_votes = senate_rollcalls(j,:);
                                else
                                    committee_votes = [committee_votes ; senate_rollcalls(j,:)];  %#ok<AGROW>
                                end
                            else % full chamber
                                if isempty(chamber_votes)
                                    chamber_votes = senate_rollcalls(j,:);
                                else
                                    chamber_votes = [chamber_votes ; senate_rollcalls(j,:)];  %#ok<AGROW>
                                end
                            end
                        end
                        
                        senate_data(end+1).committee_votes = committee_votes; %#ok<AGROW>
                        senate_data.chamber_votes = chamber_votes;
                        if ~isempty(chamber_votes)
                            senate_data.final_yes = chamber_votes{end,'yea'};
                            senate_data.final_no = chamber_votes{end,'nay'};
                            senate_data.final_abstain = chamber_votes{end,'nv'};
                            senate_data.final_yes_percentage = chamber_votes{end,'yea'};
                        end
                        
                        template.senate_data = senate_data;
                        template.passed_senate = (senate_data.final_yes_percentage > 0.5);
                    end
                    
                    if ~isempty(template.passed_senate) && ~isempty(template.passed_house)
                        template.passed_both = (template.passed_senate && template.passed_house);
                    else
                        template.passed_both = 0;
                    end
                    % signed into law?
                    
%                     if ~isempty(house_data) || ~isempty(senate_data)
%                         keyboard
%                     end
%                     
%                     'house_data',{},...
%                         'passed_house',{},...
%                         'senate_data',{},...
%                         'passed_senate',{},...
%                         'passed_both',{},...
%                         'signed_into_law',{});
%                     
                    %                     chamber_template = struct(...
                    %                         'committee_id',{},... % make sure multiple comittees are possible
                    %                         'committee_votes',{},...
                    %                         'chamber_votes',{},...
                    %                         'passed',{},...
                    %                         'final_yes',{},...
                    %                         'final_no',{},...
                    %                         'final_abstain',{},...
                    %                         'final_yes_percentage',{});
                    
                    
                    %                     'issue_category',{},...
                    %                         'sponsors',{},... % first vs co, also authors
                    %                         'date_introduced',{},...
                    %                         'date_of_last_vote',{},...
                    %                         'house_data',{},...
                    %                         'passed_house',{},...
                    %                         'senate_data',{},...
                    %                         'passed_senate',{},...
                    %                         'passed_both',{},...
                    %                         'signed_into_law',{});
                    %
                    
                    bill_set_create(bills_create{i,'bill_id'}) = template;
                end
                clear chamber_votes committee_votes bill_history bill_rollcalls i j house_data house_rollcalls senate_data senate_rollcalls template
                
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