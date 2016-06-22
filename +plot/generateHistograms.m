function generateHistograms(people_matrix,save_directory,label_string,specific_label,tag)
% TODO comments

rows = people_matrix.Properties.RowNames;
columns = people_matrix.Properties.VariableNames;
[~,match_index] = ismember(rows,columns);
match_index = match_index(match_index > 0);

secondary_plot = nan(1,length(match_index));
for i = 1:length(match_index)
    secondary_plot(i) = people_matrix{columns{match_index(i)},columns{match_index(i)}};
    people_matrix{columns{match_index(i)},columns{match_index(i)}} = NaN;
end

main_plot = reshape(people_matrix{:,:},[numel(people_matrix{:,:}),1]);

if ~isempty(main_plot)
    h = figure();
    hold on
    title(sprintf('%s %s histogram with non-matching legislators',label_string,specific_label))
    xlabel('Agreement')
    ylabel('Frequency')
    grid on
    histfit(main_plot)
    axis([0 1 0 inf])
    hold off
    saveas(h,sprintf('%s/%s_%s_histogram_all',save_directory,label_string,tag),'png')
end

if ~isempty(secondary_plot)
    h = figure();
    hold on
    title(sprintf('%s %s histogram with matching legislators',label_string,specific_label))
    xlabel('Agreement')
    ylabel('Frequency')
    grid on
    histfit(secondary_plot)
    axis([0 1 0 inf])
    hold off
    saveas(h,sprintf('%s/%s_%s_histogram_match',save_directory,label_string,tag),'png')
end
end
