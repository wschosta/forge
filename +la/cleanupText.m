function [text,weight] = cleanupText(text,cleanup_text)
% CLEANUPTEXT
% Cleanup the text in the learning algorithm learning set

% Split out individual words

if iscell(text)
    weight = ones(length(text),1);
    return
end

if ~isempty(text) && ~iscell(text)

    text = regexp(regexprep(text,{'(\d+\w*)',' \w{1,2} ','\<(\\)?[pb]\>'},{' ' ' ' ' '}),'\W+|\s+','split');
    
    if iscell(text{1}) && length(text) == 1
        text = text{:};
    end
    
    % Remove matching words
    text(util.CStrAinBP(upper(text),upper(cleanup_text))) = [];
    
    % Remove empty cells
    text = upper(text(~cellfun(@isempty,text)));
    
    % Create the weighting structure
    weight = ones(length(text),1);
else
    text = '';
    weight = 0;
end

end