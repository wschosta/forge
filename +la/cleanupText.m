function [text,weight] = cleanupText(text,cleanup_text)
% CLEANUPTEXT
% Cleanup the text in the learning algorithm learning set

% Split out individual words
text = regexp(text,'\W|\s+','split');

if iscell(text{1})
    text = text{:};
end

% Remove matching words
text = upper(text(~ismember(upper(text),upper(cleanup_text))));

% Remove empty cells
text = text(~cellfun(@isempty,text));

% Create the weighting structure
weight = ones(length(text),1);

end