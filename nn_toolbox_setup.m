load('C:\Users\Walter\Desktop\full_forge\+la\description_learning_materials.mat')
a = [data_storage.unique_text_store{:}];

a = unique(a);
b = zeros(32,length(a));
for j = 1:32
    b(j,util.CStrAinBP(data_storage.unique_text_store{j},a)) = 1; 
end

clear data_storage

n = 12000;

p = randperm(length(learning_materials.parsed_text),n);

inputs  = zeros(length(a),n);
targets = zeros(32,n);
for i = 1:n
 
    x = util.CStrAinBP(learning_materials.parsed_text{p(i)},a);
    [y,~,z] = unique(learning_materials.parsed_text{p(i)}(x));
    count = hist(z,length(y));
    
    inputs(util.CStrAinBP(a,learning_materials.parsed_text{p(i)}),i) = count; 
    targets(learning_materials.issue_codes(i),i) = 1;
end

clear learning_materials