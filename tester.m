% test script
clear all; clc; close all; 
a = IN('recompute_montecarlo',true); 
list = [10000]; 

for i = list
a.monte_carlo_number = i;
a.run()
fprintf('%i done!\n',a.monte_carlo_number)
end


% clear all; clc; close all; a = CA('recompute',false,'reprocess',false,'generateOutputs',false,'predict_montecarlo',true,'recompute_montecarlo',true); a.run()