function test_file()
clear all; clc; close all;

bills = readtable('bills.csv');
people = readtable('people.csv');
rollcalls = readtable('rollcalls.csv');
sponsors = readtable('sponsors.csv');
votes = readtable('votes.csv');

% Probably can simplify this 
rollcalls.senate = zeros(length(rollcalls.description),1);
for i = 1:length(rollcalls.description)
    if strcmp(rollcalls.description{i}(1),'S')
        rollcalls.senate(i) = 1;
    end
end

senate_rollcall = rollcalls(rollcalls.senate == 1,:);
house_rollcall = rollcalls(rollcalls.senate == 0,:);

[senate_people_matrix, senate_possible_votes] = processAllVotes(people,senate_rollcall,votes);
[house_people_matrix, house_possible_votes] = processAllVotes(people,house_rollcall,votes);

% senate_sponsor_matrix = processSponsorVotes(people,senate_rollcall,votes,sponsors);
% house_sponsor_matrix = processSponsorVotes(people,house_rollcall,votes,sponsors);

tic
[senate_people_matrix] = normalizeVotes(senate_people_matrix, senate_possible_votes);
toc

tic
[house_people_matrix] = normalizeVotes(house_people_matrix, house_possible_votes);
toc

generate_plot(senate_people_matrix,'Senate')
generate_plot(house_people_matrix,'House')

end

function [people_matrix, possible_votes] = processAllVotes(people,rollcalls,votes)
tic

unique_rollcall_ids = unique(rollcalls.roll_call_id);

% Can simplify this for sure
ids = cell(length(people.sponsor_id),1);
for i = 1:length(people.sponsor_id)
    ids{i} = sprintf('id%i',people.sponsor_id(i));
end

people_matrix = array2table(NaN(length(people.sponsor_id)),'RowNames',ids,'VariableNames',ids);
possible_votes = array2table(NaN(length(people.sponsor_id)),'RowNames',ids,'VariableNames',ids);

for i = 1:length(unique_rollcall_ids)
    
    specific_vote = votes(votes.roll_call_id == unique_rollcall_ids(i),:);
    
    for j = [1 2 3 4] % possible votes - 1=yes 2=no 3=no vote 4=?       
        group_votes_string = num2cell(specific_vote{specific_vote.vote == j,'sponsor_id'});
        group_votes_string = strcat('id',cellfun(@num2str,group_votes_string,'UniformOutput',false));
        
        group_votes_string = group_votes_string(ismember(group_votes_string,people_matrix.Properties.VariableNames));
        
        temp = people_matrix{group_votes_string,group_votes_string};
        temp(isnan(people_matrix{group_votes_string,group_votes_string})) = 1;
        temp(~isnan(people_matrix{group_votes_string,group_votes_string})) = temp(~isnan(people_matrix{group_votes_string,group_votes_string})) + 1;
        people_matrix{group_votes_string,group_votes_string} = temp;
               
        fprintf('%i %i\n',i,j)
    end
    
    group_votes_string = num2cell(specific_vote{ismember(specific_vote.vote,[1 2 3 4]),'sponsor_id'});
    group_votes_string = strcat('id',cellfun(@num2str,group_votes_string,'UniformOutput',false));
    
    group_votes_string = group_votes_string(ismember(group_votes_string,possible_votes.Properties.VariableNames));
    
    temp = possible_votes{group_votes_string,group_votes_string};
    temp(isnan(possible_votes{group_votes_string,group_votes_string})) = 1;
    temp(~isnan(possible_votes{group_votes_string,group_votes_string})) = temp(~isnan(possible_votes{group_votes_string,group_votes_string})) + 1;
    possible_votes{group_votes_string,group_votes_string} = temp;
end

row_names = people_matrix.Properties.RowNames;
for i = 1:length(people_matrix.Properties.RowNames)
    if all(isnan(people_matrix{row_names{i},:}))
        people_matrix(row_names{i},:) = [];
        people_matrix(:,row_names{i}) = [];
    end
end

row_names = possible_votes.Properties.RowNames;
for i = 1:length(possible_votes.Properties.RowNames)
    if all(isnan(possible_votes{row_names{i},:}))
        possible_votes(row_names{i},:) = [];
        possible_votes(:,row_names{i}) = [];
    end
end

toc
end

function [people_matrix] = normalizeVotes(people_matrix,vote_matrix)

    for i = people_matrix.Properties.VariableNames
        for j = people_matrix.Properties.RowNames'
           people_matrix{i,j} = people_matrix{i,j}/vote_matrix{i,j}; 
        end
    end

end

function people_matrix = processSponsorVotes(people,rollcall,votes,sponsor)

% NOT DONE YET

tic

% Can simplify this for sure
ids = cell(length(people.sponsor_id),1);
for i = 1:length(people.sponsor_id)
    ids{i} = sprintf('id%i',people.sponsor_id(i));
end

people_matrix = array2table(NaN(length(people.sponsor_id)),'RowNames',ids,'VariableNames',ids);

keyboard

for i = unique_rollcall_ids
    
    % have to match the roll call vote to the sponsor
    keyboard
    
    
    specific_vote = votes(votes.roll_call_id == i,:);
    
    % Here we're only interested in Yes votes
    group_votes_string = num2cell(specific_vote{specific_vote.vote == 1,'sponsor_id'});
    group_votes_string = strcat('id',cellfun(@num2str,group_votes_string,'UniformOutput',false));
    
    group_votes_string = group_votes_string(ismember(group_votes_string,people_matrix.Properties.VariableNames));
    
    temp = people_matrix{group_votes_string,group_votes_string};
    temp(isnan(people_matrix{group_votes_string,group_votes_string})) = 1;
    temp(~isnan(people_matrix{group_votes_string,group_votes_string})) = temp(~isnan(people_matrix{group_votes_string,group_votes_string})) + 1;
    people_matrix{group_votes_string,group_votes_string} = temp;
    
    group_votes_string = num2cell(specific_vote{ismember(specific_vote.vote,[1 2 3]),'sponsor_id'});
    group_votes_string = strcat('id',cellfun(@num2str,group_votes_string,'UniformOutput',false));
    
    group_votes_string = group_votes_string(ismember(group_votes_string,possible_votes.Properties.VariableNames));
    
    temp = possible_votes{group_votes_string,group_votes_string};
    temp(isnan(possible_votes{group_votes_string,group_votes_string})) = 1;
    temp(~isnan(possible_votes{group_votes_string,group_votes_string})) = temp(~isnan(possible_votes{group_votes_string,group_votes_string})) + 1;
    possible_votes{group_votes_string,group_votes_string} = temp;
    
    
    fprintf('%i\n',i)
end

row_names = people_matrix.Properties.RowNames;
for i = 1:length(people_matrix.Properties.RowNames)
    if all(isnan(people_matrix{row_names{i},:}))
        people_matrix(row_names{i},:) = [];
        people_matrix(:,row_names{i}) = [];
    end
end
toc
end

function generate_plot(people_matrix,label_string)

figure()
hold on
title(label_string)
surf(people_matrix{:,:})
view(3)
hold off
saveas(gcf,label_string,'png')

figure()
hold on
title(label_string)
surf(people_matrix{:,:})
view([-45 60])
hold off
saveas(gcf,sprintf('%s_alt',label_string),'png')

figure()
hold on;
title(label_string)
surf(people_matrix{:,:})
view([0 90])
hold off
saveas(gcf,sprintf('%s_flat',label_string),'png')


end