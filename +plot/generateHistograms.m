function generateHistograms(people_matrix,save_directory,label_string,specific_label,tag)
% GENERATEHISTOGRAMS
% Create histograms for a given people matrix

% Find matching rows and columns
rows            = people_matrix.Properties.RowNames;
columns         = people_matrix.Properties.VariableNames;
[~,match_index] = ismember(rows,columns);
match_index     = match_index(match_index > 0);

% Do some vodo magic to find matching legislators and eliminate them from
% the main set
secondary_plot = nan(1,length(match_index));
for i = 1:length(match_index)
    secondary_plot(i) = people_matrix{columns{match_index(i)},columns{match_index(i)}};
    people_matrix{columns{match_index(i)},columns{match_index(i)}} = NaN;
end

% Reshape the main plot values
main_plot = reshape(people_matrix{:,:},[numel(people_matrix{:,:}),1]);

% histogram for non-matchin legislators
if ~isempty(main_plot) && sum(~isnan(main_plot)) > 1
    h = figure();
    hold on
    title(sprintf('%s %s histogram with non-matching legislators',label_string,specific_label))
    xlabel('Agreement')
    ylabel('Frequency')
    grid on
    histfit(main_plot)
    axis([0 1 0 inf])
    hold off
    saveas(h,sprintf('%s/%s_%s_histogram_all',save_directory,upper(label_string(1)),tag),'png')
end

% histogram for matching legislators (allows us to see self-consistency)
if ~isempty(secondary_plot) && sum(~isnan(secondary_plot)) > 1
    h = figure();
    hold on
    title(sprintf('%s %s histogram with matching legislators',label_string,specific_label))
    xlabel('Agreement')
    ylabel('Frequency')
    grid on
    histfit(secondary_plot)
    axis([0 1 0 inf])
    hold off
    saveas(h,sprintf('%s/%s_%s_histogram_match',save_directory,upper(label_string(1)),tag),'png')
end
end
