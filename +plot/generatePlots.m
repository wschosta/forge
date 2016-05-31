function generatePlots(outputs_directory,histogram_directory,people_matrix,label_string,specific_label,x_specific,y_specific,z_specific,tag)

if ~isempty(people_matrix)
    h = figure();
    hold on
    title(sprintf('%s %s',label_string,specific_label))
    xlabel(x_specific)
    ylabel(y_specific)
    zlabel(z_specific)
    axis square
    grid on
    surf(people_matrix{:,:})
    colorbar
    view(3)
    hold off
    saveas(h,sprintf('%s/%s_%s',outputs_directory,label_string,tag),'png')
    
    view(2)
    saveas(h,sprintf('%s/%s_%s_flat',outputs_directory,label_string,tag),'png')
    
    if ~isempty(histogram_directory)
        directory = sprintf(histogram_directory);
        [~, ~, ~] = mkdir(directory);
        plot.generateHistograms(people_matrix,directory,label_string,specific_label,tag)
    end
end

end