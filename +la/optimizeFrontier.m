function [accuracy, awv, iwv] = optimizeFrontier(location,robust,max_grid_size,iterations,learning_materials,learning_table,data_storage)

for j = 1:robust
    for k = 1:max_grid_size
        for l = 1:max_grid_size
            
            x = zeros(nIter,1);
            y = zeros(nIter,1);
            z = zeros(nIter,1);
            
            max_awv = k;
            min_awv = k-1;
            max_iwv = l;
            min_iwv = l-1;
            
            for i = 1:iterations
                f = @(x)la.processAlgorithm(x,learning_materials,learning_table,data_storage,1);
                x0 = [min_awv+rand*(max_awv-min_awv),min_iwv+rand*(max_iwv-min_iwv)];
                options = optimoptions('fmincon','Algorithm','sqp','TolFun',1e-8);
                [out,fval] = fmincon(f,x0,[],[],[],[],[min_awv min_iwv],[max_awv max_iwv],[],options);
                fprintf('%5i ||| %8.3f%% || a %10.2f | i %10.2f \n',i,-fval,out(1),out(2));
                x(i) = out(1);
                y(i) = out(2);
                z(i) = -fval;
            end
            
            save(sprintf('learning_algorithm_outputs_%s_%i%i%i',location,j,k,l),'x','y','z')
            
        end
    end
end

master_x = [];
master_y = [];
master_z = [];

files = dir('learning_algorithm_outputs*.mat');
if isempty(files)
    warning('ERROR: FILES NOT FOUND')
    accuracy = [];
    awv = [];
    iwv = [];
else
    
    for i = 1:length(files)
        
        output = load(files(i).name);
        
        if ~isfield(output,'learning_materials')
            
            master_x = [master_x;output.x]; %#ok<AGROW>
            master_y = [master_y;output.y]; %#ok<AGROW>
            master_z = [master_z;output.z]; %#ok<AGROW>
            
            delete(files(i).name);
        else
            continue
        end
    end
    
    t = delaunay(master_x,master_y);
    
    figure()
    hold on; grid on;
    fill3(master_x(t)',master_y(t)',master_z(t)',master_z(t)')
    title('Paraeto surface for learning algorithm weighting')
    xlabel('Additional Word Weights')
    ylabel('Issue Word Weights')
    zlabel('Accuracy (%)')
    colorbar
    grid off;
    saveas(gcf,'paraeto_surface_maximized','png')
    saveas(gcf,'paraeto_surface_maximized','fig')
    
    x = master_x;
    y = master_y;
    z = master_z;
    save(sprintf('learning_algorithm_results_%s',date),'x','y','z','learning_materials','data_storage');
    
    accuracy = max(z);
    
    index = (z == accuracy);
    x_values = x(index);
    y_values = y(index);
    
    sorted_values = sortrows([x_values y_values]');
    
    awv = sorted_values(1,1);
    iwv = sorted_values(1,2);
end
end