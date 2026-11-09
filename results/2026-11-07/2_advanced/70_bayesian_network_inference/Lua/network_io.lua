local M = {}
local function words(line, separator)
    local result = {}
    for value in line:gmatch(separator or '%S+') do result[#result + 1] = value end
    return result
end
function M.read_inputs()
    local lines, network = {}, {names = {}, states = {}, parents = {}, expert = {}, index = {}}
    for line in io.lines('input/network.txt') do if line ~= '' and line:sub(1, 1) ~= '#' then lines[#lines + 1] = line end end
    local position = 1
    while position <= #lines do
        local fields = words(lines[position])
        position = position + 1
        if fields[1] == 'VARIABLE' then
            local v = #network.names + 1
            network.index[fields[2]], network.names[v], network.states[v], network.parents[v] = v, fields[2], {}, {}
            for i = 3, #fields do network.states[v][#network.states[v] + 1] = fields[i] end
        elseif fields[1] == 'PARENTS' then
            local v = network.index[fields[2]]
            for i = 3, #fields do network.parents[v][#network.parents[v] + 1] = network.index[fields[i]] end
        else
            local v, row_count, cpt = network.index[fields[2]], 1, {}
            for _, parent in ipairs(network.parents[v]) do row_count = row_count * #network.states[parent] end
            for _ = 1, row_count do
                local row = {}
                for _, probability in ipairs(words(lines[position])) do row[#row + 1] = tonumber(probability) end
                cpt[#cpt + 1], position = row, position + 1
            end
            network.expert[v] = cpt
        end
    end
    local params, queries, samples, columns, state_index = {sources = {}}, {}, {}, nil, {}
    for v, states in ipairs(network.states) do state_index[v] = {}; for s, state in ipairs(states) do state_index[v][state] = s end end
    for line in io.lines('input/samples.csv') do
        local fields = words(line, '[^,]+')
        if not columns then columns = {}; for i, name in ipairs(fields) do columns[i] = network.index[name] end
        else
            local sample = {}
            for i, state in ipairs(fields) do local v = columns[i]; sample[v] = state_index[v][state] end
            samples[#samples + 1] = sample
        end
    end
    for line in io.lines('input/params.txt') do
        local fields = words(line)
        if fields[1] == 'PSEUDOCOUNT' then params.alpha = tonumber(fields[2])
        elseif fields[1] == 'ELIMINATION' then params.method = fields[2]
        elseif fields[1] == 'ORDER' then params.order = {}; for i = 2, #fields do params.order[#params.order + 1] = network.index[fields[i]] end
        elseif fields[1] == 'ENUMERATION_LIMIT' then params.limit = tonumber(fields[2])
        elseif fields[1] == 'SEED' then params.seed = tonumber(fields[2])
        else params.sources[network.index[fields[2]]] = fields[3] end
    end
    for line in io.lines('input/queries.txt') do queries[#queries + 1] = line end
    return network, samples, queries, params
end
return M
