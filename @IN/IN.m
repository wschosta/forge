classdef IN < forge
    properties (Constant)
        % Indiana Specific issue key
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
        function obj = IN(varargin)
            in = inputParser;
            addOptional(in,'reprocess',0,@islogical);
            addOptional(in,'recompute',0,@islogical);
            addOptional(in,'generateOutputs',0,@islogical);
            addOptional(in,'predict_montecarlo',1,@islogical);
            addOptional(in,'recompute_montecarlo',0,@islogical);
            addOptional(in,'predict_stepwise_outputs',0,@islogical);
            parse(in,varargin{:});
            
            % Flag to launch the base forge process to read in the data
            obj.reprocess        = in.Results.reprocess;
            
            % Flag to launch the state-specific process to generate the
            % matricies
            obj.recompute        = in.Results.recompute;
            
            % Flag to generate all of the charts and outputs (note: there
            % are outputs that this does not prevent
            obj.generate_outputs = in.Results.generateOutputs;
            
            obj.predict_montecarlo       = in.Results.predict_montecarlo;
            obj.recompute_montecarlo     = in.Results.recompute_montecarlo;
            obj.predict_stepwise_outputs = in.Results.predict_stepwise_outputs;
            
            obj.state       = 'IN'; % state
            obj.senate_size = 50;   % number of seats in the Senate (upper chamber)
            obj.house_size  = 100;  % number of seats in the House (lower chamber)
            
            obj.monte_carlo_number = 10000; % number of monte carlo iterations
            
            % Storage directroies
            obj.data_directory      = sprintf('data/%s',obj.state);
            obj.outputs_directory   = sprintf('%s/outputs',obj.data_directory);
            obj.gif_directory       = sprintf('%s/gif',obj.outputs_directory); 
            % not used because gifs are unnecessary (though functionality is generaly preserved)
            obj.histogram_directory = sprintf('%s/histograms',obj.outputs_directory);
            
            % Load the learning algorithm data based on the state specific
            % information
            obj.learning_algorithm_data = la.loadLearnedMaterials(obj.state);
            
            obj.committee_threshold   = 0.75; % threshold for a vote being a committee vote, 75%
            obj.competitive_threshold = 0.85; % threshold for a bill being competitive, 85%
            
            obj.init(); % forge init
        end
        
        function run(obj)
            
            if exist(sprintf('%s/saved_data.mat',obj.data_directory),'file') ~= 2 || obj.recompute
                
                % CODED SPECIFICALLY FOR THE INDIANA HOUSE AND SENATE.
                % ABSTRACTABLE TO OTHER STATES, WE JUST NEED TO ADJUST THE
                % CHAMBER DESCRIPTIONS

                list = dir(obj.data_directory);
                list = regexp({list.name},'people_(\d+).*','once');
                
                house_people  = []; %#ok<NASGU>
                senate_people = [];
                
                override = true;
                if ~any([list{:}]) || override
                    % Takes from the maximum year, could also be set to do
                    % a specific year
                    year_select = max(unique(obj.people.year));
                    
                    if all(ismember({'year','role_id','party_id'},obj.people.Properties.VariableNames))
                        obj.people.party_id = obj.people.party_id - 1;
                        select_people       = obj.people(obj.people.year == year_select,:);
                        house_people        = select_people(select_people.role_id == 1,:);
                        senate_people       = select_people(select_people.role_id == 2,:);
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
                clear list override
                
                % ---------------------- House Data -----------------------
                if ~isempty(house_people)
                    
                    [house_chamber_matrix,house_chamber_votes,...
                        house_sponsor_chamber_matrix,house_sponsor_chamber_votes,...
                        house_committee_matrix,house_committee_votes,...
                        house_sponsor_committee_matrix,house_sponsor_committee_votes,...
                        house_consistency_matrix,house_bill_ids,house_republicans_chamber_votes,...
                        house_democrats_chamber_votes,house_republicans_chamber_sponsor,...
                        house_democrats_chamber_sponsor,house_republicans_committee_votes,...
                        house_democrats_committee_votes,house_democrats_committee_sponsor,...
                        house_republicans_committee_sponsor,house_seat_matrix] = obj.processChamberVotes(house_people,'house');
                    
                end
                
                % --------------------- Senate Data -----------------------
                if ~isempty(senate_people)
                    [senate_chamber_matrix,senate_chamber_votes,...
                        senate_sponsor_chamber_matrix,senate_sponsor_chamber_votes,...
                        senate_committee_matrix,senate_committee_votes,...
                        senate_sponsor_committee_matrix,senate_sponsor_committee_votes,...
                        senate_consistency_matrix,senate_bill_ids,senate_republicans_chamber_votes,...
                        senate_democrats_chamber_votes,senate_republicans_chamber_sponsor,...
                        senate_democrats_chamber_sponsor,senate_republicans_committee_votes,...
                        senate_democrats_committee_votes,senate_democrats_committee_sponsor,...
                        senate_republicans_committee_sponsor,senate_seat_matrix] = obj.processChamberVotes(senate_people,'senate');
                end
                
                if obj.generate_outputs
                    
                    if ~isempty(house_people)
                        obj.writeTables(house_chamber_matrix,house_chamber_votes,...
                            house_republicans_chamber_votes,house_democrats_chamber_votes,...
                            house_sponsor_chamber_matrix,house_sponsor_chamber_votes,...
                            house_republicans_chamber_sponsor,house_democrats_chamber_sponsor,...
                            house_committee_matrix,house_committee_votes,house_republicans_committee_votes,...
                            house_democrats_committee_votes,house_sponsor_committee_matrix,...
                            house_sponsor_committee_votes,house_republicans_committee_sponsor,...
                            house_democrats_committee_sponsor,house_consistency_matrix,...
                            house_seat_matrix,'house'); 
                    end
                    
                    if ~isempty(senate_people)
                        obj.writeTables(senate_chamber_matrix,senate_chamber_votes,...
                            senate_republicans_chamber_votes,senate_democrats_chamber_votes,...
                            senate_sponsor_chamber_matrix,senate_sponsor_chamber_votes,...
                            senate_republicans_chamber_sponsor,senate_democrats_chamber_sponsor,...
                            senate_committee_matrix,senate_committee_votes,senate_republicans_committee_votes,...
                            senate_democrats_committee_votes,senate_sponsor_committee_matrix,...
                            senate_sponsor_committee_votes,senate_republicans_committee_sponsor,...
                            senate_democrats_committee_sponsor,senate_consistency_matrix,...
                            senate_seat_matrix,'senate');
                    end
                    
                    [~,~,~] = rmdir(obj.histogram_directory,'s');
                    obj.make_gifs       = true;
                    obj.make_histograms = true;
                end
                
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
            
            if ~isempty(house_people) && obj.predict_stepwise_outputs
                obj.stepwisePrediction(house_bill_ids,house_people,house_sponsor_chamber_matrix,house_consistency_matrix,house_sponsor_committee_matrix,house_chamber_matrix,'House');
            end
            
            if ~isempty(senate_people) && obj.predict_stepwise_outputs
                obj.stepwisePrediction(senate_bill_ids,senate_people,senate_sponsor_chamber_matrix,senate_consistency_matrix,senate_sponsor_committee_matrix,house_chamber_matrix,'Senate');
            end
            
            if ~isempty(house_people) && obj.predict_montecarlo
                [house_accuracy_list,house_accuracy_delta,house_legislators_list,house_accuracy_steps_list,house_bill_list,house_results_table] = obj.montecarloPrediction(house_bill_ids,house_people,house_sponsor_chamber_matrix,house_consistency_matrix,house_sponsor_committee_matrix,house_chamber_matrix,'House'); %#ok<NASGU,ASGLU>
            end
            
            if ~isempty(senate_people) && obj.predict_montecarlo
                [senate_accuracy_list,senate_accuracy_delta,senate_legislators_list,senate_accuracy_steps_list,senate_bill_list,senate_results_table] = obj.montecarloPrediction(senate_bill_ids,senate_people,senate_sponsor_chamber_matrix,senate_consistency_matrix,senate_sponsor_committee_matrix,senate_chamber_matrix,'Senate'); %#ok<NASGU,ASGLU>
            end
            
            var_list = who;
            var_list = var_list(~ismember(var_list,'obj'));
            for i = 1:length(var_list)
                assignin('base',var_list{i},eval(var_list{i}));
            end
        end
    end
end