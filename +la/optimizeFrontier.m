function [accuracy, awv, iwv] = optimizeFrontier(location,robust,max_grid_size,iterations,learning_materials,learning_table,data_storage,data_location,state)
% OPTIMIZEFRONTIER
% Funciton to do optimziation the tradeoffs between the issue word value
% (iwv) and additonal word value (awv)

% Generate a random number for salting - this may not be necessary but
% should create entropy across different computers for distributed
% computing
random_salt = randi(10000000,1,1);

for j = 1:robust % multiplicative factor for all grid points
    for k = 1:max_grid_size % awv grid points
        for l = 1:max_grid_size % iwv grid points
            
            % Initialize arrays 
            awv_list      = zeros(iterations,1);
            iwv_list      = zeros(iterations,1);
            accuracy_list = zeros(iterations,1);
            
            % Find the minimum and maximum awv and iwv values for a given
            % grid square
            max_awv = k;
            min_awv = k-1;
            max_iwv = l;
            min_iwv = l-1;
            
            % Iterate over that grid square (sampling)
            for i = 1:iterations
                % Set a new random seed
                util.setRandSeed((j-1)*robust*max_grid_size*max_grid_size*iterations+(k-1)*max_grid_size*max_grid_size*iterations+(l-1)*max_grid_size*iterations+i+random_salt)
                
                % Create the function handle
                f           = @(x)la.processAlgorithm(x,learning_materials,learning_table,data_storage,1);
                
                % Create the initial value - with some randomized jitter
                x0         = [min_awv+rand*(max_awv-min_awv),min_iwv+rand*(max_iwv-min_iwv)];
                
                % Set the options
                options    = optimoptions('fmincon','Algorithm','sqp','TolFun',1e-8);
                
                % Execute fmincon
                [out,fval] = fmincon(f,x0,[],[],[],[],[min_awv min_iwv],[max_awv max_iwv],[],options);
                
                % Output the results to the screen
                fprintf('%5i ||| %8.3f%% || a %10.2f | i %10.2f \n',i,-fval,out(1),out(2));
                
                % Save the results in the appropriate lists
                awv_list(i)      = out(1);
                iwv_list(i)      = out(2);
                accuracy_list(i) = -fval;
            end
            
            % Save the iterated set to a file - allows for checkpointing
            save(sprintf('%s\%s\learning_algorithm\tmp\learning_algorithm_outputs_%s_%i%i%i',data_location,state,location,j,k,l),'awv_list','iwv_list','accuracy_list')
            
        end
    end
end

% Initialize the master arrays
master_awv      = [];
master_iwv      = [];
master_accuracy = [];

% Search for output files
files = dir(sprintf('%s\%s\learning_algorithm\tmp\learning_algorithm_outputs_*_*.mat',data_location,state));

if isempty(files)
    % Print a warning message
    warning('ERROR: FILES NOT FOUND')
    
    % Set the outputs to empty
    accuracy = [];
    awv      = [];
    iwv      = [];
else
    % Iterate over all the files
    for i = 1:length(files)
        
        % Load the file
        output = load(files(i).name);
        
        % If it does not contain the field "learning_materials" it's the
        % processed data and what we're looking for
        if ~isfield(output,'learning_materials')
            
            % Add the outputs to the master lists
            master_awv      = [master_awv ; output.awv_list]; %#ok<AGROW>
            master_iwv      = [master_iwv ; output.iwv_list]; %#ok<AGROW>
            master_accuracy = [master_accuracy ; output.accuracy_list]; %#ok<AGROW>
            
            % Deletion of constituent files under evaluation
            %             delete(files(i).name);
        else
            continue
        end
    end
    
    % Generate the coloration and sorting based on the delaunay
    % triangulation
    t = delaunay(master_awv,master_iwv);
    
    % Geneare the figure
    figure()
    hold on; grid on;
    fill3(master_awv(t)',master_iwv(t)',master_accuracy(t)',master_accuracy(t)')
    title('Paraeto surface for learning algorithm weighting')
    xlabel('Additional Word Weights')
    ylabel('Issue Word Weights')
    zlabel('Accuracy (%)')
    colorbar
    grid off; hold off;
    
    % Save the results
    saveas(gcf,sprintf('%s\%s\learning_algorithm\paraeto_surface_maximized',data_location,state),'png')
    saveas(gcf,sprintf('%s\%s\learning_algorithm\paraeto_surface_maximized',data_location,state),'fig')
    
    % Save the data into a master .mat file
    awv_list      = master_awv;
    iwv_list      = master_iwv;
    accuracy_list = master_accuracy;
    save(sprintf('%s\%s\learning_algorithm\learning_algorithm_results_%s',data_location,state,date),'awv_list','iwv_list','accuracy_list','learning_materials','data_storage');
    
    % Find the maximum accuracy
    accuracy = max(accuracy_list);
    
    % Sort the awv and iwv lists based on the accuracy
    index = (accuracy_list == accuracy);
    awv_list = awv_list(index);
    iwv_list = iwv_list(index);
    
    % Sort the rows to find the minimum values of the coeficients
    sorted_values = sortrows([awv_list iwv_list]');
    
    % Pull out those values to be returned
    awv = sorted_values(1,1);
    iwv = sorted_values(1,2);
end

end