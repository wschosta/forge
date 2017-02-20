function [data_storage,la_exist] = loadLearnedMaterials()
% LOADLEARNEDMATERIALS
% Load the learned materials for a specific state

% Read in the .mat file
la_exist = (exist('+la\learning_algorithm_data.mat','file') == 2);
data_storage = [];

if la_exist
    load('+la\learning_algorithm_data');
end

end