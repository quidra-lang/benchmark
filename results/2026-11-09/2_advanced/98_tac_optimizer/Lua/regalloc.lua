local P = require("tac_parser")
local C = require("cfg")
local D = require("dataflow")
local R = {}
local base = 1000000000
local function power(exponent)
    local result = {}
    for i = 1, exponent // 9 do result[i] = 0 end
    local digit = 1
    for _ = 1, exponent % 9 do digit = digit * 10 end
    result[#result + 1] = digit
    return result
end
local function add(a, b)
    local result, carry = {}, 0
    for i = 1, math.max(#a, #b) do
        local value = (a[i] or 0) + (b[i] or 0) + carry
        result[i], carry = value % base, value // base
    end
    if carry > 0 then result[#result + 1] = carry end
    return result
end
local function multiply(a, factor)
    local result, carry = {}, 0
    for i, digit in ipairs(a) do
        local value = digit * factor + carry
        result[i], carry = value % base, value // base
    end
    while carry > 0 do result[#result + 1], carry = carry % base, carry // base end
    while #result > 1 and result[#result] == 0 do table.remove(result) end
    return result
end
local function compare(a, b)
    if #a ~= #b then return #a < #b and -1 or 1 end
    for i = #a, 1, -1 do if a[i] ~= b[i] then return a[i] < b[i] and -1 or 1 end end
    return 0
end
function R.cost_string(value)
    local result = tostring(value[#value])
    for i = #value - 1, 1, -1 do result = result .. string.format("%09d", value[i]) end
    return result
end
function R.allocate(fn, graph, flow, registers)
    local nodes = {}
    for _, parameter in ipairs(fn.parameters) do nodes[parameter] = true end
    for number, instruction in ipairs(graph.instructions) do
        if graph.reachable[graph.block_of[number]] then
            for _, variable in ipairs(P.used(instruction)) do nodes[variable] = true end
            if instruction.destination then nodes[instruction.destination] = true end
        end
    end
    local result = { nodes = C.keys(nodes), neighbors = {}, costs = {}, partners = {}, order = {}, potential = {}, colors = {}, spills = {} }
    for node in pairs(nodes) do result.neighbors[node], result.costs[node], result.partners[node] = {}, { 0 }, {} end
    local function edge(a, b)
        if a ~= b then result.neighbors[a][b], result.neighbors[b][a] = true, true end
    end
    for _, number in ipairs(C.keys(graph.reachable)) do
        local block, state = graph.blocks[number], C.copy(flow.live_out[number])
        for i = #block.instructions, 1, -1 do
            local instruction = graph.instructions[block.instructions[i]]
            if instruction.destination then
                for variable in pairs(state) do
                    if variable ~= instruction.destination and not (instruction.kind == "copy" and variable == instruction.a) then edge(instruction.destination, variable) end
                end
            end
            state = D.live_transfer(instruction, state)
        end
        local weight = power(graph.depth[number])
        for _, index in ipairs(block.instructions) do
            local instruction = graph.instructions[index]
            local occurrences = P.used(instruction)
            if instruction.destination then occurrences[#occurrences + 1] = instruction.destination end
            for _, variable in ipairs(occurrences) do result.costs[variable] = add(result.costs[variable], weight) end
        end
    end
    local entry = C.copy(flow.live_in[1])
    for _, parameter in ipairs(fn.parameters) do entry[parameter] = true end
    for _, parameter in ipairs(fn.parameters) do
        result.costs[parameter] = add(result.costs[parameter], { 1 })
        for variable in pairs(entry) do edge(parameter, variable) end
    end
    for _, instruction in ipairs(graph.instructions) do
        if instruction.kind == "copy" and type(instruction.a) == "string" and instruction.a ~= instruction.destination then
            if result.partners[instruction.destination] then result.partners[instruction.destination][instruction.a] = true end
            if result.partners[instruction.a] then result.partners[instruction.a][instruction.destination] = true end
        end
    end
    local remaining = C.copy(nodes)
    while next(remaining) do
        local degrees, simple = {}, {}
        for node in pairs(remaining) do
            degrees[node] = C.count(C.intersect(C.copy(result.neighbors[node]), remaining))
            if degrees[node] < registers then simple[#simple + 1] = node end
        end
        local chosen
        if #simple > 0 then
            table.sort(simple, function(a, b) return degrees[a] < degrees[b] or degrees[a] == degrees[b] and a < b end)
            chosen = simple[1]
        else
            for _, node in ipairs(C.keys(remaining)) do
                if not chosen then chosen = node
                else
                    local order = compare(multiply(result.costs[node], degrees[chosen]), multiply(result.costs[chosen], degrees[node]))
                    if order < 0 or order == 0 and node < chosen then chosen = node end
                end
            end
            result.potential[#result.potential + 1] = { chosen, degrees[chosen] }
        end
        result.order[#result.order + 1], remaining[chosen] = chosen, nil
    end
    for i = #result.order, 1, -1 do
        local node, occupied = result.order[i], {}
        for neighbor in pairs(result.neighbors[node]) do local color = result.colors[neighbor]; if color ~= nil then occupied[color] = true end end
        local smallest, preferred
        for color = 0, registers - 1 do if not occupied[color] then smallest = color; break end end
        if smallest == nil then result.spills[node] = true
        else
            for partner in pairs(result.partners[node]) do
                local color = result.colors[partner]
                if color ~= nil and not occupied[color] and (preferred == nil or color < preferred) then preferred = color end
            end
            result.colors[node] = preferred or smallest
        end
    end
    return result
end
return R
