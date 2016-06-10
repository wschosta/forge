classdef IN < forge
    properties
        monte_carlo_number = 100;
    end
    
    methods
        function obj = IN(varargin)
            in = inputParser;
            addOptional(in,'recompute',0,@islogical);
            addOptional(in,'reprocess',0,@islogical);
            addOptional(in,'generateOutputs',0,@islogical);
            parse(in,varargin{:});
            
            obj.state = 'IN';
            obj.senate_size = 50;
            obj.house_size = 100;
            
            obj.recompute = in.Results.recompute;
            obj.reprocess = in.Results.reprocess;
            obj.generate_outputs = in.Results.generateOutputs;
            
            
            obj.data_directory = sprintf('data/%s',obj.state);
            obj.outputs_directory = sprintf('%s/outputs',obj.data_directory);
            obj.gif_directory = sprintf('%s/gif',obj.outputs_directory);
            obj.histogram_directory = sprintf('%s/histograms',obj.outputs_directory);
            
            obj.learning_algorithm_data = la.loadLearnedMaterials(obj.state);
            
            obj.init(); % forge init
        end
        
        function run(obj)
            predict_montecarlo = true;
            predict_outcomes = false;
            
            if exist(sprintf('%s/saved_data.mat',obj.data_directory),'file') ~= 2 || obj.recompute
                
                % CODED SPECIFICALLY FOR THE INDIANA HOUSE AND SENATE.
                % ABSTRACTABLE TO OTHER STATES, WE JUST NEED TO ADJUST THE
                % CHAMBER DESCRIPTIONS

                list      = dir(obj.data_directory);
                list      = regexp({list.name},'people_(\d+).*','once');
                
                house_people  = []; %#ok<NASGU>
                senate_people = [];
                
                if ~any([list{:}])
                    % Takes from the maximum year, could also be set to do
                    % a specific year
                    year_select = max(unique(obj.people.year));
                    
                    if all(ismember({'year','role_id','party_id'},obj.people.Properties.VariableNames))
                        obj.people.party_id = obj.people.party_id - 1;
                        select_people = obj.people(obj.people.year == year_select,:);
                        house_people  = select_people(select_people.role_id == 1,:);
                        senate_people = select_people(select_people.role_id == 2,:);
                    else
                        fprintf('Not able to read people from legiscan data, searching for local data...\n')
                        
                        % If we can't find anything, do a hardcode read
                        % (just so there's something here)
                        house_people = readtable(sprintf('%s/people_2013-2014.csv',obj.data_directory));
                    end
                    
                    clear year_select select_people
                else
                    % Hardcode read that has a bunch of great extra stuff.
                    % That we don't use...
                    house_people = readtable(sprintf('%s/people_2013-2014.csv',obj.data_directory));
                end
                clear list
                
                % ---------------------- House Data -----------------------
                if ~isempty(house_people)
                    
                    [house_chamber_matrix,house_chamber_votes,...
                        house_sponsor_chamber_matrix,house_sponsor_chamber_votes,...
                        house_committee_matrix,house_committee_votes,...
                        house_sponsor_committee_matrix,house_sponsor_committee_votes,...
                        house_consistency_matrix,house_bill_ids]  = obj.processChamberVotes(house_people,'house');
                    
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
                    
                    house_seat_flag = 0;
                    if all(ismember({'SEATROW','SEATCOLUMN'},house_people.Properties.VariableNames))
                        house_seat_flag = 1;
                        house_seat_matrix = obj.processSeatProximity(house_people);
                    end
                end
                
                % --------------------- Senate Data -----------------------
                if ~isempty(senate_people)
                    
                    [senate_chamber_matrix,senate_chamber_votes,...
                        senate_sponsor_chamber_matrix,senate_sponsor_chamber_votes,...
                        senate_committee_matrix,senate_committee_votes,...
                        senate_sponsor_committee_matrix,senate_sponsor_committee_votes,...
                        senate_consistency_matrix,senate_bill_ids]  = obj.processChamberVotes(senate_people,'senate');
                    
                    senate_consistency_matrix.percentage = senate_consistency_matrix.consistency ./ senate_consistency_matrix.opportunity;
                    
                    % Create Republican and Democrat Lists (makes accounting easier)
                    [republican_ids, democrat_ids] = obj.processParties(senate_people);
                    
                    senate_republicans_chamber_votes = senate_chamber_matrix(ismember(senate_chamber_matrix.Properties.RowNames,republican_ids),ismember(senate_chamber_matrix.Properties.VariableNames,republican_ids));
                    senate_democrats_chamber_votes   = senate_chamber_matrix(ismember(senate_chamber_matrix.Properties.RowNames,democrat_ids),ismember(senate_chamber_matrix.Properties.VariableNames,democrat_ids));
                    
                    senate_republicans_chamber_sponsor = senate_sponsor_chamber_matrix(ismember(senate_sponsor_chamber_matrix.Properties.RowNames,republican_ids),ismember(senate_sponsor_chamber_matrix.Properties.VariableNames,republican_ids));
                    senate_democrats_chamber_sponsor   = senate_sponsor_chamber_matrix(ismember(senate_sponsor_chamber_matrix.Properties.RowNames,democrat_ids),ismember(senate_sponsor_chamber_matrix.Properties.VariableNames,democrat_ids));
                    
                    senate_republicans_committee_votes = senate_committee_matrix(ismember(senate_committee_matrix.Properties.RowNames,republican_ids),ismember(senate_committee_matrix.Properties.VariableNames,republican_ids));
                    senate_democrats_committee_votes   = senate_committee_matrix(ismember(senate_committee_matrix.Properties.RowNames,democrat_ids),ismember(senate_committee_matrix.Properties.VariableNames,democrat_ids));
                    
                    senate_republicans_committee_sponsor = senate_sponsor_committee_matrix(ismember(senate_sponsor_committee_matrix.Properties.RowNames,republican_ids),ismember(senate_sponsor_committee_matrix.Properties.VariableNames,republican_ids));
                    senate_democrats_committee_sponsor   = senate_sponsor_committee_matrix(ismember(senate_sponsor_committee_matrix.Properties.RowNames,democrat_ids),ismember(senate_sponsor_committee_matrix.Properties.VariableNames,democrat_ids));
                    
                    senate_seat_flag = 0;
                    if all(ismember({'SEATROW','SEATCOLUMN'},senate_people.Properties.VariableNames))
                        senate_seat_flag = 1;
                        senate_seat_matrix = obj.processSeatProximity(senate_people);
                    end
                end
                
                if obj.generate_outputs
                    
                    if ~isempty(house_people)
                        delete(sprintf('%s/house_*.csv',obj.outputs_directory));
                        
                        writetable(house_chamber_matrix,sprintf('%s/house_all_chamber_matrix.csv',obj.outputs_directory),'WriteRowNames',true);
                        writetable(house_chamber_votes,sprintf('%s/house_all_chamber_votes.csv',obj.outputs_directory),'WriteRowNames',true);
                        writetable(house_republicans_chamber_votes,sprintf('%s/house_republicans_chamber_votes.csv',obj.outputs_directory),'WriteRowNames',true);
                        writetable(house_democrats_chamber_votes,sprintf('%s/house_democrats_chamber_votes.csv',obj.outputs_directory),'WriteRowNames',true);
                        
                        writetable(house_sponsor_chamber_matrix,sprintf('%s/house_all_sponsor_chamber_matrix.csv',obj.outputs_directory),'WriteRowNames',true);
                        writetable(house_sponsor_chamber_votes,sprintf('%s/house_all_sponsor_chamber_votes.csv',obj.outputs_directory),'WriteRowNames',true);
                        writetable(house_republicans_chamber_sponsor,sprintf('%s/house_republicans_chamber_sponsor.csv',obj.outputs_directory),'WriteRowNames',true);
                        writetable(house_democrats_chamber_sponsor,sprintf('%s/house_democrats_chamber_sponsor.csv',obj.outputs_directory),'WriteRowNames',true);
                        
                        writetable(house_committee_matrix,sprintf('%s/house_all_committee_matrix.csv',obj.outputs_directory),'WriteRowNames',true);
                        writetable(house_committee_votes,sprintf('%s/house_all_committee_votes.csv',obj.outputs_directory),'WriteRowNames',true);
                        writetable(house_republicans_committee_votes,sprintf('%s/house_republicans_committee_votes.csv',obj.outputs_directory),'WriteRowNames',true);
                        writetable(house_democrats_committee_votes,sprintf('%s/house_democrats_committee_votes.csv',obj.outputs_directory),'WriteRowNames',true);
                        
                        writetable(house_sponsor_committee_matrix,sprintf('%s/house_all_sponsor_committee_matrix.csv',obj.outputs_directory),'WriteRowNames',true);
                        writetable(house_sponsor_committee_votes,sprintf('%s/house_all_sponsor_committee_votes.csv',obj.outputs_directory),'WriteRowNames',true);
                        writetable(house_republicans_committee_sponsor,sprintf('%s/house_republicans_committee_sponsor.csv',obj.outputs_directory),'WriteRowNames',true);
                        writetable(house_democrats_committee_sponsor,sprintf('%s/house_democrats_committee_sponsor.csv',obj.outputs_directory),'WriteRowNames',true);
                        
                        writetable(house_consistency_matrix,sprintf('%s/house_consistency_matrix.csv',obj.outputs_directory),'WriteRowNames',true);
                        
                        if house_seat_flag
                            writetable(house_seat_matrix,sprintf('%s/house_seat_matrix.csv',obj.outputs_directory),'WriteRowNames',true);
                        end
                    end
                    
                    if ~isempty(senate_people)
                        delete(sprintf('%s/senate_*.csv',obj.outputs_directory));
                        
                        writetable(senate_chamber_matrix,sprintf('%s/senate_all_chamber_matrix.csv',obj.outputs_directory),'WriteRowNames',true);
                        writetable(senate_chamber_votes,sprintf('%s/senate_all_chamber_votes.csv',obj.outputs_directory),'WriteRowNames',true);
                        writetable(senate_republicans_chamber_votes,sprintf('%s/senate_republicans_chamber_votes.csv',obj.outputs_directory),'WriteRowNames',true);
                        writetable(senate_democrats_chamber_votes,sprintf('%s/senate_democrats_chamber_votes.csv',obj.outputs_directory),'WriteRowNames',true);
                        
                        writetable(senate_sponsor_chamber_matrix,sprintf('%s/senate_all_sponsor_chamber_matrix.csv',obj.outputs_directory),'WriteRowNames',true);
                        writetable(senate_sponsor_chamber_votes,sprintf('%s/senate_all_sponsor_chamber_votes.csv',obj.outputs_directory),'WriteRowNames',true);
                        writetable(senate_republicans_chamber_sponsor,sprintf('%s/senate_republicans_chamber_sponsor.csv',obj.outputs_directory),'WriteRowNames',true);
                        writetable(senate_democrats_chamber_sponsor,sprintf('%s/senate_democrats_chamber_sponsor.csv',obj.outputs_directory),'WriteRowNames',true);
                        
                        writetable(senate_committee_matrix,sprintf('%s/senate_all_committee_matrix.csv',obj.outputs_directory),'WriteRowNames',true);
                        writetable(senate_committee_votes,sprintf('%s/senate_all_committee_votes.csv',obj.outputs_directory),'WriteRowNames',true);
                        writetable(senate_republicans_committee_votes,sprintf('%s/senate_republicans_committee_votes.csv',obj.outputs_directory),'WriteRowNames',true);
                        writetable(senate_democrats_committee_votes,sprintf('%s/senate_democrats_committee_votes.csv',obj.outputs_directory),'WriteRowNames',true);
                        
                        writetable(senate_sponsor_committee_matrix,sprintf('%s/senate_all_sponsor_committee_matrix.csv',obj.outputs_directory),'WriteRowNames',true);
                        writetable(senate_sponsor_committee_votes,sprintf('%s/senate_all_sponsor_committee_votes.csv',obj.outputs_directory),'WriteRowNames',true);
                        writetable(senate_republicans_committee_sponsor,sprintf('%s/senate_republicans_committee_sponsor.csv',obj.outputs_directory),'WriteRowNames',true);
                        writetable(senate_democrats_committee_sponsor,sprintf('%s/senate_democrats_committee_sponsor.csv',obj.outputs_directory),'WriteRowNames',true);
                        
                        writetable(senate_consistency_matrix,sprintf('%s/senate_consistency_matrix.csv',obj.outputs_directory),'WriteRowNames',true);
                        
                        if senate_seat_flag
                            writetable(senate_seat_matrix,sprintf('%s/senate_seat_matrix.csv',obj.outputs_directory),'WriteRowNames',true);
                        end
                    end
                    
                    [~,~,~] = rmdir(obj.histogram_directory,'s');
                    obj.make_gifs = true;
                    obj.make_histograms = true;
                end
                
                clear senate_seat_flag house_seat_flag
                
                var_list = who;
                var_list = var_list(~ismember(var_list,'obj'));
                save(sprintf('data/%s/saved_data.mat',obj.state),var_list{:})
                
            else
                load(sprintf('data/%s/saved_data.mat',obj.state));
            end
            
            if obj.generate_outputs
                if ~isempty(house_people)
                    plot.plotRunner(obj.outputs_directory,obj.histogram_directory,'House',house_chamber_matrix,house_republicans_chamber_votes,house_democrats_chamber_votes,house_sponsor_chamber_matrix,house_republicans_chamber_sponsor,house_democrats_chamber_sponsor,house_committee_matrix,house_republicans_committee_votes,house_democrats_committee_votes,house_sponsor_committee_matrix,house_republicans_committee_sponsor,house_democrats_committee_sponsor,house_consistency_matrix)
                end
                
                if ~isempty(senate_people)
                    plot.plotRunner(obj.outputs_directory,obj.histogram_directory,'Senate',senate_chamber_matrix,senate_republicans_chamber_votes,senate_democrats_chamber_votes,senate_sponsor_chamber_matrix,senate_republicans_chamber_sponsor,senate_democrats_chamber_sponsor,senate_committee_matrix,senate_republicans_committee_votes,senate_democrats_committee_votes,senate_sponsor_committee_matrix,senate_republicans_committee_sponsor,senate_democrats_committee_sponsor,senate_consistency_matrix)
                end
            end
            
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
            
            if ~isempty(house_people) && predict_outcomes
                obj.stepwisePrediction(house_bill_ids,house_people,house_sponsor_chamber_matrix,house_consistency_matrix,house_sponsor_committee_matrix,house_chamber_matrix,'House');
            end
            
            if ~isempty(senate_people) && predict_outcomes
                obj.stepwisePrediction(senate_bill_ids,senate_people,senate_sponsor_chamber_matrix,senate_consistency_matrix,senate_sponsor_committee_matrix,house_chamber_matrix,'Senate');
            end
            
            if ~isempty(house_people) && predict_montecarlo
                [house_accuracy_list, house_accuracy_delta, house_legislators_list, house_accuracy_steps_list] = obj.runMonteCarlo(house_bill_ids,house_people,house_sponsor_chamber_matrix,house_consistency_matrix,house_sponsor_committee_matrix,house_chamber_matrix,0,'House',obj.monte_carlo_number); %#ok<NASGU,ASGLU>
            end
            
            if ~isempty(senate_people) && predict_montecarlo
                [senate_accuracy_list, senate_accuracy_delta, senate_legislators_list, senate_accuracy_steps_list] = obj.runMonteCarlo(senate_bill_ids,senate_people,senate_sponsor_chamber_matrix,senate_consistency_matrix,senate_sponsor_committee_matrix,senate_chamber_matrix,0,'Senate',obj.monte_carlo_number); %#ok<NASGU,ASGLU>
            end
            
            var_list = who;
            var_list = var_list(~ismember(var_list,'obj'));
            for i = 1:length(var_list)
                assignin('base',var_list{i},eval(var_list{i}));
            end
        end
    end
end