function data_storage = loadLearnedMaterials()

data_storage = load('data\IN\learning_algorithm_data'); % not best practice to hardcode

data_storage = data_storage.data_storage; % it's not pretty but it works

end