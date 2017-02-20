function outputBillInformation(obj,chamber_bill_ids,chamber,specific_label,specific_tag)
% OUTPUTBILLINFORMATION
% Function to output a table of relevant information for a specific list of
% bill IDs on a per chamber basis

% Initialie all of the lists to the appropriate size
sponsor_list   = zeros(1,length(chamber_bill_ids));
committee_list = zeros(1,length(chamber_bill_ids));

% Create the chamber data handle, allows for dynamic referencing
chamber_data = sprintf('%s_data',chamber);

% Initialize the competitive_bills table with the appropriate columns
competitive_bills = cell2table(cell(length(senate_bill_ids),8),'VariableNames',{'bill_id' 'bill_number' 'title' 'introduced' 'last_action' 'issue_id','sponsors','committee_members'});

% Iterate over all of the bill ids
for i = 1:length(chamber_bill_ids)
    % Pull out relevatn information
    competitive_bills{i,'bill_id'}     = {obj.bill_set(chamber_bill_ids(i)).bill_id};
    competitive_bills{i,'bill_number'} = obj.bill_set(chamber_bill_ids(i)).bill_number;
    competitive_bills{i,'title'}       = obj.bill_set(chamber_bill_ids(i)).title;
    competitive_bills{i,'introduced'}  = obj.bill_set(chamber_bill_ids(i)).date_introduced;
    competitive_bills{i,'last_action'} = obj.bill_set(chamber_bill_ids(i)).date_last_action;
    competitive_bills{i,'issue_id'}    = {obj.ISSUE_KEY(obj.bill_set(chamber_bill_ids(i)).issue_category)};
    
    % Find all sponsor names
    sponsors_names = obj.getSponsorName(obj.bill_set(chamber_bill_ids(i)).sponsors(1));
    for j = 2:length(obj.bill_set(chamber_bill_ids(i)).sponsors)
        sponsors_names = [sponsors_names ',' obj.getSponsorName(obj.bill_set(chamber_bill_ids(i)).sponsors(j))]; %#ok<AGROW>
    end
    competitive_bills{i,'sponsors'} = {sponsors_names};
    
    % Find all committee members
    comittee_ids    = [obj.bill_set(chamber_bill_ids(i)).(chamber_data).committee_votes(end).yes_list ; obj.bill_set(chamber_bill_ids(i)).(chamber_data).committee_votes(end).no_list];
    committee_names = obj.getSponsorName(comittee_ids(1));
    for j = 2:length(comittee_ids)
        committee_names = [committee_names ',' obj.getSponsorName(comittee_ids(j))]; %#ok<AGROW>
    end
    competitive_bills{i,'committee_members'} = {committee_names};
    
    % Save the number of sponsors
    sponsor_list(i)   = length(sponsor_names);
    
    % Save the number of committee members
    committee_list(i) = length(committee_names);
end

% Save the table
writetable(competitive_bills,sprintf('%s/%s_%s_competitive_bills.csv',obj.outputs_directory,chamber,specific_tag),'WriteRowNames',false);

% Create a histogram of the number of sponsors
if ~isempty(sponsor_list)
    h = figure();
    hold on
    title(sprintf('%s %s Sponsor Count',chamber,specific_label))
    xlabel('Number of Sponsors')
    ylabel('Frequency')
    grid on
    histfit(sponsor_list,10)
    axis([0 max(sponsor_list) 0 inf])
    hold off
    saveas(h,sprintf('%s/%s_%s_sponsor_histogram',obj.outputs_directory,chamber,specific_tag),'png')
end

% Create a histogram of the number of committee members
if ~isempty(committee_list)
    h = figure();
    hold on
    title(sprintf('%s %s Committee Member Count',chamber,specific_label))
    xlabel('Number of Committee Members')
    ylabel('Frequency')
    grid on
    histfit(committee_list,10)
    axis([0 max(committee_list) 0 inf])
    hold off
    saveas(h,sprintf('%s/%s_%s_committee_histogram',obj.outputs_directory,chamber,specific_tag),'png')
end

end