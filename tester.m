% test script

% States: IN, CA, OH

fclose all; close all; clc; clear all;

master = tic;

states = {'OR' 'VT' 'WI' 'IN'};

errors = {};

monte_carlo_number_list = [10];% 100 1000 10000 50000 100000];

for j = 1:length(monte_carlo_number_list)
    for i = 1:length(states)
        close all; fclose all;
        
        state_time = tic;
        fprintf('\n\n**************************************RUN FOR %s**************************************\n',states{i})
        
        a = state(states{i});
        
        a.recompute = true;
        a.reprocess = true;
        a.generate_outputs = true;
        a.predict_montecarlo = false;
        a.recompute_montecarlo = false;
        
        a.monte_carlo_number = monte_carlo_number_list(j);
        
%         try
            a.run();
            
            fprintf('**************************************%s COMPLETE!**************************************\n',states{i})
            toc(state_time)
%         catch e
%             warning('ERROR: %s',e.message)
%             fprintf('**************************************%s FAILED!**************************************\n',states{i})
%             toc(state_time)
%             errors{end+1} = e; %#ok<SAGROW>
%         end
    end
end
close all; fclose all;

fprintf('Failed: %i/%i\n',~isempty(errors),length(states)*length(monte_carlo_number_list))

toc(master)