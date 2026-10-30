local Input = {}
Input.order = {"layering", "width", "promotion", "heuristic", "sweeps", "node_sep", "dummy_sep", "layer_gap", "direction", "sifting", "reduce", "restarts", "seed"}
Input.defaults = {layering = "longest", width = 4, promotion = "off", heuristic = "barycenter", sweeps = 12,
    node_sep = 2, dummy_sep = 1, layer_gap = 3, direction = "TB", sifting = "off", reduce = "off", restarts = 0, seed = 1}
local choices = {layering = {longest = true, coffman = true}, promotion = {on = true, off = true},
    heuristic = {barycenter = true, median = true}, direction = {TB = true, BT = true, LR = true, RL = true},
    sifting = {on = true, off = true}, reduce = {on = true, off = true}}
local ranges = {width = {1, 40}, sweeps = {0, 50}, node_sep = {1, 9}, dummy_sep = {1, 9}, layer_gap = {2, 9}, restarts = {0, 9}, seed = {1, 2147483646}}

function Input.copy(items)
    local result = {}
    for key, value in pairs(items) do result[key] = value end
    return result
end

local function setting(name, word)
    if choices[name] then return choices[name][word] and word or nil end
    local bounds = ranges[name]
    if bounds and #word >= 1 and #word <= 10 and word:match("^%d+$") then
        local value = tonumber(word)
        if value >= bounds[1] and value <= bounds[2] then return value end
    end
end

local function lines(name)
    local result, number = {}, 0
    for line in io.lines("input/" .. name) do
        number = number + 1
        if line ~= "" and line:sub(1, 1) ~= "#" then
            local fields = {}
            for word in line:gmatch("%S+") do fields[#fields + 1] = word end
            result[#result + 1] = {number = number, fields = fields}
        end
    end
    return result
end

function Input.read_defaults()
    local settings = Input.copy(Input.defaults)
    for _, record in ipairs(lines("params.txt")) do settings[record.fields[1]] = setting(record.fields[1], record.fields[2]) end
    return settings
end

local function accept(graph, f)
    if f[1] == "OPTION" then
        local value = setting(f[2], f[3])
        if value == nil then return "bad_option" end
        graph.settings[f[2]] = value
    elseif f[1] == "NODE" then
        local id = tonumber(f[2])
        if graph.nodes[id] then return "duplicate_node" end
        if graph.node_count == 40 then return "too_many_nodes" end
        graph.nodes[id], graph.node_count = f[3], graph.node_count + 1
    else
        local first, second = tonumber(f[2]), tonumber(f[3])
        if not graph.nodes[first] or not graph.nodes[second] then return "unknown_node" end
        if f[1] == "PATH" then graph.path = {first, second}
        elseif first == second then graph.self_loops = graph.self_loops + 1
        elseif graph.edge_set[first .. ":" .. second] then graph.duplicates = graph.duplicates + 1
        else
            graph.edge_set[first .. ":" .. second] = true
            graph.edges[#graph.edges + 1] = {first, second}
        end
    end
end

function Input.read_graphs(defaults)
    local graphs, graph = {}, nil
    for _, record in ipairs(lines("graphs.txt")) do
        local f = record.fields
        if f[1] == "GRAPH" then
            graph = {name = f[2], settings = Input.copy(defaults), nodes = {}, node_count = 0, edges = {},
                edge_set = {}, self_loops = 0, duplicates = 0}
            graphs[#graphs + 1] = graph
        elseif f[1] == "END" then
            if not graph.error and graph.node_count == 0 then graph.error = {kind = "no_nodes", line = record.number} end
        elseif not graph.error then
            local error = accept(graph, f)
            if error then graph.error = {kind = error, line = record.number} end
        end
    end
    return graphs
end

return Input
