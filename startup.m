function startup()
% STARTUP
% Runs when matlab is launched in this folder

restoredefaultpath;

% Get the full directory listing
dir_list = genpath(pwd);

% Loop over all of the directories
while(~isempty(dir_list))
    
    % Separate out each directory at the path separator (/)
    [a_dir, dir_list] = strtok(dir_list,pathsep());  %#ok<STTOK>

    
    % this allows us to ignore the things that don't need to be aded to the
    % path, specifically the svn, git, Archive, and Profiler directories
    if isempty(regexp(a_dir,'(\svn.|\.svn|\.git|Archive|Profiler|undergrad|tmp|data|legiscan_data|profile_results|congrssional_archive|webcrawler|reference)','ONCE'))
        % add it to the path
        addpath(a_dir)
    end
end

userpath(pwd);

end