% test script

% States: IN, CA, OH

fclose all; close all; clc; clear all;

master = tic;

IN_obj = IN();
CA_obj = CA();
OH_obj = OH();

states = {IN_obj CA_obj OH_obj};

errors = {};

monte_carlo_number_list = [10];% 100 1000 10000 50000 100000];

for j = 1:length(monte_carlo_number_list)
    for i = 1:length(states)
        close all; fclose all;
        
        state = tic;
        fprintf('\n\n**************************************RUN FOR %s**************************************\n',states{i}.state)
        states{i}.recompute = false;
        states{i}.reprocess = false;
        states{i}.generate_outputs = false;
        states{i}.predict_montecarlo = false;
        states{i}.recompute_montecarlo = false;
        
        states{i}.monte_carlo_number = monte_carlo_number_list(j);
        
        try
            states{i}.run();
            
            fprintf('**************************************%s COMPLETE!**************************************\n',states{i}.state)
            toc(state)
        catch e
            warning('ERROR: %s',e.message)
            fprintf('**************************************%s FAILED!**************************************\n',states{i}.state)
            toc(state)
            errors{end+1} = e; %#ok<SAGROW>
        end
    end
end
close all; fclose all;

fprintf('Failed: %i/%i\n',~isempty(errors),length(states)*length(monte_carlo_number_list))

toc(master)