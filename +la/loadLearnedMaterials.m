function data_storage = loadLearnedMaterials(data_directory)
% LOADLEARNEDMATERIALS
% Load the learned materials for a specific state

% Read in the .mat file
data_storage = load(sprintf('%s/learning_algorithm/learning_algorithm_data',data_directory));

% Because of the way in which it was stored...
data_storage = data_storage.data_storage; % it's not pretty but it works

end