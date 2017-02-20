function slocRunner()

target = '../tags';

list = dir(target);

output = zeros(length(list)-1,8);
names  = cell(1,length(list)-1);

count = 1;
for i = 1:length(list)
    if any(strfind(list(i).name(end),'.'))
        continue
    else
        results = util.slocDir([target '/' list(i).name]);
        if count == 1
            output(count,1:4) = results;
        else
            output(count,:) = [results results(1)-output(count-1,1) results(2)-output(count-1,2) results(3)-output(count-1,3) results(4)-output(count-1,4)];
        end
        names{count} = list(i).name;
        count        = count + 1;
    end
end
results       = util.slocDir(pwd);
output(end,:) = [results results(1)-output(count-1,1) results(2)-output(count-1,2) results(3)-output(count-1,3) results(4)-output(count-1,4)];
names{end}    = 'Current';

fprintf('Tag        |  Code  |  Comments  |  Blanks  |  Total  |  delta Code  |  delta Comments  |  delta Blanks  |  delta Total  |\n')
fprintf('--------------------------------------------------------------------------------------------------------------------------\n')
fprintf('%9s  |%6i  |%10i  |%8i  |%7i  |      --      |        --        |       --       |      --       |\n',names{1},output(1,1),output(1,2),output(1,3),output(1,4))
for i = 2:length(names)
    fprintf('%9s  |%6i  |%10i  |%8i  |%7i  |%+12i  |%+16i  |%+14i  |%+13i  |\n',names{i},output(i,1),output(i,2),output(i,3),output(i,4),output(i,5),output(i,6),output(i,7),output(i,8))
end

end