function elo_master = eloMonteCarlo(obj,bill_ids,category_flag,chamber_people,chamber_sponsor_matrix,chamber_matrix,chamber)

category_flag = sort(category_flag);

if any(category_flag < 0)
    category_flag = 0:1:obj.learning_algorithm_data.issue_code_count;
end

category_flag(category_flag > obj.learning_algorithm_data.issue_code_count) = [];


category_capture = cell(1,length(category_flag));

issue_category = NaN(1,length(bill_ids));

for i = 1:length(bill_ids)
    temp = obj.bill_set(bill_ids(i));
    
    if ~temp.complete
        continue
    end
    
    chamber_data = sprintf('%s_data',lower(chamber));
    
    ids = chamber_matrix.Properties.RowNames;
    
    % Check for a third reading vote
    legislator_list = [];
    for j = length(temp.(chamber_data).chamber_votes):-1:1
        if ~isempty(regexp(upper(temp.(chamber_data).chamber_votes(j).description{:}),'(THIRD|3RD|ON PASSAGE)','once'))
            bill_yes_ids = util.createIDstrings(temp.(chamber_data).chamber_votes(j).yes_list,ids);
            bill_no_ids  = util.createIDstrings(temp.(chamber_data).chamber_votes(j).no_list,ids);
            
            legislator_list = [bill_yes_ids ; bill_no_ids];
            break
        end
    end
    
    if isempty(legislator_list) || length(legislator_list) < obj.(sprintf('%s_size',lower(chamber)))*0.5
        continue
    end
    
    issue_category(i) = temp.issue_category;
    
    if any(category_flag == temp.issue_category)
        category_capture{category_flag == temp.issue_category} = [category_capture{category_flag == temp.issue_category} bill_ids(i)];
    end
    
    if any(category_flag == 0)
        category_capture{1} = [category_capture{1} bill_ids(i)];
    end
end

empty_categories = cellfun(@isempty,category_capture);
category_capture(empty_categories) = [];
category_flag(empty_categories) = [];

category_lengths = cellfun(@length,category_capture);

fprintf('%s Competitive Bill Impact Analysis - %s - %i MC\n',obj.state_ID,chamber,obj.elo_monte_carlo_number)
fprintf('Bill Category | Bill_count\n')
fprintf('-------------------------------\n')
for i = 1:length(category_flag)
    fprintf('%13i | %5i\n',category_flag(i),category_lengths(i));
end
fprintf('-------------------------------\n\n')

MC_flag = 1;
% MC_directory = 'MC\';
if obj.elo_monte_carlo_number == 1
    MC_flag = 0;
%     MC_directory = '';
end

elo_master = cell(1,length(category_flag));

total_run_time = tic;

for i = 1:length(category_flag)
    
    fprintf('START----- Category %i:\n',category_flag(i))
    
    delete_str = '';
    
    elo_monte_carlo = cell(1,obj.elo_monte_carlo_number);
    
    variable_k = [];
    fixed_k = [];
    count = [];
    
    run_time = tic;
    
    for j = 1:obj.elo_monte_carlo_number
        MC_number = j;
        util.setRandomSeed(j);
        [elo_monte_carlo{j},delete_str] = obj.eloPrediction(MC_flag,MC_number,category_flag(i),category_capture{i},chamber_people,chamber_sponsor_matrix,chamber_matrix,chamber,delete_str);
        
        if isempty(variable_k)
            variable_k = elo_monte_carlo{j}.score_variable_k;
        else
            variable_k = variable_k + elo_monte_carlo{j}.score_variable_k;
        end
        
        if isempty(fixed_k)
            fixed_k = elo_monte_carlo{j}.score_fixed_k;
        else
            fixed_k = fixed_k + elo_monte_carlo{j}.score_fixed_k;
        end
        
        if isempty(count)
            count = elo_monte_carlo{j}.count;
        else
            count = count + elo_monte_carlo{j}.count;
        end
    end
    
    print_str = sprintf('%i Monte Carlo Iterations Complete!\n',MC_number);
    fprintf([delete_str,print_str]);
    
    fprintf('FINISH ----- Category %i, elapsed time %0.3f\n\n',category_flag(i),toc(run_time))
    
    variable_k = variable_k ./ obj.elo_monte_carlo_number;
    fixed_k = fixed_k ./ obj.elo_monte_carlo_number;
    
    elo_score = elo_monte_carlo{1};
    
    elo_score.score_fixed_k = fixed_k;
    elo_score.score_variable_k = variable_k;
    elo_score.count = count;
    
    elo_master{i} = elo_score;
    
    if obj.elo_monte_carlo_number > 1
        
        writetable(elo_score,sprintf('%s/MC/%s_elo_score_total_%i_mc%i.csv',obj.elo_directory,upper(chamber(1)),category_flag(i),obj.elo_monte_carlo_number),'WriteRowNames',true);
        
        delete(sprintf('%s/MC/_*_%s_elo_prediction_%i.mat',obj.elo_directory,upper(chamber(1)),category_flag(i)))
        
        save(sprintf('%s/MC/%s_elo_prediction_total_%i_mc%i.mat',obj.elo_directory,upper(chamber(1)),category_flag(i),obj.elo_monte_carlo_number),'elo_score');
    else
        
        writetable(elo_score,sprintf('%s/%s_elo_score_total_%i.csv',obj.elo_directory,upper(chamber(1)),category_flag(i)),'WriteRowNames',true);
        
        save(sprintf('%s/%s_elo_prediction_total_%i.mat',obj.elo_directory,upper(chamber(1)),category_flag(i)),'elo_score');
        
    end
end

fprintf('Entire %s %s Set complete, total time %0.3f\n\n',obj.state_ID,chamber,toc(total_run_time))

end