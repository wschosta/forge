function main()

optimize_frontier = 0;
process_algorithm = 1;

awv = 0.3870;
iwv = 1.0262;

% read in processed text data
learning_materials = readtable('data\IN\undergrad\description_learning_materials.xlsx');

common_words = {'and' 'of' 'a' 'an' 'the' 'is' 'or' 'on' 'by' 'for' 'in' 'to' 'bill' 'resolution' 'with' 'various' 'matters' 'program' 'public'};

master_issue_codes = containers.Map([1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16],...
    {'Agriculture','Commerce, Business, Economic Development',...
    'Courts & Judicial','Education','Elections & Apportionment',...
    'Employment & Labor','Environment & Natural Resources',...
    'Family, Children, Human Affairs & Public Health',...
    'Banks & Financial Institutions','Insurance',...
    'Government & Regulatory Reform','Local Government',...
    'Roads & Transportation','Utilities, Energy & Telecommunications',...
    'Ways & Means, Appropriations','Other'});

additional_issue_codes = containers.Map([1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16],...
    {'','firearm',...
    '','Schools student','Advocacy',...
    'Unemployment wage','',...
    'Child immigration',...
    '','',...
    'Access','Records',...
    '','',...
    'Taxation Taxes Tax',''});

[learning_table,data_storage] = la.generateLearningTable(learning_materials,common_words,master_issue_codes,additional_issue_codes);

if optimize_frontier
    
    [accuracy, awv, iwv] = la.optimizeFrontier(location,robust,max_grid_size,iterations,learning_materials,learning_table,data_storage);
    
    fprintf('Max Accuracy %8.3f%% || a %10.2f | i %10.2f \n',accuracy,awv,iwv);
    
end

if process_algorithm
    
    x(1) = awv;
    x(2) = iwv;
    outputs = la.processAlgorithm(x,learning_materials,learning_table,data_storage,0);
    processed = outputs.processed;
    correct   = outputs.correct;
    total     = outputs.total;
    accuracy  = outputs.accuracy;
    
    fprintf('Results: %i of %i (%0.2f%%) || a %10.2f | i %10.2f \n',correct,total,accuracy,awv,iwv);
    
    % manually make the histogram here so it can reflect all the categories    
    figure()
    hold on; grid on;
    
    keys = master_issue_codes.keys;
    tick_values = cell(1,length(keys)+1);
    
    peak = -inf;
    
    for i = 1:length(keys)
        tick_values{i} = sprintf('%i',keys{i});
        
        rectangle('Position',[i-0.5,0,1,sum(processed.issue_codes == keys{i})+0.000001],'FaceColor','b')
        peak = max([peak, sum(processed.issue_codes == keys{i})]);
    end
    
    axis([0.5,16.5,0,peak])
    ax = gca;
    set(ax,'XTick',[keys{:}])
    set(ax,'XTickLabel',tick_values)

    xlabel('Issue Codes')
    ylabel('Frequency')
    title('Distribution of Categorized Bills')
    saveas(gcf,sprintf('learning_algorithm_historgram_%s',date),'png')
    
    writetable(processed,sprintf('learning_algorithm_results_%s.xlsx',date))
    
    data_storage.awv = awv;
    data_storage.iwv = iwv;
    save(sprintf('learning_algorithm_data_%s',date),'learning_table','data_storage');
    save(sprintf('data\\IN\\learning_algorithm_data'),'learning_table','data_storage');
end

end