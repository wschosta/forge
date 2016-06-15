function startup()
% STARTUP
% Runs when matlab is launched in this folder

% Get the full directory listing
dir_list = genpath(pwd);

% Loop over all of the directories
while(~isempty(dir_list))
    
    % Separate out each directory at the path separator (/)
    [a_dir, dir_list] = strtok(dir_list,pathsep());  %#ok<STTOK>
    
    % this allows us to ignore the things that don't need to be aded to the
    % path, specifically the svn, git, Archive, and Profiler directories
    if isempty(regexp(a_dir,'(\svn.|\.git|Archive|Profiler|undergrad)','ONCE'))
        % add it to the path
        addpath(a_dir)
    end

end

end