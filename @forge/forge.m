classdef forge < handle
    % FORGE
    % Driving superclass for the Forge Project
    % 
    % Developed by Walter Schostak and Eric Waltenburg
    %
    % See also IN
    
    properties
        % the five core types of data to read in
        people
        bills
        history
        rollcalls
        sponsors
        votes
        
        bill_set % the container map
        
        chamber_leadership_key   % key for leadership codes
        committee_key            % key for each committee
        committee_leadership_key % key for committee leadership
        
        sponsor_filter % the minimum bill number for sponsorship
        
        state % the state of interest
        
        make_gifs       % flag to generate gifs
        make_histograms % flag to generate histograms
        
        % storage directories for each information type
        data_directory
        gif_directory
        histogram_directory
        outputs_directory
        
        % information about the size of each chamber 
        senate_size % upper
        house_size  % lower
        
        learning_algorithm_data  % storage for the learning algorithm data
        learning_algorithm_exist = true; % flag to look for existing learning algorithm data, default to true
        % all of the input flags
        generate_outputs
        recompute
        reprocess
        predict_montecarlo
        recompute_montecarlo
        
        monte_carlo_number    % the number of monte carlo iterations
        committee_threshold   % threshold of members to differentiate between committees and the main chamber
        competitive_threshold % number of votes needed for a bill to considered to be competitive
    end
    
    properties (Constant)
        % PARTY_KEY will have issues with non-primary parties
        PARTY_KEY = containers.Map({'0','1','Democrat','Republican'},{'Democrat','Republican',0,1})
        
        % Key to filter vote types
        VOTE_KEY  = containers.Map({'1','2','3','4','yea','nay','absent','no vote'},{'yea','nay','absent','no vote',1,2,3,4});
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
            % Process new information
            if obj.reprocess || exist(sprintf('data/%s/processed_data.mat',obj.state),'file') ~= 2
                
                % Read-in major information groups from the LegiscanData
                bills_create     = obj.readAllFilesOfSubject('bills',obj.state);
                people_create    = obj.readAllFilesOfSubject('people',obj.state);
                rollcalls_create = obj.readAllFilesOfSubject('rollcalls',obj.state);
                
                % Add some additional information to the rollcall data
                rollcalls_create.senate      = strncmpi(rollcalls_create{:,'description'},{'S'},1);
                rollcalls_create.total_vote  = rollcalls_create.yea + rollcalls_create.nay;
                rollcalls_create.yes_percent = rollcalls_create.yea ./ rollcalls_create.total_vote;
                
                % Read-in major information groups from the LegiscanData
                sponsors_create = obj.readAllFilesOfSubject('sponsors',obj.state);
                votes_create    = obj.readAllFilesOfSubject('votes',obj.state);
                history_create  = obj.readAllFilesOfSubject('history',obj.state);
                
                % Create the key map
                bill_set_create = containers.Map('KeyType','int32','ValueType','any');
                
                delete_str = '';
                for i = 1:length(bills_create.bill_id)
                    
                    % Screen updates
                    print_str = sprintf('%i',i);
                    fprintf([delete_str,print_str]);
                    delete_str = repmat(sprintf('\b'),1,length(print_str));

                    % Populate the bill template
                    template = util.templates.getBillTemplate();
                    template(end+1).bill_id = bills_create{i,'bill_id'}; %#ok<AGROW>
                    template.bill_number    = bills_create{i,'bill_number'};
                    template.title          = bills_create{i,'title'};
                    if obj.learning_algorithm_exist
                        template.issue_category = la.classifyBill(template.title,obj.learning_algorithm_data);
                    end
                    template.sponsors = sponsors_create{sponsors_create.bill_id == bills_create{i,'bill_id'},'sponsor_id'};
                    template.history  = sortrows(history_create(bills_create{i,'bill_id'} == history_create.bill_id,:),'date');
                    if ~isempty(template.history)
                        template.date_introduced  = template.history{1,'date'};
                        template.date_last_action = template.history{end,'date'};
                    end
                    template.passed_house  = -1;
                    template.passed_senate = -1;
                    template.passed_both   = -1;
                    template.complete      = 0; % Flag to check whether or not the bill information is complete
                    bill_rollcalls = sortrows(rollcalls_create(rollcalls_create.bill_id == bills_create{i,'bill_id'},:),'date');
                    
                    % Process House data
                    house_rollcalls = bill_rollcalls(bill_rollcalls.senate == 0,:);
                    if ~isempty(house_rollcalls)
                        template.house_data   = obj.processChamberRollcalls(house_rollcalls,votes_create,obj.house_size*obj.committee_threshold);
                        template.passed_house = (template.house_data.final_yes_percentage > 0.5);
                    end
                    
                    % Process Senate data
                    senate_rollcalls = bill_rollcalls(bill_rollcalls.senate == 1,:);
                    if ~isempty(senate_rollcalls)
                        template.senate_data   = obj.processChamberRollcalls(senate_rollcalls,votes_create,obj.senate_size*obj.committee_threshold);
                        template.passed_senate = (template.senate_data.final_yes_percentage > 0.5);
                    end
                    
                    % Check to see if the bill passed both the House and
                    % Senate
                    if (template.passed_senate ~= -1) && (template.passed_house ~= -1)
                        template.passed_both = (template.passed_senate && template.passed_house);
                        template.complete    = 1;
                    end
                    
                    % Store the bill infomration in the containers map
                    bill_set_create(bills_create{i,'bill_id'}) = template;
                end
                print_str = sprintf('Done! %i bills\n',i);
                fprintf([delete_str,print_str]);
                
                save(sprintf('data/%s/processed_data.mat',obj.state),'bills_create','history_create','people_create','rollcalls_create','sponsors_create','votes_create','bill_set_create')
            else % Load the saved information
                load(sprintf('data/%s/processed_data',obj.state))
            end
            
            % Move all of the temporary information into the object
            obj.bills     = bills_create;
            obj.history   = history_create;
            obj.people    = people_create;
            obj.rollcalls = rollcalls_create;
            obj.sponsors  = sponsors_create;
            obj.votes     = votes_create;
            obj.bill_set  = bill_set_create;
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
                        
                        field_match = ~ismember(output.Properties.VariableNames,new_table.Properties.VariableNames);
                        
                        for j = find(field_match)
                            if isa(output.(output.Properties.VariableNames{j})(1),'cell')
                                new_table.(output.Properties.VariableNames{j}) = cell(height(new_table),1);
                            elseif isa(output.(output.Properties.VariableNames{j})(1),'double')
                                new_table.(output.Properties.VariableNames{j}) = NaN(height(new_table),1);
                            else
                                error('DATA TYPE NOT RECOGNIZED!')
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
    end
end