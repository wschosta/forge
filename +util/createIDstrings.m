function ids = createIDstrings(sponsor_codes,varargin)

ids = arrayfun(@(x) ['id' num2str(x)], sponsor_codes, 'Uniform', 0);

if ~isempty(varargin)
   ids = ids(ismember(ids,varargin{1})); 
end

end