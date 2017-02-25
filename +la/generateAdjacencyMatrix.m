function generateAdjacencyMatrix(processed,specific)

adjacency_matrix = zeros(length(unique(processed.(specific))),length(unique(processed.learning_coded)));

for i = 1:length(processed.issue_codes)
    adjacency_matrix(processed.(specific)(i),processed.learning_coded(i)) = adjacency_matrix(processed.(specific)(i),processed.learning_coded(i)) + 1;
end

csvwrite(sprintf('+la/temp/testdata_%s_%s.csv',specific,date),adjacency_matrix);

end