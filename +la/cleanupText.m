function [text,weight] = cleanupText(text,cleanup_text)
% CLEANUPTEXT
% Cleanup the text in the learning algorithm learning set

% Split out individual words

if ~isempty(text)

    if ~iscell(text)
        text = regexp(regexprep(text,{'(\d+\w*)',' \w{1,2} ','\<(\\)?[pb]\>'},{' ' ' ' ' '}),'\W+|\s+','split');
        
        if iscell(text{1}) && length(text) == 1
            text = text{:};
        end
    end
    % Remove matching words
    text(util.CStrAinBP(upper(text),upper(cleanup_text))) = [];
    
    % Remove empty cells
    text = upper(text(~cellfun(@isempty,text)));
    
    [text,~,c] = unique(text);
    
    % Using the column index and length, generate the count
    weight     = hist(c,length(text))';
elseif iscell(text)
    text = '';
    weight = 0;
else
    weight = 0;
end

end