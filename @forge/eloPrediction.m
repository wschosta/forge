function elo_score = eloPrediction(obj,bill_ids,chamber_people,chamber_sponsor_matrix,chamber_consistency_matrix,committee_sponsor_matrix,chamber_matrix,chamber)
% ELOPREDICTION
% Execute ELO Prediction

chamber = lower(chamber);        
files = dir(sprintf('%s/%s_elo_prediction.mat',obj.elo_directory,upper(chamber(1))));

% if the file doesn't exist or if we're forcing a recompute
if isempty(files) || obj.recompute_ELO
    
    ids = util.createIDstrings(chamber_people.sponsor_id);
    chamber_specifics = chamber_matrix{:,:};
    
    score1 = ones(length(ids),1)*1500;
    score2 = ones(length(ids),1)*1500;
    count = zeros(length(ids),1);
    
    elo_score = array2table([score1 score2 count],'VariableNames',{'score_variable_k' 'score_fixed_k' 'count'});
    elo_score.Properties.RowNames = ids;
    
    delete_str = '';
    bill_hit   = 1;
    
    tic
    
    for iter = 1:length(bill_ids)
        bill_id = bill_ids(iter);
        

        chamber_data = sprintf('%s_data',chamber);
        
        % Get the specific bill information
        bill_information = obj.bill_set(bill_id);
        
        % if no committee information is available
        if isempty(bill_information.(chamber_data).committee_votes)
            return
        end
        
        % Check for a third reading vote
        legislator_list = [];
        for i = length(bill_information.(chamber_data).chamber_votes):-1:1
            if ~isempty(regexp(upper(obj.bill_set(i).(chamber_data).chamber_votes(i).description{:}),'(THIRD|3RD|ON PASSAGE)','once'))
                bill_yes_ids = util.createIDstrings(bill_information.(chamber_data).chamber_votes(i).yes_list,ids);
                bill_no_ids  = util.createIDstrings(bill_information.(chamber_data).chamber_votes(i).no_list,ids);
                
                legislator_list = [bill_yes_ids ; bill_no_ids];
                break
            end
        end
        
        if isempty(legislator_list) || length(legislator_list) < obj.(sprintf('%s_size',chamber))*0.5
            continue
        end
        
        % Get the sponsor IDs
        sponsor_ids      = util.createIDstrings(bill_information.sponsors,ids);
               
        % Create the basic information about the committee values
        committee_yes     = bill_information.(chamber_data).committee_votes.yes_list;
        committee_no      = bill_information.(chamber_data).committee_votes.no_list;
        committee_members = [committee_yes ; committee_no];
        committee_ids     = util.createIDstrings(committee_members,ids);
        committee_ids_yes = util.createIDstrings(committee_yes,ids);
        committee_ids_no  = util.createIDstrings(committee_no,ids);       
       
        % initial assumption, eveyone is equally likely to vote yes as
        % to vote no. This is probably not true, I'll have to figure
        % out how to figure this out.
        % so we make a table for the bayes, we'll keep track of effects
        % here and then update at each time t. New column for every
        % update, new time t for every update
        bayes_initial  = 0.5;
        t_set          = array2table(NaN(length(ids),1),'VariableNames',{'final'},'RowNames',ids);

        t_set.name = obj.getSponsorName(ids);
        t_set.t1   = NaN(length(ids),1);
        t_set{bill_yes_ids,'final'} = 1;
        t_set{bill_no_ids,'final'}  = 0;
        
        % --------- COMMITTEE EFFECT ---------
        % Calculate sponsor effect and set t1
        committee_specific = ones(length(committee_ids),1)*bayes_initial;
        committee_sponsor_match = sponsor_ids(util.CStrAinBP(sponsor_ids,committee_sponsor_matrix.Properties.VariableNames));
        for i = 1:length(committee_ids)
            
            if ~isempty(util.CStrAinBP(committee_ids{i},committee_sponsor_matrix.Properties.RowNames))
                sponsor_specific_effect = zeros(1,length(committee_sponsor_match));
                
                for k = 1:length(committee_sponsor_match)
                    sponsor_specific_effect(k) = predict.getSpecificImpact(1,committee_sponsor_matrix{committee_ids{i},committee_sponsor_match{k}});
                end
                
                committee_specific(i) = prod(sponsor_specific_effect)*bayes_initial / (prod(sponsor_specific_effect)*bayes_initial + prod(1-sponsor_specific_effect)*(1-bayes_initial));
            end
        end
        t_set{committee_ids,'t1'} = committee_specific;
        
        t_set.committee_vote                      = NaN(length(t_set.Properties.RowNames),1);
        t_set{committee_ids_yes,'committee_vote'} = 1;
        t_set{committee_ids_no,'committee_vote'}  = 0;
        
        t_set.committee_consistency                      = NaN(length(t_set.Properties.RowNames),1);
        t_set{committee_ids_yes,'committee_consistency'} = chamber_consistency_matrix{committee_ids_yes,'percentage'};
        t_set{committee_ids_no,'committee_consistency'}  = chamber_consistency_matrix{committee_ids_no,'percentage'};
        
        % So now we only update based on expressed preference for t2
        % calculate t2
        t_set_current_value  = ones(length(ids),1)*0.5;
        
        matched_ids = util.CStrAinBP(ids,[sponsor_ids;committee_ids]));
        
        for j = 1:length(ids)
            if ~any(j == matched_ids)
                combined_impact = zeros(length(matched_ids),1);
                
                for k = 1:length(matched_ids)
                    combined_impact(k) = predict.getSpecificImpact(1,chamber_specifics(j,k));
                end
                
                t_set_current_value(j) = (prod(combined_impact)*bayes_initial)/(prod(combined_impact)*bayes_initial + prod(1-combined_impact)*(1-bayes_initial));
            else
                if ~isnan(t_set.committee_vote(j))
                    t_set_current_value(j) = predict.getSpecificImpact(t_set.committee_vote(j),t_set.committee_consistency(j));
                elseif ~isempty(util.CStrAinBP(ids(j),chamber_sponsor_matrix.Properties.RowNames) && util.CStrAinBP(ids(j),chamber_sponsor_matrix.Properties.VariableNames))
                    t_set_current_value(j) = predict.getSpecificImpact(1,chamber_specifics(j,j));
                end
            end
        end
        
        t_set.t2          = t_set_current_value;
        t_final_results = t_set.final;
        
        legislator_id     = legislator_list(randperm(length(legislator_list)));
        direction         = zeros(length(legislator_id),1);
        direction(util.CStrAinBP(legislator_id,bill_yes_ids)) = 1;
        
        accuracy = zeros(1,length(legislator_id));
        
        t_count = 2;
        for i = 1:length(legislator_id)
            [~,~,~,accuracy(i)] = predict.updateBayes(legislator_id{i},direction(i),t_set,chamber_specifics,t_count,ids,t_final_results);
        end

        
        % THIS IS WHERE ALL THE ELO SCORE STUFF HAPPENS
        % everything above this point is a copy paste (ugh, I know) from
        % the monte carlo prediciton set
        
        
        count = elo_score{legislator_id,'count'};
        score1 = elo_score{legislator_id,'score_variable_k'};
        score2 = elo_score{legislator_id,'score_fixed_k'};
        
        for i = 1:length(legislator_id)
            for j = i+1:length(legislator_id)
                count(i) = count(i) + 1;
                count(j) = count(j) + 1;

                Wa = 1*(accuracy(i) > accuracy(j)) + 0.5*(accuracy(i) == accuracy(j));
                Wb = 1 - Wa;
                
                % Version 1 - variable k
                Ea = 1/(1+10^((score1(j) - score1(i))/400));
                Eb = 1/(1+10^((score1(i) - score1(j))/400));
                
                Ka = 8000/(200*(count(i) < 200) + count(i)*(count(i) >= 200 && count(i) <=800) + 800*(count(i) > 80));
                Kb = 8000/(200*(count(j) < 200) + count(j)*(count(j) >= 200 && count(j) <=800) + 800*(count(j) > 80));
                
                score1(i) = score1(i) + Ka*(Wa - Ea);
                score1(j) = score1(j) + Kb*(Wb - Eb);
                
                % Version 2 - fixed k
                Ea = 1/(1+10^((score2(j) - score2(i))/400));
                Eb = 1/(1+10^((score2(i) - score2(j))/400));
                
                Ka = 16;
                Kb = 16;
                
                score2(i) = score2(i) + Ka*(Wa - Ea);
                score2(j) = score2(j) + Kb*(Wb - Eb);
            end
        end
        
        elo_score{legislator_id,'count'} = count;
        elo_score{legislator_id,'score_variable_k'} = score1;
        elo_score{legislator_id,'score_fixed_k'} = score2;
        
        print_str = sprintf('%i %i',bill_hit,bill_ids(iter));
        fprintf([delete_str,print_str]);
        delete_str = repmat(sprintf('\b'),1,length(print_str));
        
        
        bill_hit = bill_hit + 1;
    end
    
    timed = toc;
    print_str = sprintf('%s Done - %i bills! %0.3f\n',chamber,bill_hit,timed);
    fprintf([delete_str,print_str]);
    
    elo_score.difference = elo_score.score_variable_k - elo_score.score_fixed_k;    
    elo_score.name       = obj.getSponsorName(elo_score.Properties.RowNames);
    
    elo_score = join(chamber_people,elo_score);
    elo_score = sortrows(elo_score,'score_variable_k','descend');

    save(sprintf('%s/%s_elo_prediction.mat',obj.elo_directory,upper(chamber(1))),'elo_score');
else
    data = load(sprintf('%s/%s_elo_prediction.mat',obj.elo_directory,upper(chamber(1))));
    
    % Pull out the specifics
    elo_score = data.elo_score;
end

if ~isempty(elo_score)
    % Write the results to a table
    writetable(elo_score,sprintf('%s/%s_elo_score.csv',obj.elo_directory,upper(chamber(1))),'WriteRowNames',true);
end

end