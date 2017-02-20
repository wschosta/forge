function results = readJSON(file)
fid = fopen(file);

if fid == -1
    warning('CAN''T OPEN FILE')
    results = [];
    return
end

text = fgetl(fid);
tline = fgetl(fid);
while ischar(tline)
    text = [text tline]; %#ok<AGROW>
    tline = fgetl(fid);
end

fclose(fid);

results = util.parse_json(text);

field_name = fieldnames(results);

results = results.(field_name{1});

end