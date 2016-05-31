classdef IN < forge
    properties  
    end
    
    methods
        function obj = IN(varargin)
            in = inputParser;
            addOptional(in,'recompute',0,@islogical);
            addOptional(in,'reprocess',0,@islogical);
            addOptional(in,'generateOutputs',0,@islogical);
            parse(in,varargin{:});
            
            obj.state = 'IN';
            obj.senate_size = 50;
            obj.house_size = 100;
            
            obj.recompute = in.Results.recompute;
            obj.reprocess = in.Results.reprocess;
            obj.generate_outputs = in.Results.generateOutputs;
            
            obj.outputs_directory = sprintf('data/%s/outputs',obj.state);
            obj.gif_directory = sprintf('%s/gif',obj.outputs_directory);
            obj.histogram_directory = sprintf('%s/histograms',obj.outputs_directory);
            
            obj.learning_algorithm_data = la.loadLearnedMaterials(obj.state);
            
            obj.init(); % forge init
        end
        
        function run(obj)
            predict_montecarlo = true;
            predict_outcomes = false;
            
            if exist(sprintf('data/%s/saved_data.mat',obj.state),'file') ~= 2 || obj.recompute
                
                % CODED SPECIFICALLY FOR THE INDIANA HOUSE AND SENATE.
                % ABSTRACTABLE TO OTHER STATES, WE JUST NEED TO ADJUST THE
                % CHAMBER DESCRIPTIONS
                
                override = true;
                
                directory = sprintf('data/%s',obj.state);
                list      = dir(directory);
                hit_list = regexp({list.name},'people_(\d+).*','once');
                
                house_people  = []; %#ok<NASGU>
                senate_people = [];
                
                if ~any([hit_list{:}]) || override
                    % Takes from the maximum year, could also be set to do
                    % a specific year
                    year_select = max(unique(obj.people.year));
                    
                    if all(ismember({'year','role_id','party_id'},obj.people.Properties.VariableNames))
                        obj.people.party_id = obj.people.party_id - 1;
                        select_people = obj.people(obj.people.year == year_select,:);
                        house_people  = select_people(select_people.role_id == 1,:);
                        senate_people = select_people(select_people.role_id == 2,:);
                    else
                        fprintf('Not able to read people from legiscan data, searching for local data...\n')
                        
                        % If we can't find anything, do a hardcode read
                        % (just so there's something here)
                        house_people = readtable(sprintf('data/%s/people_2013-2014.xlsx',obj.state));
                    end
                else
                    % Hardcode read that has a bunch of great extra stuff.
                    % That we don't use...
                    house_people = readtable(sprintf('data/%s/people_2013-2014.xlsx',obj.state));
                end
                
                % ---------------------- House Data -----------------------
                if ~isempty(house_people)

                    [house_chamber_matrix,house_chamber_votes,...
                        house_sponsor_chamber_matrix,house_sponsor_chamber_votes,...
                        house_committee_matrix,house_committee_votes,...
                        house_sponsor_committee_matrix,house_sponsor_committee_votes,...
                        house_consistency_matrix,house_bill_ids]  = obj.processChamberVotes(house_people,'house');
                    
                    house_consistency_matrix.percentage = house_consistency_matrix.consistency ./ house_consistency_matrix.opportunity;
                    
                    % Create Republican and Democrat Lists (makes accounting easier)
                    [republican_ids, democrat_ids] = obj.processParties(house_people);
                    
                    house_republicans_chamber_votes = house_chamber_matrix(ismember(house_chamber_matrix.Properties.RowNames,republican_ids),ismember(house_chamber_matrix.Properties.VariableNames,republican_ids));
                    house_democrats_chamber_votes   = house_chamber_matrix(ismember(house_chamber_matrix.Properties.RowNames,democrat_ids),ismember(house_chamber_matrix.Properties.VariableNames,democrat_ids));
                    
                    house_republicans_chamber_sponsor = house_sponsor_chamber_matrix(ismember(house_sponsor_chamber_matrix.Properties.RowNames,republican_ids),ismember(house_sponsor_chamber_matrix.Properties.VariableNames,republican_ids));
                    house_democrats_chamber_sponsor   = house_sponsor_chamber_matrix(ismember(house_sponsor_chamber_matrix.Properties.RowNames,democrat_ids),ismember(house_sponsor_chamber_matrix.Properties.VariableNames,democrat_ids));
                    
                    house_republicans_committee_votes = house_committee_matrix(ismember(house_committee_matrix.Properties.RowNames,republican_ids),ismember(house_committee_matrix.Properties.VariableNames,republican_ids));
                    house_democrats_committee_votes   = house_committee_matrix(ismember(house_committee_matrix.Properties.RowNames,democrat_ids),ismember(house_committee_matrix.Properties.VariableNames,democrat_ids));
                    
                    house_republicans_committee_sponsor = house_sponsor_committee_matrix(ismember(house_sponsor_committee_matrix.Properties.RowNames,republican_ids),ismember(house_sponsor_committee_matrix.Properties.VariableNames,republican_ids));
                    house_democrats_committee_sponsor   = house_sponsor_committee_matrix(ismember(house_sponsor_committee_matrix.Properties.RowNames,democrat_ids),ismember(house_sponsor_committee_matrix.Properties.VariableNames,democrat_ids));
                    
                    house_seat_flag = 0;
                    if all(ismember({'SEATROW','SEATCOLUMN'},house_people.Properties.VariableNames))
                        house_seat_flag = 1;
                        house_seat_matrix = obj.processSeatProximity(house_people);
                    end
                end
                
                % --------------------- Senate Data -----------------------
                if ~isempty(senate_people)

                    [senate_chamber_matrix,senate_chamber_votes,...
                        senate_sponsor_chamber_matrix,senate_sponsor_chamber_votes,...
                        senate_committee_matrix,senate_committee_votes,...
                        senate_sponsor_committee_matrix,senate_sponsor_committee_votes,...
                        senate_consistency_matrix,senate_bill_ids]  = obj.processChamberVotes(senate_people,'senate');
                    
                    senate_consistency_matrix.percentage = senate_consistency_matrix.consistency ./ senate_consistency_matrix.opportunity;
                    
                    % Create Republican and Democrat Lists (makes accounting easier)
                    [republican_ids, democrat_ids] = obj.processParties(senate_people);
                    
                    senate_republicans_chamber_votes = senate_chamber_matrix(ismember(senate_chamber_matrix.Properties.RowNames,republican_ids),ismember(senate_chamber_matrix.Properties.VariableNames,republican_ids));
                    senate_democrats_chamber_votes   = senate_chamber_matrix(ismember(senate_chamber_matrix.Properties.RowNames,democrat_ids),ismember(senate_chamber_matrix.Properties.VariableNames,democrat_ids));
                    
                    senate_republicans_chamber_sponsor = senate_sponsor_chamber_matrix(ismember(senate_sponsor_chamber_matrix.Properties.RowNames,republican_ids),ismember(senate_sponsor_chamber_matrix.Properties.VariableNames,republican_ids));
                    senate_democrats_chamber_sponsor   = senate_sponsor_chamber_matrix(ismember(senate_sponsor_chamber_matrix.Properties.RowNames,democrat_ids),ismember(senate_sponsor_chamber_matrix.Properties.VariableNames,democrat_ids));
                    
                    senate_republicans_committee_votes = senate_committee_matrix(ismember(senate_committee_matrix.Properties.RowNames,republican_ids),ismember(senate_committee_matrix.Properties.VariableNames,republican_ids));
                    senate_democrats_committee_votes   = senate_committee_matrix(ismember(senate_committee_matrix.Properties.RowNames,democrat_ids),ismember(senate_committee_matrix.Properties.VariableNames,democrat_ids));
                    
                    senate_republicans_committee_sponsor = senate_sponsor_committee_matrix(ismember(senate_sponsor_committee_matrix.Properties.RowNames,republican_ids),ismember(senate_sponsor_committee_matrix.Properties.VariableNames,republican_ids));
                    senate_democrats_committee_sponsor   = senate_sponsor_committee_matrix(ismember(senate_sponsor_committee_matrix.Properties.RowNames,democrat_ids),ismember(senate_sponsor_committee_matrix.Properties.VariableNames,democrat_ids));
                    
                    senate_seat_flag = 0;
                    if all(ismember({'SEATROW','SEATCOLUMN'},senate_people.Properties.VariableNames))
                        senate_seat_flag = 1;
                        senate_seat_matrix = obj.processSeatProximity(senate_people);
                    end
                end
                
                var_list = who;
                var_list = var_list(~ismember(var_list,'obj'));
                save(sprintf('data/%s/saved_data.mat',obj.state),var_list{:})
                
                if obj.generate_outputs
                    
                    if ~isempty(house_people)
                        delete(sprintf('%s/house_*.xlsx',obj.outputs_directory));
                        
                        writetable(house_chamber_matrix,sprintf('%s/house_all_chamber_matrix.xlsx',obj.outputs_directory),'WriteRowNames',true);
                        writetable(house_chamber_votes,sprintf('%s/house_all_chamber_votes.xlsx',obj.outputs_directory),'WriteRowNames',true);
                        writetable(house_republicans_chamber_votes,sprintf('%s/house_republicans_chamber_votes.xlsx',obj.outputs_directory),'WriteRowNames',true);
                        writetable(house_democrats_chamber_votes,sprintf('%s/house_democrats_chamber_votes.xlsx',obj.outputs_directory),'WriteRowNames',true);
                        
                        writetable(house_sponsor_chamber_matrix,sprintf('%s/house_all_sponsor_chamber_matrix.xlsx',obj.outputs_directory),'WriteRowNames',true);
                        writetable(house_sponsor_chamber_votes,sprintf('%s/house_all_sponsor_chamber_votes.xlsx',obj.outputs_directory),'WriteRowNames',true);
                        writetable(house_republicans_chamber_sponsor,sprintf('%s/house_republicans_chamber_sponsor.xlsx',obj.outputs_directory),'WriteRowNames',true);
                        writetable(house_democrats_chamber_sponsor,sprintf('%s/house_democrats_chamber_sponsor.xlsx',obj.outputs_directory),'WriteRowNames',true);
                        
                        writetable(house_committee_matrix,sprintf('%s/house_all_committee_matrix.xlsx',obj.outputs_directory),'WriteRowNames',true);
                        writetable(house_committee_votes,sprintf('%s/house_all_committee_votes.xlsx',obj.outputs_directory),'WriteRowNames',true);
                        writetable(house_republicans_committee_votes,sprintf('%s/house_republicans_committee_votes.xlsx',obj.outputs_directory),'WriteRowNames',true);
                        writetable(house_democrats_committee_votes,sprintf('%s/house_democrats_committee_votes.xlsx',obj.outputs_directory),'WriteRowNames',true);
                        
                        writetable(house_sponsor_committee_matrix,sprintf('%s/house_all_sponsor_committee_matrix.xlsx',obj.outputs_directory),'WriteRowNames',true);
                        writetable(house_sponsor_committee_votes,sprintf('%s/house_all_sponsor_committee_votes.xlsx',obj.outputs_directory),'WriteRowNames',true);
                        writetable(house_republicans_committee_sponsor,sprintf('%s/house_republicans_committee_sponsor.xlsx',obj.outputs_directory),'WriteRowNames',true);
                        writetable(house_democrats_committee_sponsor,sprintf('%s/house_democrats_committee_sponsor.xlsx',obj.outputs_directory),'WriteRowNames',true);
                        
                        writetable(house_consistency_matrix,sprintf('%s/house_consistency_matrix.xlsx',obj.outputs_directory),'WriteRowNames',true);
                        
                        if house_seat_flag
                            writetable(house_seat_matrix,sprintf('%s/house_seat_matrix.xlsx',obj.outputs_directory),'WriteRowNames',true);
                        end
                    end
                    
                    if ~isempty(senate_people)
                        delete(sprintf('%s/senate_*.xlsx',obj.outputs_directory));
                        
                        writetable(senate_chamber_matrix,sprintf('%s/senate_all_chamber_matrix.xlsx',obj.outputs_directory),'WriteRowNames',true);
                        writetable(senate_chamber_votes,sprintf('%s/senate_all_chamber_votes.xlsx',obj.outputs_directory),'WriteRowNames',true);
                        writetable(senate_republicans_chamber_votes,sprintf('%s/senate_republicans_chamber_votes.xlsx',obj.outputs_directory),'WriteRowNames',true);
                        writetable(senate_democrats_chamber_votes,sprintf('%s/senate_democrats_chamber_votes.xlsx',obj.outputs_directory),'WriteRowNames',true);
                        
                        writetable(senate_sponsor_chamber_matrix,sprintf('%s/senate_all_sponsor_chamber_matrix.xlsx',obj.outputs_directory),'WriteRowNames',true);
                        writetable(senate_sponsor_chamber_votes,sprintf('%s/senate_all_sponsor_chamber_votes.xlsx',obj.outputs_directory),'WriteRowNames',true);
                        writetable(senate_republicans_chamber_sponsor,sprintf('%s/senate_republicans_chamber_sponsor.xlsx',obj.outputs_directory),'WriteRowNames',true);
                        writetable(senate_democrats_chamber_sponsor,sprintf('%s/senate_democrats_chamber_sponsor.xlsx',obj.outputs_directory),'WriteRowNames',true);
                        
                        writetable(senate_committee_matrix,sprintf('%s/senate_all_committee_matrix.xlsx',obj.outputs_directory),'WriteRowNames',true);
                        writetable(senate_committee_votes,sprintf('%s/senate_all_committee_votes.xlsx',obj.outputs_directory),'WriteRowNames',true);
                        writetable(senate_republicans_committee_votes,sprintf('%s/senate_republicans_committee_votes.xlsx',obj.outputs_directory),'WriteRowNames',true);
                        writetable(senate_democrats_committee_votes,sprintf('%s/senate_democrats_committee_votes.xlsx',obj.outputs_directory),'WriteRowNames',true);
                        
                        writetable(senate_sponsor_committee_matrix,sprintf('%s/senate_all_sponsor_committee_matrix.xlsx',obj.outputs_directory),'WriteRowNames',true);
                        writetable(senate_sponsor_committee_votes,sprintf('%s/senate_all_sponsor_committee_votes.xlsx',obj.outputs_directory),'WriteRowNames',true);
                        writetable(senate_republicans_committee_sponsor,sprintf('%s/senate_republicans_committee_sponsor.xlsx',obj.outputs_directory),'WriteRowNames',true);
                        writetable(senate_democrats_committee_sponsor,sprintf('%s/senate_democrats_committee_sponsor.xlsx',obj.outputs_directory),'WriteRowNames',true);
                        
                        writetable(senate_consistency_matrix,sprintf('%s/senate_consistency_matrix.xlsx',obj.outputs_directory),'WriteRowNames',true);
                        
                        if senate_seat_flag
                            writetable(senate_seat_matrix,sprintf('%s/senate_seat_matrix.xlsx',obj.outputs_directory),'WriteRowNames',true);
                        end
                    end
                    
                    [~,~,~] = rmdir(obj.gif_directory,'s');
                    [~,~,~] = rmdir(obj.histogram_directory,'s');
                    obj.make_gifs = true;
                    obj.make_histograms = true;
                end
            else
                load(sprintf('data/%s/saved_data.mat',obj.state));
            end
            
            if obj.generate_outputs
                
                if ~isempty(house_people)
                    % PLOTTING
                    % Chamber Vote Data
                    tic
                    plot.generatePlots(obj.outputs_directory,obj.histogram_directory,house_chamber_matrix,'House','','Legislators','Legislators','Agreement Score','chamber_all')
                    plot.generatePlots(obj.outputs_directory,obj.histogram_directory,house_republicans_chamber_votes,'House','Republicans','Legislators','Legislators','Agreement Score','chamber_R')
                    plot.generatePlots(obj.outputs_directory,obj.histogram_directory,house_democrats_chamber_votes,'House','Democrats','Legislators','Legislators','Agreement Score','chamber_D')
                    toc
                    
                    % Chamber Sponsorship Data
                    tic
                    plot.generatePlots(obj.outputs_directory,obj.histogram_directory,house_sponsor_chamber_matrix,'House','Sponsorship','Sponsors','Legislators','Sponsorship Score','chamber_sponsor_all')
                    plot.generatePlots(obj.outputs_directory,obj.histogram_directory,house_republicans_chamber_sponsor,'House','Republican Sponsorship','Sponsors','Legislators','Sponsorship Score','chamber_sponsor_R')
                    plot.generatePlots(obj.outputs_directory,obj.histogram_directory,house_democrats_chamber_sponsor,'House','Democrat Sponsorship','Sponsors','Legislators','Sponsorship Score','chamber_sponsor_D')
                    toc
                    
                    % Committee Vote Data
                    tic
                    plot.generatePlots(obj.outputs_directory,obj.histogram_directory,house_committee_matrix,'House Committee','','Legislators','Legislators','Agreement Score','committee_all')
                    plot.generatePlots(obj.outputs_directory,obj.histogram_directory,house_republicans_committee_votes,'House Committee','Republicans','Legislators','Legislators','Agreement Score','committee_R')
                    plot.generatePlots(obj.outputs_directory,obj.histogram_directory,house_democrats_committee_votes,'House Committee','Democrats','Legislators','Legislators','Agreement Score','committee_D')
                    toc
                    
                    % Committee Sponsorship Data
                    tic
                    plot.generatePlots(obj.outputs_directory,obj.histogram_directory,house_sponsor_committee_matrix,'House Committee','Sponsorship','Sponsors','Legislators','Sponsorship Score','committee_sponsor_all')
                    plot.generatePlots(obj.outputs_directory,obj.histogram_directory,house_republicans_committee_sponsor,'House Committee','Republican Sponsorship','Sponsors','Legislators','Sponsorship Score','committee_sponsor_R')
                    plot.generatePlots(obj.outputs_directory,obj.histogram_directory,house_democrats_committee_sponsor,'House Committee','Democrat Sponsorship','Sponsors','Legislators','Sponsorship Score','committee_sponsor_D')
                    toc
                    
                    % Chamber-Committee Consistency
                    if any(~isnan(house_consistency_matrix.percentage))
                        h = figure();
                        hold on
                        title('Chamber-Committee Consistency')
                        xlabel('Agreement')
                        ylabel('Frequency')
                        grid on
                        histfit(house_consistency_matrix.percentage)
                        axis([0 1 0 inf])
                        hold off
                        saveas(h,sprintf('%s/histogram_house_committee_consistency',obj.outputs_directory),'png')
                    end
                end
                
                if ~isempty(senate_people)
                    % PLOTTING
                    % Chamber Vote Data
                    tic
                    plot.generatePlots(obj.outputs_directory,obj.histogram_directory,senate_chamber_matrix,'Senate','','Legislators','Legislators','Agreement Score','chamber_all')
                    plot.generatePlots(obj.outputs_directory,obj.histogram_directory,senate_republicans_chamber_votes,'Senate','Republicans','Legislators','Legislators','Agreement Score','chamber_R')
                    plot.generatePlots(obj.outputs_directory,obj.histogram_directory,senate_democrats_chamber_votes,'Senate','Democrats','Legislators','Legislators','Agreement Score','chamber_D')
                    toc
                    
                    % Chamber Sponsorship Data
                    tic
                    plot.generatePlots(obj.outputs_directory,obj.histogram_directory,senate_sponsor_chamber_matrix,'Senate','Sponsorship','Sponsors','Legislators','Sponsorship Score','chamber_sponsor_all')
                    plot.generatePlots(obj.outputs_directory,obj.histogram_directory,senate_republicans_chamber_sponsor,'Senate','Republican Sponsorship','Sponsors','Legislators','Sponsorship Score','chamber_sponsor_R')
                    plot.generatePlots(obj.outputs_directory,obj.histogram_directory,senate_democrats_chamber_sponsor,'Senate','Democrat Sponsorship','Sponsors','Legislators','Sponsorship Score','chamber_sponsor_D')
                    toc
                    
                    % Committee Vote Data
                    tic
                    plot.generatePlots(obj.outputs_directory,obj.histogram_directory,senate_committee_matrix,'Senate Committee','','Legislators','Legislators','Agreement Score','committee_all')
                    plot.generatePlots(obj.outputs_directory,obj.histogram_directory,senate_republicans_committee_votes,'Senate Committee','Republicans','Legislators','Legislators','Agreement Score','committee_R')
                    plot.generatePlots(obj.outputs_directory,obj.histogram_directory,senate_democrats_committee_votes,'Senate Committee','Democrats','Legislators','Legislators','Agreement Score','committee_D')
                    toc
                    
                    % Committee Sponsorship Data
                    tic
                    plot.generatePlots(obj.outputs_directory,obj.histogram_directory,senate_sponsor_committee_matrix,'Senate Committee','Sponsorship','Sponsors','Legislators','Sponsorship Score','committee_sponsor_all')
                    plot.generatePlots(obj.outputs_directory,obj.histogram_directory,senate_republicans_committee_sponsor,'Senate Committee','Republican Sponsorship','Sponsors','Legislators','Sponsorship Score','committee_sponsor_R')
                    plot.generatePlots(obj.outputs_directory,obj.histogram_directory,senate_democrats_committee_sponsor,'Senate Committee','Democrat Sponsorship','Sponsors','Legislators','Sponsorship Score','committee_sponsor_D')
                    toc
                    
                    % Chamber-Committee Consistency
                    if any(~isnan(senate_consistency_matrix.percentage))
                        h = figure();
                        hold on
                        title('Chamber-Committee Consistency')
                        xlabel('Agreement')
                        ylabel('Frequency')
                        grid on
                        histfit(senate_consistency_matrix.percentage)
                        axis([0 1 0 inf])
                        hold off
                        saveas(h,sprintf('%s/histogram_senate_committee_consistency',obj.outputs_directory),'png')
                    end
                end
                
                if obj.make_gifs
                    [~,~,~] = rmdir(obj.gif_directory,'s');
                end
            end
            
            % each entry will be a structure that contains the important
            % information about the bill and its passage through both the
            % senate and the house
            % this might be an opportunity to bring in the as-yet
            % unused "history" sheet - from which it should be possible
            % to mine primary vs secondary sponsors
            
            % build in a key for each coded variable on both a bill and
            % person basis: {bill : issue, committee of origin } {person :
            % party, chamber leadership, committee leadership}
            
            % the result will be a system in which the bills are stored in
            % a struct that can be drilled to get specific information and
            % people will continue to be stored in a table
            
            % district information, which will be included soon, will also
            % be stored in table format
            
            % makes sense for the relational things (seat proximity, vote
            % similarity, sponsorship) to be stored in a table as well -
            % they can be referenced directly by the legislator ID
            
            % ID should probably be stored as a string throughout, that way
            % it can be used in variable names more easily
            
            if ~isempty(house_people) && predict_outcomes
                accuracy_list = zeros(1,length(house_bill_ids));
                sponsor_list = zeros(1,length(house_bill_ids));
                committee_list = zeros(1,length(house_bill_ids));
                for i = 1:length(house_bill_ids)
                    [accuracy, sponsor, committee] = obj.predictOutcomes(house_bill_ids(i),house_people,house_sponsor_chamber_matrix,house_consistency_matrix,house_sponsor_committee_matrix,house_chamber_matrix,obj.generate_outputs,'house');
                    accuracy_list(i) = accuracy;
                    sponsor_list(i) = sponsor;
                    committee_list(i) = committee;
                end
                
                if ~isempty(accuracy_list) && obj.generate_outputs
                    h = figure();
                    hold on
                    title('House Predictive Model Accuracy at t2')
                    xlabel('Accuracy')
                    ylabel('Frequency')
                    grid on
                    histfit(accuracy_list,20)
                    axis([0 100 0 inf])
                    hold off
                    saveas(h,sprintf('%s/house_accuracy_histogram_t2',obj.outputs_directory),'png')
                end
                
                if ~isempty(sponsor_list) && obj.generate_outputs
                    h = figure();
                    hold on
                    title('House Sponsor Count')
                    xlabel('Number of Sponsors')
                    ylabel('Frequency')
                    grid on
                    histfit(sponsor_list,10)
                    axis([0 max(sponsor_list) 0 inf])
                    hold off
                    saveas(h,sprintf('%s/house_sponsor_histogram',obj.outputs_directory),'png')
                end
                
                if ~isempty(committee_list) && obj.generate_outputs
                    h = figure();
                    hold on
                    title('House Committee Member Count')
                    xlabel('Number of Committee Members')
                    ylabel('Frequency')
                    grid on
                    histfit(committee_list,10)
                    axis([0 max(committee_list) 0 inf])
                    hold off
                    saveas(h,sprintf('%s/house_committee_histogram',obj.outputs_directory),'png')
                end
                
                if ~isempty(house_bill_ids)
                    competitive_bills = cell2table(cell(length(house_bill_ids),8),'VariableNames',{'bill_id' 'bill_number' 'title' 'introduced' 'last_action' 'issue_id','sponsors','committee_members'});
                    for i = 1:length(house_bill_ids)
                        competitive_bills{i,'bill_id'} = {obj.bill_set(house_bill_ids(i)).bill_id};
                        competitive_bills{i,'bill_number'} = obj.bill_set(house_bill_ids(i)).bill_number;
                        competitive_bills{i,'title'} = obj.bill_set(house_bill_ids(i)).title;
                        competitive_bills{i,'introduced'} = obj.bill_set(house_bill_ids(i)).date_introduced;
                        competitive_bills{i,'last_action'} = obj.bill_set(house_bill_ids(i)).date_last_action;
                        competitive_bills{i,'issue_id'} = {obj.ISSUE_KEY(obj.bill_set(house_bill_ids(i)).issue_category)};
                        
                        sponsors_names = obj.getSponsorName(obj.bill_set(house_bill_ids(i)).sponsors(1));
                        for j = 2:length(obj.bill_set(house_bill_ids(i)).sponsors)
                            sponsors_names = [sponsors_names ',' obj.getSponsorName(obj.bill_set(house_bill_ids(i)).sponsors(j))]; %#ok<AGROW>
                        end
                        competitive_bills{i,'sponsors'} = {sponsors_names};
                        
                        comittee_ids = [obj.bill_set(house_bill_ids(i)).house_data.committee_votes(end).yes_list ; obj.bill_set(house_bill_ids(i)).house_data.committee_votes(end).no_list];
                        committee_names = obj.getSponsorName(comittee_ids(1));
                        for j = 2:length(comittee_ids)
                            committee_names = [committee_names ',' obj.getSponsorName(comittee_ids(j))]; %#ok<AGROW>
                        end
                        competitive_bills{i,'committee_members'} = {committee_names};
                    end
                    writetable(competitive_bills,sprintf('%s/house_competitive_bills.xlsx',obj.outputs_directory),'WriteRowNames',false);
                end 
            end
            
            if ~isempty(senate_people) && predict_outcomes
                accuracy_list = zeros(1,length(senate_bill_ids));
                sponsor_list = zeros(1,length(senate_bill_ids));
                committee_list = zeros(1,length(senate_bill_ids));
                for i = 1:length(senate_bill_ids)
                    [accuracy, sponsor, committee] = obj.predictOutcomes(senate_bill_ids(i),senate_people,senate_sponsor_chamber_matrix,senate_consistency_matrix,senate_sponsor_committee_matrix,senate_chamber_matrix,obj.generate_outputs,'senate');
                    accuracy_list(i) = accuracy;
                    sponsor_list(i) = sponsor;
                    committee_list(i) = committee;
                end
                
                if ~isempty(accuracy_list) && obj.generate_outputs
                    h = figure();
                    hold on
                    title('Senate Predictive Model Accuracy at t2')
                    xlabel('Accuracy')
                    ylabel('Frequency')
                    grid on
                    histfit(accuracy_list,20)
                    axis([0 100 0 inf])
                    hold off
                    saveas(h,sprintf('%s/senate_accuracy_histogram_t2',obj.outputs_directory),'png')
                end
                
                if ~isempty(sponsor_list) && obj.generate_outputs
                    h = figure();
                    hold on
                    title('Senate Sponsor Count')
                    xlabel('Number of Sponsors')
                    ylabel('Frequency')
                    grid on
                    histfit(sponsor_list,10)
                    axis([0 max(sponsor_list) 0 inf])
                    hold off
                    saveas(h,sprintf('%s/senate_sponsor_histogram',obj.outputs_directory),'png')
                end
                
                if ~isempty(committee_list) && obj.generate_outputs
                    h = figure();
                    hold on
                    title('Senate Committee Member Count')
                    xlabel('Number of Committee Members')
                    ylabel('Frequency')
                    grid on
                    histfit(committee_list,10)
                    axis([0 max(committee_list) 0 inf])
                    hold off
                    saveas(h,sprintf('%s/senate_committee_histogram',obj.outputs_directory),'png')
                end
                
                if ~isempty(senate_bill_ids)
                    competitive_bills = cell2table(cell(length(senate_bill_ids),8),'VariableNames',{'bill_id' 'bill_number' 'title' 'introduced' 'last_action' 'issue_id','sponsors','committee_members'});
                    for i = 1:length(senate_bill_ids)
                        competitive_bills{i,'bill_id'} = {obj.bill_set(senate_bill_ids(i)).bill_id};
                        competitive_bills{i,'bill_number'} = obj.bill_set(senate_bill_ids(i)).bill_number;
                        competitive_bills{i,'title'} = obj.bill_set(senate_bill_ids(i)).title;
                        competitive_bills{i,'introduced'} = obj.bill_set(senate_bill_ids(i)).date_introduced;
                        competitive_bills{i,'last_action'} = obj.bill_set(senate_bill_ids(i)).date_last_action;
                        competitive_bills{i,'issue_id'} = {obj.ISSUE_KEY(obj.bill_set(senate_bill_ids(i)).issue_category)};
                        
                        sponsors_names = obj.getSponsorName(obj.bill_set(senate_bill_ids(i)).sponsors(1));
                        for j = 2:length(obj.bill_set(senate_bill_ids(i)).sponsors)
                            sponsors_names = [sponsors_names ',' obj.getSponsorName(obj.bill_set(senate_bill_ids(i)).sponsors(j))]; %#ok<AGROW>
                        end
                        competitive_bills{i,'sponsors'} = {sponsors_names};
                        
                        comittee_ids = [obj.bill_set(senate_bill_ids(i)).senate_data.committee_votes(end).yes_list ; obj.bill_set(senate_bill_ids(i)).senate_data.committee_votes(end).no_list];
                        committee_names = obj.getSponsorName(comittee_ids(1));
                        for j = 2:length(comittee_ids)
                            committee_names = [committee_names ',' obj.getSponsorName(comittee_ids(j))]; %#ok<AGROW>
                        end
                        competitive_bills{i,'committee_members'} = {committee_names};
                    end
                    writetable(competitive_bills,sprintf('%s/senate_competitive_bills.xlsx',obj.outputs_directory),'WriteRowNames',false);
                end
            end
            
            tic
            monte_carlo_number = 100;
            bill_target = 10; %length(house_bill_ids)
            if ~isempty(house_people) && predict_montecarlo
                
                accuracy_list = zeros(bill_target,monte_carlo_number);
                legislators_list = cell(bill_target,monte_carlo_number);
                bill_ids = zeros(1,bill_target);
                
                bill_hit = 1;
                i = 0;
                while bill_hit <= bill_target
                    i = i + 1;
                    successful = 1;
                    for j = 1:monte_carlo_number
                        rng(j);
                        [accuracy,~,~,legislators] = obj.predictOutcomes(house_bill_ids(i),house_people,house_sponsor_chamber_matrix,house_consistency_matrix,house_sponsor_committee_matrix,house_chamber_matrix,0,'house');
                        
                        if ~isempty(legislators)
                            accuracy_list(bill_hit,j) = accuracy;
                            legislators_list{bill_hit,j} = legislators;
                        else
                            successful = 0;
                            break
                        end
                        fprintf('%i %i\n',bill_hit,j)
                    end
                    
                    if successful
                        bill_ids(bill_hit) = house_bill_ids(i);
                        bill_hit = bill_hit + 1;
                    end
                end
                
                h = figure();
                hold on
                title('House Prediction Histogram')
                boxplot(accuracy_list',bill_ids)
                xlabel('Bills')
                ylabel('Accuracy')
                hold off
                saveas(h,sprintf('%s/house_prediction_histogram',obj.outputs_directory),'png')
                
                save(sprintf('%s/house_predictive_model.mat',obj.outputs_directory),'accuracy_list','legislators_list');
            end
            toc
            
            tic
            monte_carlo_number = 100;
            bill_target = 10; %length(senate_bill_ids)
            if ~isempty(senate_people) && predict_montecarlo
                
                accuracy_list = zeros(bill_target,monte_carlo_number);
                legislators_list = cell(bill_target,monte_carlo_number);
                bill_ids = zeros(1,bill_target);
                
                bill_hit = 1;
                i = 0;
                while bill_hit <= bill_target
                    i = i + 1;
                    successful = 1;
                    for j = 1:monte_carlo_number
                        rng(j);
                        [accuracy,~,~,legislators] = obj.predictOutcomes(senate_bill_ids(i),senate_people,senate_sponsor_chamber_matrix,senate_consistency_matrix,senate_sponsor_committee_matrix,senate_chamber_matrix,0,'senate');
                        
                        if ~isempty(legislators)
                            accuracy_list(bill_hit,j) = accuracy;
                            legislators_list{bill_hit,j} = legislators;
                        else
                            successful = 0;
                            break
                        end
                        fprintf('%i %i\n',bill_hit,j)
                    end
                    
                    if successful
                        bill_ids(bill_hit) = senate_bill_ids(i);
                        bill_hit = bill_hit + 1;
                    end
                end
                
                h = figure();
                hold on
                title('Senate Prediction Histogram')
                boxplot(accuracy_list',bill_ids)
                xlabel('Bills')
                ylabel('Accuracy')
                hold off
                saveas(h,sprintf('%s/senate_prediction_histogram',obj.outputs_directory),'png')
                
                save(sprintf('%s/senate_predictive_model.mat',obj.outputs_directory),'accuracy_list','legislators_list')
            end
            toc
            
            var_list = who;
            var_list = var_list(~ismember(var_list,'obj'));
            for i = 1:length(var_list)
                assignin('base',var_list{i},eval(var_list{i}));
            end
        end
    end
end