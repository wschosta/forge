function data_storage = loadLearnedMaterials(state)

data_storage = load(sprintf('data/%s/learning_algorithm_data',state));

data_storage = data_storage.data_storage; % it's not pretty but it works

end