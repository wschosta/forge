function startup()

dir_list = genpath(pwd);

while(~isempty(dir_list))
    
    [a_dir, dir_list] = strtok(dir_list,pathsep());  %#ok<STTOK>
    
    if isempty(regexp(a_dir,'(\svn.|\.git|Archive|Profiler)','ONCE'))
        addpath(a_dir)
    end

end

end