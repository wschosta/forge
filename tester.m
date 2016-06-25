% test script

% States: IN, CA, OH


fclose all; close all; clc; clear all;

master = tic;

IN_obj = IN();
CA_obj = CA();
OH_obj = OH();

states = {IN_obj, CA_obj, OH_obj};

errors = cell(1,length(states));

for i = 1:length(states)
    close all; fclose all;
    
    state = tic;
    fprintf('\n\n**************************************RUN FOR %s**************************************\n',states{i}.state)
    states{i}.recompute = true;
    states{i}.reprocess = true;
    states{i}.generate_outputs = true;
    states{i}.predict_montecarlo = true;
    states{i}.recompute_montecarlo = true;
    
    states{i}.monte_carlo_number = 100;
    
    try
        states{i}.run();
        
        fprintf('**************************************%s COMPLETE!**************************************\n',states{i}.state)
        toc(state)
    catch e
        warning('ERROR: %s',e.message)
        fprintf('**************************************%s FAILED!**************************************\n',states{i}.state)
        toc(state)
        errors{i} = e;
    end
    
end
close all; fclose all;

fprintf('Failed: %i/%i\n',~isempty(errors),length(errors))

toc(master)