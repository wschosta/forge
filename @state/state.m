classdef state < forge
    % state
    % Subclass state of the Superclass Forge
    % Used to generate the prediction algorithms and data repositiories
    % for the a specified state. Driven by Legiscan data.
    %
    % SYNTAX:
    % ---------------------------------------------------------------------
    % state_obj = state(state_ID,varargin)
    %
    % REQUIRED PARAMETERS:
    % ---------------------------------------------------------------------
    % "state_ID"
    %   Two character state identifier. Must be a char and correspond to an
    %   entry in the state_properties file.
    %   Syntax: Allowable inputs char
    %
    % AVAILABLE PARAMETERS:
    % ---------------------------------------------------------------------
    % "reprocess"
    %   Flag to reprocess the Legiscan data
    %   Syntax: Allowable inputs logical (true, false, default false)
    %
    % "recompute"
    %   Flag to recompute bill specific data
    %   Syntax: Allowable inputs logical (true, false, default false)
    %
    % "generateOutputs"
    %   Flag to regenerate all system outpus. Note, when this flag is off
    %   it does not prevent *all* outputs from being generated
    %   Syntax: Allowable inputs logical (true, false, default false)
    %
    % "predict_montecarlo"
    %   Flag to execte the bill prediction monte carlo analysis with the
    %   parameter specified monte carlo number - will attempt to load in an
    %   existing matlab for that monte carlo number
    %   Syntax: Allowable inputs logical (true, false, default false)
    %
    % "recompute_montecarlo"
    %   Flag to force a recompute of the monte carlo data for a given
    %   monte carlo size
    %   Syntax: Allowable inputs logical (true, false, default false)
    %
    % USER NOTES AND ADDITIONAL PARAMETERS:
    % ---------------------------------------------------------------------
    % Developed by Walter Schostak and Eric Waltenburg
    %
    % See forge, state_properties
    
    
    properties (Constant)
        
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
        function obj=state(varargin)
            in = inputParser;
            addRequired(in,'state',@ischar)
            addOptional(in,'reprocess',0,@islogical);
            addOptional(in,'recompute',0,@islogical);
            addOptional(in,'generate_outputs',0,@islogical);
            addOptional(in,'predict_montecarlo',0,@islogical);
            addOptional(in,'recompute_montecarlo',0,@islogical);
            addOptional(in,'predict_ELO',0,@islogical);
            addOptional(in,'recompute_ELO',0,@islogical);
            parse(in,varargin{:});
            
            obj.state_ID             = in.Results.state;
            obj.reprocess            = in.Results.reprocess;        % Flag to launch the base forge process to read in the data
            obj.recompute            = in.Results.recompute;        % Flag to launch the state-specific process to generate the matricies
            obj.generate_outputs     = in.Results.generate_outputs; % Flag to generate all of the charts and outputs (note: there are outputs that this does not prevent)
            obj.predict_montecarlo   = in.Results.predict_montecarlo;
            obj.recompute_montecarlo = in.Results.recompute_montecarlo;
            obj.predict_ELO          = in.Results.predict_ELO;
            obj.recompute_ELO        = in.Results.recompute_ELO;
            
            [obj.senate_size, obj.house_size] = obj.state_properties();
            obj.monte_carlo_number = 100; % number of monte carlo iterations
            
            % Storage directroies
            obj.data_directory       = sprintf('data/%s',obj.state_ID);
            obj.outputs_directory    = sprintf('%s/outputs',obj.data_directory);
            obj.prediction_directory = sprintf('%s/prediction_model',obj.data_directory);
            obj.gif_directory        = sprintf('%s/gif',obj.outputs_directory); % not used because gifs are unnecessary (though functionality is generaly preserved)
            obj.elo_directory        = sprintf('%s/elo_model',obj.data_directory);
            obj.histogram_directory = sprintf('%s/histograms',obj.outputs_directory);
            
            if ~isdir(obj.data_directory)
                mkdir(obj.data_directory);
            end
            if ~isdir(obj.outputs_directory)
                mkdir(obj.outputs_directory);
            end
            if ~isdir(obj.prediction_directory)
                mkdir(obj.prediction_directory);
            end
            if ~isdir(obj.gif_directory)
                mkdir(obj.gif_directory);
            end
            if ~isdir(obj.elo_directory)
                mkdir(obj.elo_directory);
            end
            if ~isdir(obj.histogram_directory)
                mkdir(obj.histogram_directory);
            end
            addpath(genpath(obj.data_directory));
            
            % Load the learning algorithm data based on the state specific
            % information TODO does this have to be state specific? Why?
            obj.learning_algorithm_exist = false;
            if obj.learning_algorithm_exist
                obj.learning_algorithm_data = la.loadLearnedMaterials(obj.data_directory);
            end
            
            obj.committee_threshold   = 0.75; % threshold for a vote being a committee vote, 75%
            obj.competitive_threshold = 0.85; % threshold for a bill being competitive, 85%
        end
        
        function run(obj)  
            obj.init(); % forge init
                        
            if exist(sprintf('%s/saved_data.mat',obj.data_directory),'file') ~= 2 || obj.recompute

                list = dir(obj.data_directory);
                list = regexp({list.name},'people_(\d+).*','once');
                
                house_people  = [];
                senate_people = [];

                if ~any([list{:}])
                    % Takes from the maximum year, could also be set to do
                    % a specific year
                    year_select = max(unique(obj.people.year));
                    
                    if all(ismember({'year','role_id','party_id'},obj.people.Properties.VariableNames))
                        obj.people.party_id = obj.people.party_id - 1;
                        select_people       = obj.people(obj.people.year == year_select,:);
                        house_people        = select_people(select_people.role_id == 1,:);
                        senate_people       = select_people(select_people.role_id == 2,:);
                    else
                        warning('Not able to read people from legiscan data, searching for local data...')
                        
                        % If we can't find anything, do a hardcode read
                        % (just so there's something here)
                        house_people = readtable(sprintf('%s/people_2013-2014.csv',obj.data_directory));
                    end
                    
                    clear year_select select_people
                end
                
                % Clean up extra variables
                clear list override
                
                % ---------------------- House Data -----------------------
                % Read in data for the house
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
                % Read in data for the senate
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
                    % Output all the tables for the house
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
                    
                    % Output all the tables for the senate
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
                    
                    % Clean out the histogram directory
                    warning('off','MATLAB:RMDIR:RemovedFromPath')
                    [~,~,~] = rmdir(obj.histogram_directory,'s');
                    warning('on','MATLAB:RMDIR:RemovedFromPath')
                    
                    % Set the flag to generate histograms to be true
                    obj.make_histograms = true;
                end
                
                % Save out all of the generated data with the exception of
                % the IN object
                var_list = who;
                var_list = var_list(~ismember(var_list,'obj'));
                save(sprintf('%s/saved_data.mat',obj.data_directory),var_list{:})
            else
                load(sprintf('%s/saved_data.mat',obj.data_directory));
            end
            
            if obj.generate_outputs
                % Generate all of the plots for the house
                if ~isempty(house_people)
                    plot.plotRunner(obj.outputs_directory,obj.histogram_directory,...
                        'House',house_chamber_matrix,house_republicans_chamber_votes,...
                        house_democrats_chamber_votes,house_sponsor_chamber_matrix,...
                        house_republicans_chamber_sponsor,house_democrats_chamber_sponsor,...
                        house_committee_matrix,house_republicans_committee_votes,...
                        house_democrats_committee_votes,house_sponsor_committee_matrix,...
                        house_republicans_committee_sponsor,house_democrats_committee_sponsor,...
                        house_consistency_matrix)
                end
                
                % Generate all of the plots for the senate
                if ~isempty(senate_people)
                    plot.plotRunner(obj.outputs_directory,obj.histogram_directory,...
                        'Senate',senate_chamber_matrix,senate_republicans_chamber_votes,...
                        senate_democrats_chamber_votes,senate_sponsor_chamber_matrix,...
                        senate_republicans_chamber_sponsor,senate_democrats_chamber_sponsor,...
                        senate_committee_matrix,senate_republicans_committee_votes,...
                        senate_democrats_committee_votes,senate_sponsor_committee_matrix,...
                        senate_republicans_committee_sponsor,senate_democrats_committee_sponsor,...
                        senate_consistency_matrix)
                end
            end
            
            if ~isempty(house_people) && obj.predict_montecarlo
                % Run the montecarlo prediction for the House
                [house_accuracy_list,house_accuracy_delta,house_legislators_list,house_accuracy_steps_list,house_bill_list,house_results_table] = obj.montecarloPrediction(house_bill_ids,house_people,house_sponsor_chamber_matrix,house_consistency_matrix,house_sponsor_committee_matrix,house_chamber_matrix,'House'); %#ok<NASGU,ASGLU>
            end
            
            if ~isempty(senate_people) && obj.predict_montecarlo
                % Run the montecarlo prediction for the Senate
                [senate_accuracy_list,senate_accuracy_delta,senate_legislators_list,senate_accuracy_steps_list,senate_bill_list,senate_results_table] = obj.montecarloPrediction(senate_bill_ids,senate_people,senate_sponsor_chamber_matrix,senate_consistency_matrix,senate_sponsor_committee_matrix,senate_chamber_matrix,'Senate'); %#ok<NASGU,ASGLU>
            end
            
            if ~isempty(house_people) && obj.predict_ELO
                house_elo_score = obj.eloPrediction(house_bill_ids,house_people,house_sponsor_chamber_matrix,house_consistency_matrix,house_sponsor_committee_matrix,house_chamber_matrix,'House'); %#ok<NASGU>
            end
            
            if ~isempty(senate_people) && obj.predict_ELO
                senate_elo_score = obj.eloPrediction(senate_bill_ids,senate_people,senate_sponsor_chamber_matrix,senate_consistency_matrix,senate_sponsor_committee_matrix,senate_chamber_matrix,'Senate'); %#ok<NASGU>
            end
            
            % Save out all of the generated data, with the exception of
            % the IN object to the workspace,
            var_list = who;
            var_list = var_list(~ismember(var_list,'obj'));
            for i = 1:length(var_list)
                assignin('base',var_list{i},eval(var_list{i}));
            end
        end
    end
end