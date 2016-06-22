function stepwisePrediction(obj,chamber_bill_ids,chamber_people,chamber_sponsor_matrix,chamber_consistency_matrix,committee_sponsor_matrix,chamber_matrix,chamber)
% STEPWISEPREDCITION
% TODO comments

accuracy_list  = zeros(1,length(senate_bill_ids));
sponsor_list   = zeros(1,length(senate_bill_ids));
committee_list = zeros(1,length(senate_bill_ids));

chamber_data = sprintf('%s_data',chamber);

ids               = util.createIDstrings(chamber_people.sponsor_id);
chamber_specifics = chamber_matrix{:,:};
competitive_bills = cell2table(cell(length(senate_bill_ids),8),'VariableNames',{'bill_id' 'bill_number' 'title' 'introduced' 'last_action' 'issue_id','sponsors','committee_members'});

for i = 1:length(chamber_bill_ids)
    competitive_bills{i,'bill_id'}     = {obj.bill_set(chamber_bill_ids(i)).bill_id};
    competitive_bills{i,'bill_number'} = obj.bill_set(chamber_bill_ids(i)).bill_number;
    competitive_bills{i,'title'}       = obj.bill_set(chamber_bill_ids(i)).title;
    competitive_bills{i,'introduced'}  = obj.bill_set(chamber_bill_ids(i)).date_introduced;
    competitive_bills{i,'last_action'} = obj.bill_set(chamber_bill_ids(i)).date_last_action;
    competitive_bills{i,'issue_id'}    = {obj.ISSUE_KEY(obj.bill_set(chamber_bill_ids(i)).issue_category)};
    
    sponsors_names = obj.getSponsorName(obj.bill_set(chamber_bill_ids(i)).sponsors(1));
    for j = 2:length(obj.bill_set(chamber_bill_ids(i)).sponsors)
        sponsors_names = [sponsors_names ',' obj.getSponsorName(obj.bill_set(chamber_bill_ids(i)).sponsors(j))]; %#ok<AGROW>
    end
    competitive_bills{i,'sponsors'} = {sponsors_names};
    
    comittee_ids    = [obj.bill_set(chamber_bill_ids(i)).(chamber_data).committee_votes(end).yes_list ; obj.bill_set(chamber_bill_ids(i)).(chamber_data).committee_votes(end).no_list];
    committee_names = obj.getSponsorName(comittee_ids(1));
    for j = 2:length(comittee_ids)
        committee_names = [committee_names ',' obj.getSponsorName(comittee_ids(j))]; %#ok<AGROW>
    end
    competitive_bills{i,'committee_members'} = {committee_names};
    
    [accuracy, sponsor, committee] = obj.predictOutcomes(chamber_bill_ids(i),ids,chamber_sponsor_matrix,chamber_consistency_matrix,committee_sponsor_matrix,chamber_specifics,obj.generate_outputs,chamber);
    accuracy_list(i)  = accuracy;
    sponsor_list(i)   = sponsor;
    committee_list(i) = committee;
end

if obj.generate_outputs
    writetable(competitive_bills,sprintf('%s/%s_competitive_bills.xlsx',obj.outputs_directory,chamber),'WriteRowNames',false);
end

if ~isempty(accuracy_list) && obj.generate_outputs
    h = figure();
    hold on
    title(sprintf('%s Predictive Model Accuracy at t2',chamber))
    xlabel('Accuracy')
    ylabel('Frequency')
    grid on
    histfit(accuracy_list,20)
    axis([0 100 0 inf])
    hold off
    saveas(h,sprintf('%s/%s_accuracy_histogram_t2',obj.outputs_directory,chamber),'png')
end

if ~isempty(sponsor_list) && obj.generate_outputs
    h = figure();
    hold on
    title(sprintf('%s Sponsor Count',chamber))
    xlabel('Number of Sponsors')
    ylabel('Frequency')
    grid on
    histfit(sponsor_list,10)
    axis([0 max(sponsor_list) 0 inf])
    hold off
    saveas(h,sprintf('%s/%s_sponsor_histogram',obj.outputs_directory,chamber),'png')
end

if ~isempty(committee_list) && obj.generate_outputs
    h = figure();
    hold on
    title(sprintf('%s Committee Member Count',chamber))
    xlabel('Number of Committee Members')
    ylabel('Frequency')
    grid on
    histfit(committee_list,10)
    axis([0 max(committee_list) 0 inf])
    hold off
    saveas(h,sprintf('%s/%s_committee_histogram',obj.outputs_directory,chamber),'png')
end

end