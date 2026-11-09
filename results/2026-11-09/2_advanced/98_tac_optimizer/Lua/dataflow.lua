local P = require("tac_parser")
local C = require("cfg")
local D = {}
D.__index = D
function D.reaching_transfer(instruction, number, state)
    local result = C.copy(state)
    if instruction.destination then
        local prefix = instruction.destination .. ":"
        for definition in pairs(result) do if definition:sub(1, #prefix) == prefix then result[definition] = nil end end
        result[prefix .. number] = true
    end
    return result
end
function D.live_transfer(instruction, state)
    local result = C.copy(state)
    if instruction.destination then result[instruction.destination] = nil end
    for _, variable in ipairs(P.used(instruction)) do result[variable] = true end
    return result
end
function D:expression_transfer(instruction, _, state)
    local result = C.copy(state)
    local expression = P.expression(instruction)
    if expression then result[expression] = true end
    for key in pairs(result) do
        local value = self.expressions[key]
        if instruction.kind == "store" and value.kind == "load" and instruction.name == value.name
            or instruction.kind == "call" and value.kind == "load"
            or instruction.destination and (value.a == instruction.destination or value.kind == "bin" and value.b == instruction.destination) then
            result[key] = nil
        end
    end
    return result
end
function D.copy_transfer(instruction, _, state)
    local result = C.copy(state)
    if instruction.destination then
        for key in pairs(result) do
            local first, second = key:match("^([^:]+):(.+)$")
            if first == instruction.destination or second == instruction.destination then result[key] = nil end
        end
    end
    if instruction.kind == "copy" and type(instruction.a) == "string" and instruction.a ~= instruction.destination then
        result[instruction.destination .. ":" .. instruction.a] = true
    end
    return result
end
function D.new(graph)
    local result = setmetatable({ graph = graph, expressions = {}, iterations = {}, live_before = {}, live_after = {} }, D)
    local expressions, copies = {}, {}
    for number, instruction in ipairs(graph.instructions) do
        if graph.reachable[graph.block_of[number]] then
            local expression = P.expression(instruction)
            if expression then expressions[expression], result.expressions[expression] = true, instruction end
            if instruction.kind == "copy" and type(instruction.a) == "string" and instruction.a ~= instruction.destination then
                copies[instruction.destination .. ":" .. instruction.a] = true
            end
        end
    end
    local expression_transfer = function(instruction, number, state) return result:expression_transfer(instruction, number, state) end
    result.reaching_in, result.reaching_out = result:forward("reaching", D.reaching_transfer, {})
    result.live_in, result.live_out = result:liveness()
    result.expression_in, result.expression_out = result:forward("expressions", expression_transfer, expressions)
    result.copy_in, result.copy_out = result:forward("copies", D.copy_transfer, copies)
    result.reaching_before = result:boundaries(result.reaching_in, D.reaching_transfer)
    result.expression_before = result:boundaries(result.expression_in, expression_transfer)
    result.copy_before = result:boundaries(result.copy_in, D.copy_transfer)
    for _, block_number in ipairs(C.keys(graph.reachable)) do
        local state, block = C.copy(result.live_out[block_number]), graph.blocks[block_number]
        for i = #block.instructions, 1, -1 do
            local number = block.instructions[i]
            result.live_after[number] = C.copy(state)
            state = D.live_transfer(graph.instructions[number], state)
            result.live_before[number] = C.copy(state)
        end
    end
    return result
end
function D:forward(kind, transfer, universe)
    local graph, incoming, outgoing, iterations = self.graph, {}, {}, 0
    for number in pairs(graph.reachable) do outgoing[number] = C.copy(universe) end
    while true do
        local changed = false
        iterations = iterations + 1
        for _, number in ipairs(graph.reverse_postorder) do
            local predecessors, state = graph.reachable_predecessors[number], {}
            if kind == "reaching" then
                for _, predecessor in ipairs(predecessors) do C.union(state, outgoing[predecessor]) end
                if number == 1 then for _, parameter in ipairs(graph.fn.parameters) do state[parameter .. ":0"] = true end end
            elseif number ~= 1 then
                state = C.copy(outgoing[predecessors[1]])
                for i = 2, #predecessors do C.intersect(state, outgoing[predecessors[i]]) end
            end
            incoming[number] = C.copy(state)
            for _, index in ipairs(graph.blocks[number].instructions) do state = transfer(graph.instructions[index], index, state) end
            if not C.equal(state, outgoing[number]) then outgoing[number], changed = state, true end
        end
        if not changed then self.iterations[kind] = iterations; return incoming, outgoing end
    end
end
function D:liveness()
    local graph, incoming, outgoing, iterations = self.graph, {}, {}, 0
    for number in pairs(graph.reachable) do incoming[number] = {} end
    while true do
        local changed = false
        iterations = iterations + 1
        for _, number in ipairs(graph.postorder) do
            local block, state = graph.blocks[number], {}
            for _, successor in ipairs(block.successors) do C.union(state, incoming[successor]) end
            outgoing[number] = C.copy(state)
            for i = #block.instructions, 1, -1 do state = D.live_transfer(graph.instructions[block.instructions[i]], state) end
            if not C.equal(state, incoming[number]) then incoming[number], changed = state, true end
        end
        if not changed then self.iterations.liveness = iterations; return incoming, outgoing end
    end
end
function D:boundaries(incoming, transfer)
    local result, graph = {}, self.graph
    for _, number in ipairs(C.keys(graph.reachable)) do
        local state = C.copy(incoming[number])
        for _, index in ipairs(graph.blocks[number].instructions) do
            result[index] = C.copy(state)
            state = transfer(graph.instructions[index], index, state)
        end
    end
    return result
end
return D
