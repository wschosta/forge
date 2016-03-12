function forge_flat()
clear all; clc;

recompute = 1;
make_gifs = 0;

if exist('saved_data.mat','file') ~= 2 || recompute
    
    bills = readAllFilesOfSubject('bills');
    % people = readAllFilesOfSubject('people'); % THIS IS TO READ IN THE TOTAL PEOPLE LIST
    rollcalls = readAllFilesOfSubject('rollcalls');
    sponsors = readAllFilesOfSubject('sponsors');
    votes = readAllFilesOfSubject('votes');
    
    % CODED SPECIFICALLY FOR THE INDIANA HOUSE AND SENATE. ABSTRACTABLE TO
    % OTHER STATES, WE JUST NEED TO ADJUST THE CHAMBER DESCTIPTIONS
    
    % Read in the specific 2013-2014 Indiana List
    people = readtable('people_2013-2014.xlsx');
    
    rollcalls.senate = strncmpi(rollcalls{:,'description'},{'S'},1);
    rollcalls.total_vote = rollcalls.yea + rollcalls.nay;
    rollcalls.yes_percent = rollcalls.yea./rollcalls.total_vote;
    
    rollcalls.sponsors = cell(length(rollcalls.bill_id),1);
    for i = 1:length(rollcalls.bill_id)
        rollcalls.sponsors(i) = {sponsors{sponsors.bill_id == rollcalls.bill_id(i),'sponsor_id'}}; %#ok<CCAT1>
    end
    
    % EVERYTHING FROM THIS POINT ON IS WRITTEN FOR A SPECIFIC FOCUS ON THE
    % HOUSE. THE SAME COULD BE DONE WITH THE SENATE
    
    house_rollcall = rollcalls(rollcalls.senate == 0,:);
    
    % LIMITING CONDITIONS
    % Where the Yes percetnage is less than 85%
    house_rollcall = house_rollcall(house_rollcall.yes_percent < 0.85,:);
    % Where the number of votes is greater than 60 (effectively eliminating
    % comittee votes)
    house_rollcall = house_rollcall(house_rollcall.total_vote > 60,:);
    
    % PROCESS DATA
    % Two sets, the total data and the sponsorship data
    
    [house_people_matrix, house_people_votes] = processAllVotes(people,house_rollcall,votes);
    [house_people_matrix] = normalizeVotes(house_people_matrix, house_people_votes);
    
    [house_sponsor_matrix, house_sponsor_votes, sponsor_counts] = processSponsorVotes(people,house_rollcall,votes);
    [house_sponsor_matrix] = normalizeVotes(house_sponsor_matrix, house_sponsor_votes);
    
    people.sponsorship_count = sponsor_counts;
    
    % Create Republican and Democrat Lists (makes accounting easier)
    [republican_ids, democrat_ids] = processParties(people);
    
    house_republicans_vote = house_people_matrix(ismember(house_people_matrix.Properties.RowNames,republican_ids),ismember(house_people_matrix.Properties.VariableNames,republican_ids));
    house_democrats_vote   = house_people_matrix(ismember(house_people_matrix.Properties.RowNames,democrat_ids),ismember(house_people_matrix.Properties.VariableNames,democrat_ids));
    
    house_republicans_sponsor = house_sponsor_matrix(ismember(house_sponsor_matrix.Properties.RowNames,republican_ids),ismember(house_sponsor_matrix.Properties.VariableNames,republican_ids));
    house_democrats_sponsor   = house_sponsor_matrix(ismember(house_sponsor_matrix.Properties.RowNames,democrat_ids),ismember(house_sponsor_matrix.Properties.VariableNames,democrat_ids));
    
    save('saved_data')
    
    delete('house_*.xlsx')
    
    writetable(house_people_matrix,'house_people_matrix.xlsx','WriteRowNames',true)
    writetable(house_people_matrix,'house_people_votes.xlsx','WriteRowNames',true)
    writetable(house_republicans_vote,'house_republicans_vote.xlsx','WriteRowNames',true)
    writetable(house_democrats_vote,'house_democrats_vote.xlsx','WriteRowNames',true)
    
    writetable(house_sponsor_matrix,'house_sponsor_matrix.xlsx','WriteRowNames',true)
    writetable(house_sponsor_votes,'house_sponsor_votes.xlsx','WriteRowNames',true)
    writetable(house_republicans_sponsor,'house_republicans_sponsor.xlsx','WriteRowNames',true)
    writetable(house_democrats_sponsor,'house_democrats_sponsor.xlsx','WriteRowNames',true)
    rmdir('gif','s');
    make_gifs = 1;
else
    load('saved_data')
end

% PLOTTING
% Vote Data
tic
generatePlots(house_people_matrix,'House','','Legislators','Legislators','Agreement Score','all',make_gifs)
generatePlots(house_republicans_vote,'House','Republicans','Legislators','Legislators','Agreement Score','R',make_gifs)
generatePlots(house_democrats_vote,'House','Democrats','Legislators','Legislators','Agreement Score','D',make_gifs)
toc

% Sponsorship Data
tic
generatePlots(house_sponsor_matrix,'House','Sponsorship','Legislators','Sponsors','Sponsorship Score','sponsor_all',make_gifs)
generatePlots(house_republicans_sponsor,'House','Republican Sponsorship','Legislators','Sponsors','Sponsorship Score','sponsor_R',make_gifs)
generatePlots(house_democrats_sponsor,'House','Democrat Sponsorship','Legislators','Sponsors','Sponsorship Score','sponsor_D',make_gifs)
toc

end

function [people_matrix, possible_votes] = processAllVotes(people,rollcalls,votes)
tic

% Find the unique roll call ids, this identifies unique votes
unique_rollcall_ids = unique(rollcalls.roll_call_id);

% Create the string array list (which allows for referencing variable names
ids = arrayfun(@(x) ['id' num2str(x)], people{:,'sponsor_id'}, 'Uniform', 0);

% Initialize the people_matrix and possible_votes matrix
people_matrix  = createTable(unique(ids),unique(ids),'NaN');
possible_votes = createTable(unique(ids),unique(ids),'NaN');

% Now we're going to iterate over all the roll calls
for i = 1:length(unique_rollcall_ids)
    
    % Vote Similarity
    % Match all the votes based on the rol call id
    specific_vote = votes(votes.roll_call_id == unique_rollcall_ids(i),:);
    
    % Loop over the two vote types under examination
    for j = [1 2] % possible votes - 1=yes 2=no 3=no vote 4=absent/excused
        % Generate the variable IDs of the relevant voters
        group_votes_string = filterIDs(specific_vote,people_matrix,j);
        
        % Place that information into the people matrix
        people_matrix = addVotes(people_matrix,group_votes_string);
        
        % Print status message
        fprintf('%i %i\n',i,j)
    end
    
    % Total Possible Votes
    % Generate the variable IDs of the relevant voters (yes and no)
    group_votes_string = filterIDs(specific_vote,people_matrix,[1 2]);
    
    % Place that information into possible votes matrix
    possible_votes = addVotes(possible_votes,group_votes_string);
end

% Clear People who didn't have votes
% Generate the list of row names
row_names = people_matrix.Properties.RowNames;

% Iterate over the row names
for i = 1:length(people_matrix.Properties.RowNames)
    % If there are votes (these two statements should always be equivalent)
    if all(isnan(people_matrix{row_names{i},:})) || all(isnan(possible_votes{row_names{i},:}))
        people_matrix(row_names{i},:) = []; % Clear the people matrix row
        people_matrix.(row_names{i})  = []; % Clear the people matrix column
        
        possible_votes(row_names{i},:) = []; % Clear the people matrix row
        possible_votes.(row_names{i})  = []; % Clear the people matrix column
        
        fprintf('WARNING: NO VOTES RECORDED FOR %s\n',row_names{i});
    end
end
toc
end

function [people_matrix, possible_votes, sponsorship_counts] = processSponsorVotes(people,rollcalls,votes)
tic

unique_rollcall_ids = unique(rollcalls.roll_call_id);

ids = arrayfun(@(x) ['id' num2str(x)], people{:,'sponsor_id'}, 'Uniform', 0);

people_matrix  = createTable(unique(ids),unique(ids),'zero');
possible_votes = createTable(unique(ids),unique(ids),'zero');

sponsorship_counts = array2table(zeros(length(unique(ids)),1),'RowNames',unique(ids),'VariableNames',{'count'});

for i = 1:length(unique_rollcall_ids)
    
    specific_vote = votes(votes.roll_call_id == unique_rollcall_ids(i),:);
    
    sponsor = rollcalls{rollcalls.roll_call_id == unique_rollcall_ids(i),'sponsors'}{:};
    
    sponsor_ids = arrayfun(@(x) ['id' num2str(x)], sponsor, 'Uniform', 0);
    sponsor_ids = sponsor_ids(ismember(sponsor_ids,possible_votes.Properties.VariableNames));
    
    if isempty(sponsor_ids)
        continue
    end
    
    sponsorship_counts{ismember(sponsorship_counts.Properties.RowNames,sponsor_ids),'count'} = sponsorship_counts{ismember(sponsorship_counts.Properties.RowNames,sponsor_ids),'count'} + 1;
    
    % possible votes - 1=yes 2=no 3=no vote 4=absent/excused
    % since we're looking at sponsorship agreement we're only looking at
    % Yes votes
    group_votes_string = filterIDs(specific_vote,people_matrix,1);
    
    people_matrix = addVotes(people_matrix,group_votes_string);
    
    fprintf('%i\n',i)
    
    % For total possible votes we're looking at each type: yes, no
    group_votes_string = filterIDs(specific_vote,possible_votes,[1 2]);
    
    possible_votes = addVotes(possible_votes,group_votes_string);
end

% Clear People who didn't have votes

% Generate the list of row names
row_names = people_matrix.Properties.RowNames;

% Iterate over the row names
for i = 1:length(row_names)
    
    % If there are not votes
    if sum(possible_votes{row_names{i},:}) == 0
        people_matrix(row_names{i},:)  = []; % Clear the people matrix
        possible_votes(row_names{i},:) = []; % Clar the possible vote matrix
        fprintf('WARNING: NO VOTES RECORDED FOR %s\n',row_names{i});
    end
end

% Filter out sponsors that don't meet the minimum vote threshold
% Create the filter
filter = mean(sponsorship_counts.count) - std(sponsorship_counts.count)/2;

% Generate the list of column names
column_names = people_matrix.Properties.VariableNames;

% Iterate over the column names
for i = 1:length(column_names)
    
    % If the value for sponsorship is less than the filter
    if sponsorship_counts{column_names{i},'count'} < filter %#ok<BDSCA>
        people_matrix.(column_names{i})  = []; % Clear the people matrix
        possible_votes.(column_names{i}) = []; % Clear the possible vote matrix
        fprintf('WARNING: %s did not meet the vote threshold with only %i\n',column_names{i},sponsorship_counts{i,'count'});
    end
end
toc
end


function [republican_ids, democrat_ids] = processParties(people)
% Create republican ids
republican_ids = arrayfun(@(x) ['id' num2str(x)], people{people.party == 1,'sponsor_id'}, 'Uniform', 0);

% Create democrat ids
democrat_ids   = arrayfun(@(x) ['id' num2str(x)], people{people.party == 0,'sponsor_id'}, 'Uniform', 0);

% Check for bad party IDs
bad_ids = arrayfun(@(x) ['id' num2str(x)], people{~ismember(people.party,[0 1]),'sponsor_id'}, 'Uniform', 0);
for i = 1:length(bad_ids)
    fprintf('WARNING: INCORRECT PARTY ID FOR %s\n',bad_ids{i});
end
end

function output = readAllFilesOfSubject(type)

directories = dir;

output = [];

for i = 1:length(directories)
    if ~isempty(regexp(directories(i).name,'(\d+)-(\d+)_Regular_Session','once'))
        if istable(output)
            output = [output;readtable(sprintf('%s/csv/%s.csv',directories(i).name,type))]; %#ok<AGROW>
        else
            output = readtable(sprintf('%s/csv/%s.csv',directories(i).name,type));
        end
    end
end
end

function vote_matrix = addVotes(vote_matrix,group_votes_string)
temp = vote_matrix{group_votes_string,group_votes_string};
temp(isnan(vote_matrix{group_votes_string,group_votes_string})) = 1;
temp(~isnan(vote_matrix{group_votes_string,group_votes_string})) = temp(~isnan(vote_matrix{group_votes_string,group_votes_string})) + 1;
vote_matrix{group_votes_string,group_votes_string} = temp;
end

function return_table = createTable(rows,columns,type)

switch type
    case 'NaN'
        return_table = array2table(NaN(length(rows),length(columns)),'RowNames',rows,'VariableNames',columns);
    case 'zero'
        return_table = array2table(zeros(length(rows),length(columns)),'RowNames',rows,'VariableNames',columns);
    otherwise
        error('TABLE TYPE NOT FOUND');
end

end

function group_votes_string = filterIDs(specific_vote,people_matrix,parameter)
group_votes_string = num2cell(specific_vote{ismember(specific_vote.vote,parameter),'sponsor_id'});
group_votes_string = strcat('id',cellfun(@num2str,group_votes_string,'UniformOutput',false));
group_votes_string = group_votes_string(ismember(group_votes_string,people_matrix.Properties.VariableNames));
end

function [people_matrix] = normalizeVotes(people_matrix,vote_matrix)

people_matrix{:,:} = people_matrix{:,:} ./ vote_matrix{:,:};

end

function generatePlots(people_matrix,label_string,specific_label,x_specific,y_specific,z_specific,tag,make_gif)

figure()
hold on
title(sprintf('%s %s',label_string,specific_label))
xlabel(x_specific)
ylabel(y_specific)
zlabel(z_specific)
axis square
colorbar
surf(people_matrix{:,:})
view(3)
hold off
saveas(gcf,sprintf('%s_%s',label_string,tag),'png')

view(2)
saveas(gcf,sprintf('%s_%s_flat',label_string,tag),'png')

if make_gif
    directory = sprintf('gif/%s_%s/',label_string,tag);
    [~, ~, ~] = mkdir(directory);
    figure()
    for i = 0:4:360
        
        hold on
        title(sprintf('%s %s',label_string,specific_label))
        xlabel(sprintf('%s Legislators',x_specific))
        ylabel(sprintf('%s Legislators',y_specific))
        zlabel(z_specific)
        axis square
        colorbar
        surf(people_matrix{:,:})
        view(i,48)
        hold off
        saveas(gcf,sprintf('%s/%03i',directory,i),'png')
    end
    
    makeGif(directory,sprintf('%s_%s.gif',label_string,tag),pwd);
end
end

function makeGif(file_path,save_name,save_path)

results   = dir(sprintf('%s/*.png',file_path));
file_name = {results(:).name}';
save_path = [save_path, '\'];
loops = 65535;
delay = 0.2;

h = waitbar(0,'0% done','name','Progress') ;
for i = 1:length(file_name)
    
    a=imread([file_path,file_name{i}]);
    [M,c_map] = rgb2ind(a,256);
    if i == 1
        imwrite(M,c_map,[save_path,save_name],'gif','LoopCount',loops,'DelayTime',delay)
    else
        imwrite(M,c_map,[save_path,save_name],'gif','WriteMode','append','DelayTime',delay)
    end
    waitbar(i/length(file_name),h,[num2str(round(100*i/length(file_name))),'% done']) ;
end
close(h);
end
