function data_storage = loadLearnedMaterials(state)
% LOADLEARNEDMATERIALS
% Load the learned materials for a specific state

% Read in the .mat file
data_storage = load(sprintf('data/%s/learning_algorithm_data',state));

% Because of the way in which it was stored...
data_storage = data_storage.data_storage; % it's not pretty but it works

end