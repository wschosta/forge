% test script

% States: IN, OR, WI

fclose all; close all; clc; clear all;

% try
%     fprintf('**************************************LA MASTER ANALYSIS**************************************\n')
%     
%     la_time = tic;
%     
%     la.main()
%     
%     fprintf('**************************************LA COMPLETE!**************************************\n')
%     toc(la_stime)
% catch e
%     warning('ERROR: %s',e.message)
%     fprintf('**************************************LA FAILED!**************************************\n')
%     toc(la_time)
%     la_errors = e;
% end

master = tic;

states = {'WI' 'OR' 'IN'};

errors = {};

for i = 1:length(states)
    close all; fclose all;
    
    state_time = tic;
    fprintf('\n\n**************************************RUN FOR %s**************************************\n',states{i})
    
    a = state(states{i});
    
    a.recompute = true;
    a.reprocess = true;
    a.generate_outputs     = true;
    a.predict_montecarlo   = true;
    a.recompute_montecarlo = true;
    a.predict_ELO          = true;
    a.recompute_ELO        = true;
    
    try
        a.run();
        
        fprintf('**************************************%s COMPLETE!**************************************\n',states{i})
        toc(state_time)
    catch e
        warning('ERROR: %s',e.message)
        fprintf('**************************************%s FAILED!**************************************\n',states{i})
        toc(state_time)
        errors{end+1} = e; %#ok<SAGROW>
    end
end

close all; fclose all;

fprintf('Failed: %i/%i\n',~isempty(errors),length(states))

toc(master)