function [accuracy, number_sponsors, number_committee, varargout] = predictOutcomes(obj,bill_id,ids,chamber_sponsor_matrix,chamber_consistency_matrix,committee_sponsor_matrix,chamber_specifics,chamber,varargin)
% PREDICTOUTCOMES
% Predict outcomes for a specific bill with a randomized set of legislators

% If there are extra inputs, set the monte carlo number based
% on that. If there aren't this is a single run which means the
% monte carlo number is just 1
monte_carlo = 1;
monte_carlo_run = 0;
if length(varargin) == 1
    monte_carlo = varargin{1};
    monte_carlo_run = 1;
end

% initialize the outputs
varargout{1}     = {};
varargout{2}     = {};
accuracy         = NaN;
number_sponsors  = NaN;
number_committee = NaN;

% Set up the chamber data spring (makes it abstractable)
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
    if ~isempty(regexp(upper(bill_information.(chamber_data).chamber_votes(i).description{:}),'THIRD READING','once'))
        bill_yes_ids = util.createIDstrings(bill_information.(chamber_data).chamber_votes(i).yes_list,ids);
        bill_no_ids  = util.createIDstrings(bill_information.(chamber_data).chamber_votes(i).no_list,ids);
        
        legislator_list = [bill_yes_ids ; bill_no_ids];
        break
    end
end

if isempty(legislator_list) || length(legislator_list) < obj.(sprintf('%s_size',chamber))*0.5
    return
end

% Get the sponsor IDs
sponsor_ids      = util.createIDstrings(bill_information.sponsors,ids);

% Set the number of sponsors
number_sponsors  = size(sponsor_ids,1);

% Create the basic information about the committee values
committee_yes     = bill_information.(chamber_data).committee_votes.yes_list;
committee_no      = bill_information.(chamber_data).committee_votes.no_list;
committee_members = [committee_yes ; committee_no];
committee_ids     = util.createIDstrings(committee_members,ids);
committee_ids_yes = util.createIDstrings(committee_yes,ids);
committee_ids_no  = util.createIDstrings(committee_no,ids);
number_committee  = size(committee_ids,1);


% initial assumption, eveyone is equally likely to vote yes as
% to vote no. This is probably not true, I'll have to figure
% out how to figure this out.
% so we make a table for the bayes, we'll keep track of effects
% here and then update at each time t. New column for every
% update, new time t for every update
bayes_initial  = 0.5;
t_set          = array2table(NaN(length(ids),1),'VariableNames',{'final'},'RowNames',ids);
accuracy_table = array2table(NaN(1,5),'VariableNames',{'final','name','t1','committee_vote','committee_consistency'},'RowNames',{'accuracy'});

t_set.name = obj.getSponsorName(ids);
t_set.t1   = NaN(length(ids),1);
t_set{bill_yes_ids,'final'} = 1;
t_set{bill_no_ids,'final'}  = 0;

% --------- COMMITTEE EFFECT ---------
% Calculate sponsor effect and set t1
committee_specific = ones(length(committee_ids),1)*bayes_initial;
committee_sponsor_match = sponsor_ids(ismember(sponsor_ids,committee_sponsor_matrix.Properties.VariableNames));
for i = 1:length(committee_ids)
    
    if ismember(committee_ids{i},committee_sponsor_matrix.Properties.RowNames)
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

matched_ids = find(ismember(ids,[sponsor_ids;committee_ids]));

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
        elseif ismember(ids(j),chamber_sponsor_matrix.Properties.RowNames) && ismember(ids(j),chamber_sponsor_matrix.Properties.VariableNames)
            t_set_current_value(j) = predict.getSpecificImpact(1,chamber_specifics(j,j));
        end
    end
end

t_set.t2          = t_set_current_value;
t2_check          = (round(t_set.t2) == t_set.final);
incorrect         = sum(t2_check == false);
are_nan           = sum(isnan(t_set{t2_check == false,'final'}));
accuracy_table.t2 = 100*(1-(incorrect-are_nan)/(100-are_nan));

% here is where the updating comes in, need to mock up some
% data whereby people declare preferences. However, things are
% pretty damn solid at this point

% at this point, for t3, we do basically the same thing as t2
% but we just update everything

% TODO Finish comments
if monte_carlo_run
    accuracy_list       = zeros(2,monte_carlo);
    legislators_list    = cell(monte_carlo,1);
    accuracy_steps_list = cell(monte_carlo,1);
end

t_final_results = t_set.final;

for j = 1:monte_carlo
    util.setRandomSeed(j);
    
    legislator_id     = legislator_list(randperm(length(legislator_list)));
    direction         = ismember(legislator_id,bill_yes_ids);
    accuracy_steps    = zeros(1,length(legislator_id)+1);
    accuracy_steps(1) = accuracy_table.t2;
    
    t_count = 2;
    for i = 1:length(legislator_id)
        [t_set,t_count,t_current,accuracy_steps(i+1)] = predict.updateBayes(legislator_id{i},direction(i),t_set,chamber_specifics,t_count,ids,t_final_results);
    end
    
    t_set.(sprintf('%s_check',t_current)) = round(t_set.(t_current)) == t_set.final;
    incorrect = sum(t_set.(sprintf('%s_check',t_current)) == false);
    are_nan   = sum(isnan(t_set{t_set.(sprintf('%s_check',t_current)) == false,'final'}));
    accuracy  = 100*(1-(incorrect-are_nan)/(100-are_nan));
    
    if length(varargin) == 1
        accuracy_list(1,j)  = accuracy;
        accuracy_list(2,j)  = (accuracy - accuracy_table.t2);
        legislators_list{j} = legislator_id;
        
        accuracy_steps_delta = zeros(1,length(legislator_id));
        for i = 1:length(accuracy_steps)-1
            accuracy_steps_delta(i) = accuracy_steps(i+1) - accuracy_steps(i);
        end
        
        accuracy_steps_list{j} = accuracy_steps_delta;
    end
end

if monte_carlo_run
    accuracy     = accuracy_list;
    varargout{1} = obj.createIDcodes(legislators_list);
    varargout{2} = accuracy_steps_list;
end

end