function findSimilarCategories(adjacency_matrix)

true_categories  = size(adjacency_matrix,1);
coded_categories = size(adjacency_matrix,2);

category_block = meshgrid((1:true_categories),ones(coded_categories,1))';

category_block(adjacency_matrix == 0) = NaN;

sorted_block = nan(true_categories,coded_categories);

for i = 1:coded_categories

[~,index] = sortrows(adjacency_matrix(:,i));

sorted_block(:,i) = category_block(index,i);

end