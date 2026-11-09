local M = {}
M.names = {"ALLOC", "PUSH", "LOAD", "POP", "SET", "OVERWRITE", "CHECKPOINT"}
local forms = {ALLOC = {"number", "number"}, PUSH = {"source"}, LOAD = {"number", "number"}, POP = {"number"}, SET = {"number", "number", "source"}, OVERWRITE = {"number", "source"}, CHECKPOINT = {"label"}}
local function split(text)
    local fields = {}
    for value in (text .. " "):gmatch("(.-) ") do
        fields[#fields + 1] = value
    end
    return fields
end
function M.read_lines(path)
    local lines = {}
    for line in io.lines(path) do
        lines[#lines + 1] = line
    end
    return lines
end
function M.read_config(path)
    local config = {collectors = {}}
    for _, line in ipairs(M.read_lines(path)) do
        local fields = split(line)
        if fields[1] == "HEAP" then
            config.size = tonumber(fields[2])
        elseif fields[1] == "COLLECTOR" then
            config.collectors[#config.collectors + 1] = {name = fields[2], algorithm = fields[3], young = tonumber(fields[4]) or 0, age = tonumber(fields[5]) or 0}
        elseif fields[1] == "MAPS" then
            config.maps = {table.unpack(fields, 2)}
        elseif fields[1] == "MMU" then
            config.windows = {}
            for i = 2, #fields do
                config.windows[#config.windows + 1] = tonumber(fields[i])
            end
        else
            config.width = tonumber(fields[2])
        end
    end
    return config
end
local function number(text)
    return #text >= 1 and #text <= 4 and text:match("^%d+$") and (#text == 1 or text:sub(1, 1) ~= "0")
end
local function matches(kind, text)
    if kind == "number" then
        return number(text)
    end
    if kind == "source" then
        return text == "-" or number(text)
    end
    return #text >= 1 and #text <= 16 and text:match("^[a-z0-9_]+$") ~= nil
end
function M.parse_line(line, text)
    local tokens = split(text)
    local form = forms[tokens[1]]
    if not form or #tokens ~= #form + 1 then
        return nil, "syntax"
    end
    for i, kind in ipairs(form) do
        if not matches(kind, tokens[i + 1]) then
            return nil, "syntax"
        end
    end
    local command = {line = line, name = tokens[1], pointers = 0, data = 0, slot = 0, field = 0, source = -1, count = 0, label = ""}
    local function source(token)
        return token == "-" and -1 or tonumber(token)
    end
    if command.name == "ALLOC" then
        command.pointers, command.data = tonumber(tokens[2]), tonumber(tokens[3])
    elseif command.name == "PUSH" then
        command.source = source(tokens[2])
    elseif command.name == "LOAD" then
        command.slot, command.field = tonumber(tokens[2]), tonumber(tokens[3])
    elseif command.name == "POP" then
        command.count = tonumber(tokens[2])
    elseif command.name == "SET" then
        command.slot, command.field, command.source = tonumber(tokens[2]), tonumber(tokens[3]), source(tokens[4])
    elseif command.name == "OVERWRITE" then
        command.slot, command.source = tonumber(tokens[2]), source(tokens[3])
    else
        command.label = tokens[2]
    end
    if command.name == "ALLOC" and (command.pointers > 6 or command.data > 24) or command.name == "POP" and command.count == 0 then
        return nil, "range"
    end
    return command
end
return M
