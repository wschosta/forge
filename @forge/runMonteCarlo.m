function [accuracy_list, accuracy_delta, legislators_list, accuracy_steps_list, bill_ids] = runMonteCarlo(obj,chamber_bill_ids,chamber_people,chamber_sponsor_matrix,chamber_consistency_matrix,committee_sponsor_matrix,chamber_matrix,chamber,monte_carlo_number)
% TODO comments

tic
bill_target = length(chamber_bill_ids);
delete_str  = '';

accuracy_list       = zeros(bill_target,obj.monte_carlo_number);
accuracy_delta      = zeros(bill_target,obj.monte_carlo_number);
legislators_list    = cell(bill_target,1);
accuracy_steps_list = cell(bill_target,obj.monte_carlo_number);
bill_ids            = zeros(1,bill_target);

% These will reduce the runtime in the the predictOutcomes
% function
ids               = util.createIDstrings(chamber_people.sponsor_id);
chamber_specifics = chamber_matrix{:,:};

bill_hit = 1;
i = 1;
while bill_hit <= bill_target && i <= length(chamber_bill_ids)
    
    [accuracy,~,~,legislators,accuracy_steps] = obj.predictOutcomes(chamber_bill_ids(i),ids,chamber_sponsor_matrix,chamber_consistency_matrix,committee_sponsor_matrix,chamber_specifics,lower(chamber),obj.monte_carlo_number);
    
    if ~isempty(legislators)
        accuracy_list(bill_hit,:)       = accuracy(1,:);
        accuracy_delta(bill_hit,:)      = accuracy(2,:);
        accuracy_steps_list(bill_hit,:) = accuracy_steps;
        legislators_list{bill_hit}      = legislators;
    else
        i = i + 1;
        continue
    end
    
    print_str = sprintf('%i %i',bill_hit,chamber_bill_ids(i));
    fprintf([delete_str,print_str]);
    delete_str = repmat(sprintf('\b'),1,length(print_str));
    
    bill_ids(bill_hit) = chamber_bill_ids(i);
    bill_hit = bill_hit + 1;
    i = i + 1;
end
bill_hit = bill_hit - 1;

accuracy_list       = accuracy_list(1:bill_hit,1:monte_carlo_number);
accuracy_delta      = accuracy_delta(1:bill_hit,1:monte_carlo_number);
legislators_list    = legislators_list(1:bill_hit);
accuracy_steps_list = accuracy_steps_list(1:bill_hit,1:monte_carlo_number);
bill_ids            = bill_ids(1:bill_hit);

h = figure();
hold on
title(sprintf('%s Prediction Boxplot',chamber))
boxplot(accuracy_list',bill_ids)
xlabel('Bills')
ylabel('Accuracy')
hold off
saveas(h,sprintf('%s/%s_prediction_boxplot_m%i',obj.outputs_directory,upper(chamber(1)),monte_carlo_number),'png')

h = figure();
hold on
title(sprintf('%s Prediction Boxplot - Delta',chamber))
boxplot(accuracy_delta',bill_ids)
xlabel('Bills')
ylabel('Change in Accuracy')
hold off
saveas(h,sprintf('%s/%s_prediction_delta_boxplot_m%i',obj.outputs_directory,upper(chamber(1)),monte_carlo_number),'png')

h = figure();
hold on
title(sprintf('%s Total Prediction Boxplot',chamber))
boxplot(accuracy_list(1:numel(accuracy_list)))
xlabel('All Bills')
ylabel('Accuracy')
hold off
saveas(h,sprintf('%s/%s_prediction_total_boxplot_m%i',obj.outputs_directory,upper(chamber(1)),monte_carlo_number),'png')

h = figure();
hold on
title(sprintf('%s Total Prediction Boxplot - Delta',chamber))
boxplot(accuracy_delta(1:numel(accuracy_delta)))
xlabel('All Bills')
ylabel('Change in Accuracy')
hold off
saveas(h,sprintf('%s/%s_prediction_total_delta_boxplot_m%i',obj.outputs_directory,upper(chamber(1)),monte_carlo_number),'png')

save(sprintf('%s/%s_prediction_model_m%i.mat',obj.prediction_directory,upper(chamber(1)),monte_carlo_number),'accuracy_list','accuracy_delta','legislators_list','accuracy_steps_list','bill_ids')

timed = toc;

print_str = sprintf('%s Done - %i bills! %0.3f\n',chamber,bill_hit,timed);
fprintf([delete_str,print_str]);

end