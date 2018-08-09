function stats()

%to generate some basic frequencies on the congressional data

bill_data = load('parsed_xml.mat');

policy_categories = unique(bill_data.policy_area);
policy_count = zeros(length(policy_categories),1);

for i = 1:length(policy_categories)
    policy_count(i) = sum(count(bill_data.policy_area,policy_categories{i}));    
end

subject_list = {};
for i = 1:length(bill_data.subject_area)
    subject_list = [subject_list bill_data.subject_area{i}];
end
subject_categories = unique(subject_list)';
subject_count = zeros(length(subject_categories),1);
for i = 1:length(subject_categories)
    subject_count(i) = sum(count(subject_list,subject_categories{i}));    
end

policy_table = table(policy_categories,policy_count);
subject_table = table(subject_categories,subject_count);

writetable(policy_table,'policy_frequency.csv')
writetable(subject_table,'subject_frequency.csv')

end