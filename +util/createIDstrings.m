function ids = createIDstrings(sponsor_codes,varargin)
% CREATEIDSTRINGS
% Create ID strings from numbers

% Create the ID strings
ids = arrayfun(@(x) ['id' num2str(x)], sponsor_codes, 'Uniform', 0);

% Because it's a common use, there's the option to take only the matched
% values
if ~isempty(varargin)
   ids = ids(util.CStrAinBP(ids,varargin{1})); 
end

end