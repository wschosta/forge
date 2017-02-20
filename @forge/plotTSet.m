function plotTSet(obj,t_set_values,title_text)
% PLOTTSET
% Plots the specific revealed preferences for a given piece of legislation
% at a specific time t

% Get all of the legislator ids
label_text  = t_set_values.Properties.RowNames(~isnan(t_set_values{:,:}));

% Convert the IDs to names
label_text = obj.getSponsorName(label_text);

% Create the plot values based on the name values
plot_values = ceil(t_set_values{:,:}(~isnan(t_set_values{:,:}))*5) - 1 + 0.05;

% Sort the plot values and find the unique values
[plot_values, index] = sort(plot_values);
unique_values        = unique(plot_values);

% Reorganize the label text
label_text           = label_text(index);

% Process out all the label text heights
height = [];
for i = 1:length(unique_values)
    height = [height linspace(0.02,0.98,sum(plot_values == unique_values(i)))]; %#ok<AGROW>
end

% Create the plot
figure('units','normalized','outerposition',[0 0 1 1])
hold on;
title(title_text)
patch([0 1 1 0],[0 0 1 1],[256/256  51/256  51/256]) % No - Red
patch([1 2 2 1],[0 0 1 1],[256/256 153/256  51/256])
patch([2 3 3 2],[0 0 1 1],[256/256 256/256  51/256]) % Swing - Yellow
patch([3 4 4 3],[0 0 1 1],[153/256 256/256  51/256])
patch([4 5 5 4],[0 0 1 1],[ 51/256 256/256  51/256]) % Yes - Green
alpha(0.4)
text(plot_values,height,label_text)
axis([0,5,0,1])
ax = gca;
set(ax,'XTick',[0.5 1.5 2.5 3.5 4.5]);
set(ax,'XTickLabel',{'Strong No','Leaning No','Neutral','Leaning Yes','Strong Yes'});
set(ax,'YTick',[]);
hold off

end