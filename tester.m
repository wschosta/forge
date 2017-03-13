% test script

% States: IN, CA, OH

fclose all; close all; clc; clear all;

dbstop if error

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

states = {'OR' 'WI' 'IN' };

errors = {};

monte_carlo_number_list = [5000];

for j = 1:length(monte_carlo_number_list)
    for i = 1:length(states)
        close all; fclose all;
        
        state_time = tic;
        fprintf('\n\n**************************************RUN FOR %s**************************************\n',states{i})
        
        a = state(states{i});
        
        a.recompute = false;
        a.reprocess = false;
        a.generate_outputs     = false;
        a.predict_montecarlo   = false;
        a.recompute_montecarlo = false;
        a.predict_ELO          = true;
        a.recompute_ELO        = true;
        
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