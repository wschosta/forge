classdef CA < state
    % CA
    % Subclass California of the Superclass Forge
    % Used to generate the prediction algorithms and data repositiories
    % for the state of California. Driven by Legiscan data.
    %
    % SYNTAX:
    % ---------------------------------------------------------------------
    % CA_obj = CA(varargin)
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
    % See forge, state
        
    methods
        function obj = CA(varargin)
            in = inputParser;
            addOptional(in,'reprocess',0,@islogical);
            addOptional(in,'recompute',0,@islogical);
            addOptional(in,'generate_outputs',0,@islogical);
            addOptional(in,'predict_montecarlo',0,@islogical);
            addOptional(in,'recompute_montecarlo',0,@islogical);
            parse(in,varargin{:});
            
            obj.reprocess            = in.Results.reprocess;        % Flag to launch the base forge process to read in the data
            obj.recompute            = in.Results.recompute;        % Flag to launch the state-specific process to generate the matricies
            obj.generate_outputs     = in.Results.generate_outputs; % Flag to generate all of the charts and outputs (note: there are outputs that this does not prevent)
            obj.predict_montecarlo   = in.Results.predict_montecarlo;
            obj.recompute_montecarlo = in.Results.recompute_montecarlo;
            
            obj.state       = 'CA'; % state
            obj.senate_size = 40;   % number of seats in the Senate (upper chamber)
            obj.house_size  = 88;   % number of seats in the House (lower chamber)
            
            obj.monte_carlo_number = 100; % number of monte carlo iterations
            
            % Storage directroies
            obj.data_directory       = sprintf('data/%s',obj.state);
            obj.outputs_directory    = sprintf('%s/outputs',obj.data_directory);
            obj.prediction_directory = sprintf('%s/prediction_model',obj.data_directory);
            obj.gif_directory        = sprintf('%s/gif',obj.outputs_directory);
            
            % not used because gifs are unnecessary (though functionality is generaly preserved)
            obj.histogram_directory = sprintf('%s/histograms',obj.outputs_directory);
            
            % Load the learning algorithm data based on the state specific
            % information TODO does this have to be state specific? Why?
            obj.learning_algorithm_exist = false;
            if obj.learning_algorithm_exist
                obj.learning_algorithm_data = la.loadLearnedMaterials(obj.data_directory);
            end
            
            obj.committee_threshold   = 0.75; % threshold for a vote being a committee vote, 75%
            obj.competitive_threshold = 0.85; % threshold for a bill being competitive, 85%
        end
    end
end