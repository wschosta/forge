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
            
            if exist(sprintf('data/%s/saved_data.mat',obj.state,obj.state),'file') ~= 2 || obj.recompute
                
                % CODED SPECIFICALLY FOR THE INDIANA HOUSE AND SENATE.
                % ABSTRACTABLE TO OTHER STATES, WE JUST NEED TO ADJUST THE
                % CHAMBER DESCRIPTIONS
                
                % Read in the specific 2013-2014 Indiana List
                
                % TODO 2015 people list might have all the information we need?
                house_people = readtable(sprintf('data/%s/people_2013-2014.xlsx',obj.state));
                
                [house_chamber_matrix,house_chamber_votes,...
                    house_sponsor_chamber_matrix,house_sponsor_chamber_votes,...
                    house_committee_matrix,house_committee_votes,...
                    house_sponsor_committee_matrix,house_sponsor_committee_votes,...
                    house_consistency_matrix,bill_ids]  = obj.processHouseVotes(house_people);
                [house_chamber_matrix]           = obj.normalizeVotes(house_chamber_matrix, house_chamber_votes);
                [house_sponsor_chamber_matrix]   = obj.normalizeVotes(house_sponsor_chamber_matrix, house_sponsor_chamber_votes);
                [house_committee_matrix]         = obj.normalizeVotes(house_committee_matrix,house_committee_votes);
                [house_sponsor_committee_matrix] = obj.normalizeVotes(house_sponsor_committee_matrix,house_sponsor_committee_votes);
                
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
                
                house_seat_matrix = obj.processSeatProximity(house_people);
                
                var_list = who;
                var_list = var_list(~ismember(var_list,'obj'));
                save(sprintf('data/%s/saved_data.mat',obj.state),var_list{:})
                
                if obj.generate_outputs
                    
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
                    
                    writetable(house_seat_matrix,sprintf('%s/house_seat_matrix.xlsx',obj.outputs_directory),'WriteRowNames',true);
                    
                    [~,~,~] = rmdir(obj.gif_directory,'s');
                    [~,~,~] = rmdir(obj.histogram_directory,'s');
                    obj.make_gifs = true;
                    obj.make_histograms = true;
                end
            else
                load(sprintf('data/%s/saved_data.mat',obj.state));
            end
            
            if obj.generate_outputs
                
                % PLOTTING
                % Chamber Vote Data
                tic
                obj.generatePlots(house_chamber_matrix,'House','','Legislators','Legislators','Agreement Score','chamber_all')
                obj.generatePlots(house_republicans_chamber_votes,'House','Republicans','Legislators','Legislators','Agreement Score','chamber_R')
                obj.generatePlots(house_democrats_chamber_votes,'House','Democrats','Legislators','Legislators','Agreement Score','chamber_D')
                toc
                
                % Chamber Sponsorship Data
                tic
                obj.generatePlots(house_sponsor_chamber_matrix,'House','Sponsorship','Sponsors','Legislators','Sponsorship Score','chamber_sponsor_all')
                obj.generatePlots(house_republicans_chamber_sponsor,'House','Republican Sponsorship','Sponsors','Legislators','Sponsorship Score','chamber_sponsor_R')
                obj.generatePlots(house_democrats_chamber_sponsor,'House','Democrat Sponsorship','Sponsors','Legislators','Sponsorship Score','chamber_sponsor_D')
                toc
                
                % Committee Vote Data
                tic
                obj.generatePlots(house_committee_matrix,'House Committee','','Legislators','Legislators','Agreement Score','committee_all')
                obj.generatePlots(house_republicans_committee_votes,'House Committee','Republicans','Legislators','Legislators','Agreement Score','committee_R')
                obj.generatePlots(house_democrats_committee_votes,'House Committee','Democrats','Legislators','Legislators','Agreement Score','committee_D')
                toc
                
                % Committee Sponsorship Data
                tic
                obj.generatePlots(house_sponsor_committee_matrix,'House Committee','Sponsorship','Sponsors','Legislators','Sponsorship Score','committee_sponsor_all')
                obj.generatePlots(house_republicans_committee_sponsor,'House Committee','Republican Sponsorship','Sponsors','Legislators','Sponsorship Score','committee_sponsor_R')
                obj.generatePlots(house_democrats_committee_sponsor,'House Committee','Democrat Sponsorship','Sponsors','Legislators','Sponsorship Score','committee_sponsor_D')
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
                    saveas(h,sprintf('%s/histogram_chamber_committee_consistency',obj.outputs_directory),'png')
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
            
            accuracy_list = zeros(1,length(bill_ids));
            sponsor_list = zeros(1,length(bill_ids));
            committee_list = zeros(1,length(bill_ids));
            for i = 1:length(bill_ids)
                [accuracy, sponsor, committee] = obj.predictOutcomes(bill_ids(i),house_people,house_sponsor_chamber_matrix,house_consistency_matrix,house_sponsor_committee_matrix,house_chamber_matrix);
                accuracy_list(i) = accuracy;
                sponsor_list(i) = sponsor;
                committee_list(i) = committee;
            end
            
            if ~isempty(accuracy_list)
                h = figure();
                hold on
                title('Predictive Model Accuracy at t2')
                xlabel('Accuracy')
                ylabel('Frequency')
                grid on
                histfit(accuracy_list,20)
                axis([0 100 0 inf])
                hold off
                saveas(h,sprintf('%s/accuracy_histogram_t2',obj.outputs_directory),'png')
            end
            
            if ~isempty(sponsor_list)
                h = figure();
                hold on
                title('Sponsor Count')
                xlabel('Number of Sponsors')
                ylabel('Frequency')
                grid on
                histfit(sponsor_list,10)
                axis([0 max(sponsor_list) 0 inf])
                hold off
                saveas(h,sprintf('%s/sponsor_histogram',obj.outputs_directory),'png')
            end
            
            if ~isempty(committee_list)
                h = figure();
                hold on
                title('Committee Member Count')
                xlabel('Number of Committee Members')
                ylabel('Frequency')
                grid on
                histfit(committee_list,10)
                axis([0 max(committee_list) 0 inf])
                hold off
                saveas(h,sprintf('%s/committee_histogram',obj.outputs_directory),'png')
            end
            
            if ~isempty(bill_ids)
                competitive_bills = cell2table(cell(length(bill_ids),8),'VariableNames',{'bill_id' 'bill_number' 'title' 'introduced' 'last_action' 'issue_id','sponsors','committee_members'});
                for i = 1:length(bill_ids)
                    competitive_bills{i,'bill_id'} = {obj.bill_set(bill_ids(i)).bill_id};
                    competitive_bills{i,'bill_number'} = obj.bill_set(bill_ids(i)).bill_number;
                    competitive_bills{i,'title'} = obj.bill_set(bill_ids(i)).title;
                    competitive_bills{i,'introduced'} = obj.bill_set(bill_ids(i)).date_introduced;
                    competitive_bills{i,'last_action'} = obj.bill_set(bill_ids(i)).date_last_action;
                    competitive_bills{i,'issue_id'} = {obj.ISSUE_KEY(obj.bill_set(bill_ids(i)).issue_category)};
                    
                    sponsors_names = obj.getSponsorName(obj.bill_set(bill_ids(i)).sponsors(1));
                    for j = 2:length(obj.bill_set(bill_ids(i)).sponsors)
                        sponsors_names = [sponsors_names ',' obj.getSponsorName(obj.bill_set(bill_ids(i)).sponsors(j))]; %#ok<AGROW>
                    end
                    competitive_bills{i,'sponsors'} = {sponsors_names};
                    
                    comittee_ids = [obj.bill_set(bill_ids(i)).house_data.committee_votes(end).yes_list ; obj.bill_set(bill_ids(i)).house_data.committee_votes(end).no_list];
                    committee_names = obj.getSponsorName(comittee_ids(1));
                    for j = 2:length(comittee_ids)
                        committee_names = [committee_names ',' obj.getSponsorName(comittee_ids(j))]; %#ok<AGROW>
                    end
                    competitive_bills{i,'committee_members'} = {committee_names};
                end
                writetable(competitive_bills,sprintf('%s/competitive_bills.xlsx',obj.outputs_directory),'WriteRowNames',false);
            end
            
            var_list = who;
            var_list = var_list(~ismember(var_list,'obj'));
            for i = 1:length(var_list)
                assignin('base',var_list{i},eval(var_list{i}));
            end
        end
   end
end