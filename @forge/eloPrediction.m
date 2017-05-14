function [elo_score,varargout] = eloPrediction(obj,MC_flag,MC_number,category_flag,bill_ids,chamber_people,chamber_sponsor_matrix,chamber_matrix,chamber,varargin)
% ELOPREDICTION
% Execute ELO Prediction

if length(varargin) == 1
    delete_str = varargin{1};
else
    delete_str = '';
end

MC_directory = '';
if MC_flag
    MC_directory = sprintf('MC/_%i_',MC_number);
end

chamber = lower(chamber);        
files = dir(sprintf('%s/%s%s_elo_prediction_%i.mat',obj.elo_directory,MC_directory,upper(chamber(1)),category_flag));

% if the file doesn't exist or if we're forcing a recompute
if isempty(files) || obj.recompute_ELO
    
%     ids = util.createIDstrings(chamber_people.sponsor_id);
    ids = chamber_matrix.Properties.RowNames;
    chamber_specifics = chamber_matrix{:,:};
    
    score1 = ones(length(ids),1)*1500;
    score2 = ones(length(ids),1)*1500;
    count  = zeros(length(ids),1);
    
    elo_score = array2table([score1 score2 count],'VariableNames',{'score_variable_k' 'score_fixed_k' 'count'});
    elo_score.Properties.RowNames = ids;
    
    
    bill_hit   = 1;
    
    tic
    
    for iter = 1:length(bill_ids)
        bill_id = bill_ids(iter);
        
        chamber_data = sprintf('%s_data',chamber);
        
        % Get the specific bill information
        bill_information = obj.bill_set(bill_id);
        
        % TODO Up in here is where we would do the bill-category specific
        % filtering
        
        % TODO THIS IS ALL COPY+PASTED FROM PREDICTOUTCOMES. SAD!
        
        % if the bill is incomplete, skip it
%         if ~bill_information.complete
%             continue
%         end
        
        % Check for a third reading vote
        legislator_list = [];
        for i = length(bill_information.(chamber_data).chamber_votes):-1:1
            if ~isempty(regexp(upper(bill_information.(chamber_data).chamber_votes(i).description{:}),'(THIRD|3RD|ON PASSAGE)','once'))
                bill_yes_ids = util.createIDstrings(bill_information.(chamber_data).chamber_votes(i).yes_list,ids);
                bill_no_ids  = util.createIDstrings(bill_information.(chamber_data).chamber_votes(i).no_list,ids);
                
                legislator_list = [bill_yes_ids ; bill_no_ids];
                break
            end
        end
        
%         if isempty(legislator_list) || length(legislator_list) < obj.(sprintf('%s_size',chamber))*0.5
%             continue
%         end
        
        % Get the sponsor IDs
        sponsor_ids      = util.createIDstrings(bill_information.sponsors,ids);

        % Set the number of sponsors
%         number_sponsors  = size(sponsor_ids,1);

        % initial assumption, eveyone is equally likely to vote yes as
        % to vote no. This is probably not true, I'll have to figure
        % out how to figure this out.
        % so we make a table for the bayes, we'll keep track of effects
        % here and then update at each time t. New column for every
        % update, new time t for every update
        bayes_initial  = 0.5;
        t_set          = array2table(NaN(length(ids),1),'VariableNames',{'final'},'RowNames',ids);

%         t_set.name = obj.getSponsorName(ids);
        t_set.t1   = NaN(length(ids),1);
        t_set{bill_yes_ids,'final'} = 1;
        t_set{bill_no_ids,'final'}  = 0;
        
        % --------- SPONSOR EFFECT ---------
        % Calculate sponsor effect and set t1
        sponsor_specific = ones(length(sponsor_ids),1)*bayes_initial;
        sponsor_match = sponsor_ids(util.CStrAinBP(sponsor_ids,chamber_sponsor_matrix.Properties.VariableNames));
        chamber_sponsor_matrix_fast = chamber_sponsor_matrix{sponsor_ids,sponsor_match};
        for i = 1:length(sponsor_ids)
            
            %             if ismember(sponsor_ids{i},chamber_sponsor_matrix.Properties.RowNames) % this seems to be unnecessary in this case, commenting out to save time.
            sponsor_specific_effect = zeros(1,length(sponsor_match));
            
            for k = 1:length(sponsor_match)
                sponsor_specific_effect(k) = predict.getSpecificImpact(1,chamber_sponsor_matrix_fast(i,k));
            end
            
            sponsor_specific(i) = prod(sponsor_specific_effect)*bayes_initial / (prod(sponsor_specific_effect)*bayes_initial + prod(1-sponsor_specific_effect)*(1-bayes_initial));
            %             end
        end

        t_set{sponsor_ids,'t1'} = sponsor_specific;

 
        t_final_results   = t_set.final;
        legislator_id     = legislator_list(randperm(length(legislator_list)));
        direction         = zeros(length(legislator_id),1);
        direction(util.CStrAinBP(legislator_id,bill_yes_ids)) = 1;
        
        accuracy = zeros(1,length(legislator_id));
        
        t_count = 1;
        
        %---------NEW WAY
        t_current = sprintf('t%i',t_count);
        
        % Pull out the values of the previous t_set
        t_current_value = t_set.(t_current);
        for i = 1:length(legislator_id)
            [~,~,accuracy(i)] = predict.updateBayes(legislator_id{i},direction(i),t_current_value,chamber_specifics,t_count,ids,t_final_results);
        end
        
        t_set.(t_current) = t_current_value;
        %---------NEW WAY END
        
        %---------OLD WAY
        %         for i = 1:length(legislator_id)
        %             [~,~,~,accuracy(i)] = predict.updateBayes_old(legislator_id{i},direction(i),t_set,chamber_specifics,t_count,ids,t_final_results);
        %         end
        %---------OLD WAY END
        
        % THIS IS WHERE ALL THE ELO SCORE STUFF HAPPENS
        % everything above this point is a copy paste (ugh, I know) from
        % predictOutcomes
        
        % TODO for the bill categories, maybe just some filter here?
        % different variable names for the different bill categories? the
        % issue is it has to pull from the existing score which will be
        % different for each legislator in each category
        
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
        
        print_str = sprintf('%i %i %i',MC_number,bill_hit,bill_ids(iter));
        fprintf([delete_str,print_str]);
        delete_str = repmat(sprintf('\b'),1,length(print_str));
        
        
        bill_hit = bill_hit + 1;
    end
    
    timed = toc;
    print_str = sprintf('%i %s Done - %i bills! %0.3f',MC_number,chamber,bill_hit,timed);
    fprintf([delete_str,print_str]);
    delete_str = repmat(sprintf('\b'),1,length(print_str));
        
    elo_score.difference = elo_score.score_variable_k - elo_score.score_fixed_k;    
    elo_score.name       = obj.getSponsorName(elo_score.Properties.RowNames);
    
    elo_score = join(elo_score,chamber_people);
    
    if ~MC_flag
        elo_score = sortrows(elo_score,'score_variable_k','descend');
    else
        elo_score = sortrows(elo_score,'sponsor_id','descend');
    end
    
    save(sprintf('%s/%s%s_elo_prediction_%i.mat',obj.elo_directory,MC_directory,upper(chamber(1)),category_flag),'elo_score');
    
else
    data = load(sprintf('%s/%s%s_elo_prediction_%i.mat',obj.elo_directory,MC_directory,upper(chamber(1)),category_flag));
    
    % Pull out the specifics
    elo_score = data.elo_score;
end

if ~isempty(elo_score) && ~MC_flag
    % Write the results to a table
    writetable(elo_score,sprintf('%s/%s%s_elo_score_%i.csv',obj.elo_directory,MC_directory,upper(chamber(1)),category_flag),'WriteRowNames',true);
end

if nargout == 2
    varargout{1} = delete_str;
end

end