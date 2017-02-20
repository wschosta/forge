function writeTables(obj,chamber_matrix,chamber_votes,republicans_chamber_votes,democrats_chamber_votes,sponsor_chamber_matrix,sponsor_chamber_votes,republicans_chamber_sponsor,democrats_chamber_sponsor,committee_matrix,committee_votes,republicans_committee_votes,democrats_committee_votes,sponsor_committee_matrix,sponsor_committee_votes,republicans_committee_sponsor,democrats_committee_sponsor,consistency_matrix,seat_matrix,chamber)
% WRITETABLES
% Export all the information for one chamber to .csv files

% Delete the existing files
delete(sprintf('%s/%s_*.csv',obj.outputs_directory,chamber));

chamber = upper(chamber(1));

% Write the chamber information
if ~isempty(chamber_matrix) && ~isempty(chamber_votes)
    writetable(chamber_matrix,sprintf('%s/%s_cha_A_matrix.csv',obj.outputs_directory,chamber),'WriteRowNames',true);
    writetable(chamber_votes,sprintf('%s/%s_cha_A_votes.csv',obj.outputs_directory,chamber),'WriteRowNames',true);
    writetable(republicans_chamber_votes,sprintf('%s/%s_cha_R_votes.csv',obj.outputs_directory,chamber),'WriteRowNames',true);
    writetable(democrats_chamber_votes,sprintf('%s/%s_cha_D_votes.csv',obj.outputs_directory,chamber),'WriteRowNames',true);
    
    % Write the chamber sponsor information
    writetable(sponsor_chamber_matrix,sprintf('%s/%s_cha_A_s_matrix.csv',obj.outputs_directory,chamber),'WriteRowNames',true);
    writetable(sponsor_chamber_votes,sprintf('%s/%s_cha_A_s_votes.csv',obj.outputs_directory,chamber),'WriteRowNames',true);
    writetable(republicans_chamber_sponsor,sprintf('%s/%s_cha_R_s_votes.csv',obj.outputs_directory,chamber),'WriteRowNames',true);
    writetable(democrats_chamber_sponsor,sprintf('%s/%s_cha_D_s_votes.csv',obj.outputs_directory,chamber),'WriteRowNames',true);
end

% Write the committee information
if ~isempty(committee_matrix) && ~isempty(committee_votes)
    writetable(committee_matrix,sprintf('%s/%s_com_A_matrix.csv',obj.outputs_directory,chamber),'WriteRowNames',true);
    writetable(committee_votes,sprintf('%s/%s_com_A_votes.csv',obj.outputs_directory,chamber),'WriteRowNames',true);
    writetable(republicans_committee_votes,sprintf('%s/%s_com_R_votes.csv',obj.outputs_directory,chamber),'WriteRowNames',true);
    writetable(democrats_committee_votes,sprintf('%s/%s_com_D_votes.csv',obj.outputs_directory,chamber),'WriteRowNames',true);
    
    % Write the committee sponsor information
    writetable(sponsor_committee_matrix,sprintf('%s/%s_com_A_s_matrix.csv',obj.outputs_directory,chamber),'WriteRowNames',true);
    writetable(sponsor_committee_votes,sprintf('%s/%s_com_A_s_votes.csv',obj.outputs_directory,chamber),'WriteRowNames',true);
    writetable(republicans_committee_sponsor,sprintf('%s/%s_com_R_s_matrix.csv',obj.outputs_directory,chamber),'WriteRowNames',true);
    writetable(democrats_committee_sponsor,sprintf('%s/%s_com_D_s_matrix.csv',obj.outputs_directory,chamber),'WriteRowNames',true);
    
    % Write the chamber-committee consistency matrix
    writetable(consistency_matrix,sprintf('%s/%s_consistency_matrix.csv',obj.outputs_directory,chamber),'WriteRowNames',true);
end

if ~isempty(seat_matrix)
    % if it exists, write the seat matrix
    writetable(seat_matrix,sprintf('%s/%s_seat_matrix.csv',obj.outputs_directory,chamber),'WriteRowNames',true);
end

end