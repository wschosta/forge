function generatePlots(show_warnings,outputs_directory,histogram_directory,people_matrix,label_string,specific_label,x_specific,y_specific,z_specific,tag)
% GENERATEPLOTS
% Generate plots for a given matrix. Also includes the option to generate
% histograms. The arugments essentially make it possible to properly label
% each axis.

if ~isempty(people_matrix) && size(people_matrix{:,:},1) > 1 && size(people_matrix{:,:},2) > 1
    
    h = figure();
    hold on
    title(sprintf('%s %s',label_string,specific_label))
    xlabel(x_specific)
    ylabel(y_specific)
    zlabel(z_specific)
    axis square
    grid on
    surf(people_matrix{:,:})
    colormap jet
    caxis([0,1])
    colorbar
    
    % At an angle
    view(3)
    hold off
    saveas(h,sprintf('%s/%s_%s',outputs_directory,upper(label_string(1)),tag),'png')
    
    % Flat
    view(2)
    saveas(h,sprintf('%s/%s_%s_flat',outputs_directory,upper(label_string(1)),tag),'png')
    
    % Generate histograms
    if ~isempty(histogram_directory)
        directory = sprintf(histogram_directory);
        [~, ~, ~] = mkdir(directory);
        plot.generateHistograms(people_matrix,directory,label_string,specific_label,tag)
    end
elseif show_warnings
    fprintf('WARNING: Empty Matrix %s %s\n',label_string, specific_label)
end

end