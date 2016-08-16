function plotRunner(outputs_directory,histogram_directory,chamber,chamber_matrix,republicans_chamber_votes,democrats_chamber_votes,sponsor_chamber_matrix,republicans_chamber_sponsor,democrats_chamber_sponsor,committee_matrix,republicans_committee_votes,democrats_committee_votes,sponsor_committee_matrix,republicans_committee_sponsor,democrats_committee_sponsor,consistency_matrix)
% PLOTRUNNER
% Generate all of the plots for all of the matricies. This allows for
% common functionality across both chambers




% Chamber Vote Data
tic
plot.generatePlots(outputs_directory,histogram_directory,chamber_matrix,chamber,'','Legislators','Legislators','Agreement Score','cha_A')
plot.generatePlots(outputs_directory,histogram_directory,republicans_chamber_votes,chamber,'Republicans','Legislators','Legislators','Agreement Score','cha_R')
plot.generatePlots(outputs_directory,histogram_directory,democrats_chamber_votes,chamber,'Democrats','Legislators','Legislators','Agreement Score','cha_D')

% Chamber Sponsorship Data
plot.generatePlots(outputs_directory,histogram_directory,sponsor_chamber_matrix,chamber,'Sponsorship','Sponsors','Legislators','Sponsorship Score','cha_A_s')
plot.generatePlots(outputs_directory,histogram_directory,republicans_chamber_sponsor,chamber,'Republican Sponsorship','Sponsors','Legislators','Sponsorship Score','cha_R_s')
plot.generatePlots(outputs_directory,histogram_directory,democrats_chamber_sponsor,chamber,'Democrat Sponsorship','Sponsors','Legislators','Sponsorship Score','cha_D_s')

% Committee Vote Data
plot.generatePlots(outputs_directory,histogram_directory,committee_matrix,chamber,'Committee','Legislators','Legislators','Agreement Score','com_A')
plot.generatePlots(outputs_directory,histogram_directory,republicans_committee_votes,chamber,'Committee Republicans','Legislators','Legislators','Agreement Score','com_R')
plot.generatePlots(outputs_directory,histogram_directory,democrats_committee_votes,chamber,'Committee Democrats','Legislators','Legislators','Agreement Score','com_D')

% Committee Sponsorship Data
plot.generatePlots(outputs_directory,histogram_directory,sponsor_committee_matrix,chamber,'Committee Sponsorship','Sponsors','Legislators','Sponsorship Score','com_A_s')
plot.generatePlots(outputs_directory,histogram_directory,republicans_committee_sponsor,chamber,'Committee Republican Sponsorship','Sponsors','Legislators','Sponsorship Score','com_R_s')
plot.generatePlots(outputs_directory,histogram_directory,democrats_committee_sponsor,chamber,'Committee Democrat Sponsorship','Sponsors','Legislators','Sponsorship Score','com_D_s')

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
    saveas(h,sprintf('%s/%s_committee_consistency_histogram',outputs_directory,upper(chamber(1))),'png')
end
toc

end