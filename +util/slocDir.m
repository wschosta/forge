%SLOCDIR Counts number source lines of code.
function locSum = slocDir(directory)

locSum = [0 0 0 0];

if any(strfind(directory(end),'.'))
    return;
end

list = dir(directory);

for i = 1:length(list)
    if list(i).isdir
        locSum = locSum + util.slocDir([directory '\' list(i).name]);
    elseif any(strfind(list(i).name(end-1:end),'.m'))
        [s, c, b, t] = sloc([directory '\' list(i).name]);
        locSum = [locSum(1) + s locSum(2) + c locSum(3) + b locSum(4) + t];
    end
    
end

end

function [sl, cl, bl, tl] = sloc(file)
%SLOC Counts number source lines of code.
%   SL = SLOC(FILE) returns the line count for FILE.  If there are multiple
%   functions in one file, subfunctions are not counted separately, but
%   rather together.
%
%   The following lines are not counted as a line of code:
%   (1) The "function" line
%   (2) A line that is continued from the previous line --> ...
%   (3) A comment line, a line that starts with --> % or a line that is
%       part of a block comment (   %{...%}   )
%   (4) A blank line
%
%   Note: If more than one statement is on the line, it counts that as one
%   line of code.  For instance the following:
%
%        minx = 32; maxx = 100;
%
%   is considered to be one line of code.  Also, if the creation of a
%   matrix is continued onto several line without the use of '...', SLOC
%   will deem that as separate lines of code.  Using '...' will "tie" the
%   lines together.
%
%   Example:
%   ========
%      sl = sloc('sloc')
%      sl =
%                41

%   Copyright 2004-2005 MathWorks, Inc.
%   Raymond S. Norris (rayn@mathworks.com)
%   $Revision: 1.4 $ $Date: 2006/03/08 19:50:30 $

% Check to see if the ".m" is missing from the M-file name
fid = fopen(file,'r');

sl = 0;
cl = 0;
bl = 0;

previous_line = '-99999';
inblockcomment = false;

while true
    
    % Get the next line
    m_line = fgetl(fid);
    
    % If line is -1, we've reached the end of the file
    if m_line==-1
        break
    end
    
    % The Profiler doesn't include the "function" line of a function, so
    % skip it.  Because nested functions may be indented, trim the front of
    % the line of code.  Since we are string trimming the line, we may as
    % well check here if the resulting string it empty.  If any of the above
    % is true, just continue onto the next line.
    m_line = strtrim(m_line);
    if strncmp(m_line,'function ',9) || isempty(m_line)
        bl = bl + 1;
        continue
    end
    
    % In R14, block comments where introduced ( %{...%} )
    if length(m_line)>1 && ...
            strcmp(m_line(1:2),'%{')
        inblockcomment = true;
    elseif length(previous_line)>1 && ...
            strcmp(previous_line(1:2),'%}')
        inblockcomment = false;
    end
    
    % Check if comment line or if line continued from previous line
    if ~strcmp(m_line(1),'%') && ...
            ~(length(previous_line)>2 && ...
            strcmp(previous_line(end-2:end),'...') && ...
            ~strcmp(previous_line(1),'%')) && ...
            ~inblockcomment
        sl = sl+1;
    else
        cl = cl+1;
    end
    
    % Keep track of current line to see if the next line is a continuation
    % of the current
    previous_line = m_line;
end

tl = sl + cl + bl;

fclose(fid);

end