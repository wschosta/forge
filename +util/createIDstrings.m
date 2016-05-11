function ids = createIDstrings(sponsor_codes)

ids = arrayfun(@(x) ['id' num2str(x)], sponsor_codes, 'Uniform', 0);

end