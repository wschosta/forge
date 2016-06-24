function plotRunner(outputs_directory,histogram_directory,chamber,chamber_matrix,republicans_chamber_votes,democrats_chamber_votes,sponsor_chamber_matrix,republicans_chamber_sponsor,democrats_chamber_sponsor,committee_matrix,republicans_committee_votes,democrats_committee_votes,sponsor_committee_matrix,republicans_committee_sponsor,democrats_committee_sponsor,consistency_matrix)
% PLOTRUNNER
% Generate all of the plots for all of the matricies. This allows for
% common functionality across both chambers

% Chamber Vote Data
tic
plot.generatePlots(outputs_directory,histogram_directory,chamber_matrix,chamber,'','Legislators','Legislators','Agreement Score','chamber_all')
plot.generatePlots(outputs_directory,histogram_directory,republicans_chamber_votes,chamber,'Republicans','Legislators','Legislators','Agreement Score','chamber_R')
plot.generatePlots(outputs_directory,histogram_directory,democrats_chamber_votes,chamber,'Democrats','Legislators','Legislators','Agreement Score','chamber_D')

% Chamber Sponsorship Data
plot.generatePlots(outputs_directory,histogram_directory,sponsor_chamber_matrix,chamber,'Sponsorship','Sponsors','Legislators','Sponsorship Score','chamber_sponsor_all')
plot.generatePlots(outputs_directory,histogram_directory,republicans_chamber_sponsor,chamber,'Republican Sponsorship','Sponsors','Legislators','Sponsorship Score','chamber_sponsor_R')
plot.generatePlots(outputs_directory,histogram_directory,democrats_chamber_sponsor,chamber,'Democrat Sponsorship','Sponsors','Legislators','Sponsorship Score','chamber_sponsor_D')

% Committee Vote Data
plot.generatePlots(outputs_directory,histogram_directory,committee_matrix,chamber,'Committee','Legislators','Legislators','Agreement Score','committee_all')
plot.generatePlots(outputs_directory,histogram_directory,republicans_committee_votes,chamber,'Committee Republicans','Legislators','Legislators','Agreement Score','committee_R')
plot.generatePlots(outputs_directory,histogram_directory,democrats_committee_votes,chamber,'Committee Democrats','Legislators','Legislators','Agreement Score','committee_D')

% Committee Sponsorship Data
plot.generatePlots(outputs_directory,histogram_directory,sponsor_committee_matrix,chamber,'Committee Sponsorship','Sponsors','Legislators','Sponsorship Score','committee_sponsor_all')
plot.generatePlots(outputs_directory,histogram_directory,republicans_committee_sponsor,chamber,'Committee Republican Sponsorship','Sponsors','Legislators','Sponsorship Score','committee_sponsor_R')
% plot.generatePlots(outputs_directory,histogram_directory,democrats_committee_sponsor,chamber,'Committee Democrat Sponsorship','Sponsors','Legislators','Sponsorship Score','committee_sponsor_D')

% Chamber-Committee Consistency
if any(~isnan(consistency_matrix.percentage))
    h = figure();
    hold on
    title('Chamber-Committee Consistency')
    xlabel('Agreement')
    ylabel('Frequency')
    grid on
    histfit(consistency_matrix.percentage)
    axis([0 1 0 inf])
    hold off
    saveas(h,sprintf('%s/histogram_%s_committee_consistency',outputs_directory,lower(chamber)),'png')
end
toc

end