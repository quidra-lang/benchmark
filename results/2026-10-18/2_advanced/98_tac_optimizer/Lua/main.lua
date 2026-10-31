local P = require("tac_parser")
local C = require("cfg")
local D = require("dataflow")
local O = require("optimizations")
local R = require("regalloc")
local pass_order = { "constprop", "copyprop", "cse", "dce", "licm", "unreachable" }
local versions = { "original", "optimized", "allocated" }
local function append(result, values) for _, value in ipairs(values) do result[#result + 1] = value end end
local function list(values, prefix)
    if #values == 0 then return "-" end
    local result = {}
    for i, value in ipairs(values) do result[i] = (prefix or "") .. tostring(value) end
    return table.concat(result, ",")
end
local function reaching_numbers(flow, number, variable)
    local result, prefix = {}, variable .. ":"
    for key in pairs(flow.reaching_before[number]) do if key:sub(1, #prefix) == prefix then result[tonumber(key:sub(#prefix + 1))] = true end end
    return result
end
local function inside_definitions(graph, loop, definitions)
    local result = {}
    for number in pairs(definitions) do if number ~= 0 and loop.blocks[graph.block_of[number]] then result[number] = true end end
    return result
end
local function constant_value(graph, definitions)
    if not next(definitions) or definitions[0] then return nil end
    local value
    for number in pairs(definitions) do
        local instruction = graph.instructions[number]
        if instruction.kind ~= "copy" or type(instruction.a) ~= "number" or value ~= nil and value ~= instruction.a then return nil end
        value = instruction.a
    end
    return value
end
local function propagation(fn, graph, flow, constants)
    local replacements, records = {}, {}
    for number, original in ipairs(graph.instructions) do
        if graph.reachable[graph.block_of[number]] then
            local instruction = P.copy(original)
            local available = {}
            if not constants then
                for pair in pairs(flow.copy_before[number]) do local a, b = pair:match("^([^:]+):(.+)$"); available[a] = b end
            end
            for _, field in ipairs(P.fields(original)) do
                local variable = original[field]
                if type(variable) == "string" then
                    local value
                    if constants then value = constant_value(graph, reaching_numbers(flow, number, variable)) else value = available[variable] end
                    if value ~= nil then
                        instruction[field] = value
                        records[#records + 1] = "#" .. number .. ": " .. variable .. " -> " .. tostring(value)
                    end
                end
            end
            if constants then
                local result = O.fold(instruction)
                if not result then records[#records + 1] = "#" .. number .. ": delete " .. P.string(instruction); replacements[number] = {}
                else
                    if result ~= instruction then records[#records + 1] = "#" .. number .. ": fold " .. P.string(result) end
                    replacements[number] = { result }
                end
            else replacements[number] = { instruction } end
        end
    end
    O.rewrite(fn, replacements)
    return #records, records
end
local function expression_sources(graph, expression, candidate)
    local block_number = graph.block_of[candidate]
    local block = graph.blocks[block_number]
    for i = #block.instructions, 1, -1 do
        local number = block.instructions[i]
        if number < candidate and P.expression(graph.instructions[number]) == expression then return { [number] = true } end
    end
    local sources, examined, pending = {}, {}, {}
    append(pending, graph.reachable_predecessors[block_number])
    while #pending > 0 do
        local number = table.remove(pending)
        if not examined[number] then
            examined[number] = true
            local found, instructions = false, graph.blocks[number].instructions
            for i = #instructions, 1, -1 do
                local index = instructions[i]
                if P.expression(graph.instructions[index]) == expression then sources[index], found = true, true; break end
            end
            if not found then append(pending, graph.reachable_predecessors[number]) end
        end
    end
    return sources
end
local function common_subexpressions(fn, graph, flow)
    local groups, by_expression = {}, {}
    for number, instruction in ipairs(graph.instructions) do
        if graph.reachable[graph.block_of[number]] then
            local expression = P.expression(instruction)
            if expression and flow.expression_before[number][expression] then
                if not by_expression[expression] then by_expression[expression] = {}; groups[#groups + 1] = expression end
                local numbers = by_expression[expression]
                numbers[#numbers + 1] = number
            end
        end
    end
    local replacements, records, changes = {}, {}, 0
    for _, expression in ipairs(groups) do
        local numbers, sources = by_expression[expression], {}
        for _, number in ipairs(numbers) do C.union(sources, expression_sources(graph, expression, number)) end
        for _, number in ipairs(numbers) do sources[number] = nil end
        local temporary, edits = O.cse(fn, graph, sources, numbers)
        for number, edit in pairs(edits) do replacements[number] = edit end
        records[#records + 1] = expression .. ": " .. temporary .. " sources=" .. list(C.keys(sources), "#") .. " replaced=" .. list(numbers, "#")
        changes = changes + #numbers
    end
    O.rewrite(fn, replacements)
    return changes, records
end
local function dead_code(fn, graph, flow)
    local replacements, records = {}, {}
    for _, block_number in ipairs(C.keys(graph.reachable)) do
        local state, block = C.copy(flow.live_out[block_number]), graph.blocks[block_number]
        for i = #block.instructions, 1, -1 do
            local number = block.instructions[i]
            local instruction = graph.instructions[number]
            local destination = instruction.destination
            if instruction.kind == "copy" and destination == instruction.a
                or (instruction.kind == "copy" or instruction.kind == "bin" or instruction.kind == "load") and not state[destination] then
                replacements[number], records[number] = {}, "#" .. number .. ": delete " .. P.string(instruction)
            else
                if instruction.kind == "call" and destination and not state[destination] then
                    records[number] = "#" .. number .. ": unused result " .. P.string(instruction)
                    instruction = P.copy(instruction)
                    instruction.destination, replacements[number] = nil, { instruction }
                end
                state = D.live_transfer(instruction, state)
            end
        end
    end
    O.rewrite(fn, replacements)
    local ordered = {}
    for _, number in ipairs(C.keys(records)) do ordered[#ordered + 1] = records[number] end
    return #ordered, ordered
end
local function invariant_moves(graph, flow, loop)
    local numbers, stores, calls, definitions = {}, {}, false, {}
    for block in pairs(loop.blocks) do append(numbers, graph.blocks[block].instructions) end
    table.sort(numbers)
    for _, number in ipairs(numbers) do
        local instruction = graph.instructions[number]
        if instruction.kind == "store" then stores[instruction.name] = true elseif instruction.kind == "call" then calls = true end
        if instruction.destination then definitions[instruction.destination] = (definitions[instruction.destination] or 0) + 1 end
    end
    local marked, order, changed = {}, {}, true
    while changed do
        changed = false
        for _, number in ipairs(numbers) do
            local instruction = graph.instructions[number]
            if not marked[number] and (instruction.kind == "copy" or instruction.kind == "bin" or instruction.kind == "load")
                and not (instruction.kind == "load" and (calls or stores[instruction.name])) then
                local valid = true
                for _, variable in ipairs(P.used(instruction)) do
                    local reaching = reaching_numbers(flow, number, variable)
                    local inside = inside_definitions(graph, loop, reaching)
                    if next(inside) and not (C.count(reaching) == 1 and marked[next(inside)]) then valid = false; break end
                end
                if valid then marked[number], changed = true, true; order[#order + 1] = number end
            end
        end
    end
    local moved, moves = {}, {}
    for _, number in ipairs(order) do
        local instruction = graph.instructions[number]
        local destination, block = instruction.destination, graph.block_of[number]
        local valid = definitions[destination] == 1 and not flow.live_in[loop.header][destination]
        local dominates, dead_outside = true, true
        for exit in pairs(loop.exits) do if not graph.dominators[exit][block] then dominates = false end end
        for outside in pairs(loop.outside) do if flow.live_in[outside][destination] then dead_outside = false end end
        local dangerous = instruction.kind == "load" or instruction.kind == "bin" and (instruction.operation == "/" or instruction.operation == "%")
            and (type(instruction.b) == "string" or instruction.b == 0)
        if not dominates and (dangerous or not dead_outside) then valid = false end
        if valid then
            for _, variable in ipairs(P.used(instruction)) do
                for definition in pairs(inside_definitions(graph, loop, reaching_numbers(flow, number, variable))) do if not moved[definition] then valid = false end end
            end
        end
        if valid then moved[number] = true; moves[#moves + 1] = number end
    end
    return moves
end
local function loop_motion(fn, graph, flow)
    local loops = {}
    append(loops, graph.loops)
    table.sort(loops, function(a, b)
        local ac, bc = C.count(a.blocks), C.count(b.blocks)
        return ac < bc or ac == bc and a.header < b.header
    end)
    for _, loop in ipairs(loops) do
        local moves = invariant_moves(graph, flow, loop)
        if #moves > 0 then
            local destination = O.hoist(fn, graph, loop, moves)
            return #moves, { "B" .. loop.header .. ": hoist " .. list(moves, "#") .. " to " .. destination }
        end
    end
    return 0, {}
end
local function unreachable(fn, graph)
    local blocks, jumps, labels = O.unreachable(fn, graph)
    local records = {}
    for _, number in ipairs(blocks) do records[#records + 1] = "remove block B" .. number end
    for _, number in ipairs(jumps) do records[#records + 1] = "remove jump #" .. number end
    for _, label in ipairs(labels) do records[#records + 1] = "remove label " .. label end
    return #records, records
end
local passes = {
    constprop = function(fn, graph, flow) return propagation(fn, graph, flow, true) end,
    copyprop = function(fn, graph, flow) return propagation(fn, graph, flow, false) end,
    cse = common_subexpressions, dce = dead_code, licm = loop_motion, unreachable = unreachable
}
local function instruction_count(fn)
    local result = 0
    for _, line in ipairs(fn.code) do if type(line) ~= "string" then result = result + 1 end end
    return result
end
local function optimize(fn, enabled, maximum_rounds, totals)
    local before, lines, rounds = instruction_count(fn), { "== " .. fn.name .. " ==" }, 0
    for round = 1, maximum_rounds do
        local counts, records, changed = {}, {}, false
        rounds = round
        for _, name in ipairs(enabled) do
            local graph = C.new(fn)
            local count, entries = passes[name](fn, graph, D.new(graph))
            totals[name] = (totals[name] or 0) + count
            counts[#counts + 1] = name .. "=" .. count
            if count > 0 then changed = true end
            for _, entry in ipairs(entries) do records[#records + 1] = "  " .. name .. " " .. entry end
        end
        lines[#lines + 1] = "round " .. round .. ": " .. table.concat(counts, " ")
        append(lines, records)
        if not changed then break end
    end
    lines[#lines + 1] = string.format("result: rounds=%d instructions=%d->%d", rounds, before, instruction_count(fn))
    return lines
end
local function call_graph(program, heading)
    local callees = {}
    for _, fn in ipairs(program.functions) do
        local called = {}
        for _, line in ipairs(fn.code) do if type(line) ~= "string" and line.kind == "call" then called[line.name] = true end end
        local values = {}
        for _, target in ipairs(program.functions) do if called[target.name] then values[#values + 1] = target.name end end
        callees[fn.name] = values
    end
    local function reachable(starts)
        local reached, pending = {}, {}
        append(pending, starts)
        while #pending > 0 do
            local name = table.remove(pending)
            if not reached[name] then reached[name] = true; append(pending, callees[name]) end
        end
        return reached
    end
    local reached, lines, missing = reachable({ "main" }), { "== call graph (" .. heading .. ") ==" }, {}
    for _, fn in ipairs(program.functions) do
        lines[#lines + 1] = fn.name .. " -> " .. list(callees[fn.name]) .. (reachable(callees[fn.name])[fn.name] and " (recursive)" or "")
        if not reached[fn.name] then missing[#missing + 1] = fn.name end
    end
    lines[#lines + 1] = "unreachable functions: " .. list(missing)
    return lines, reached
end
local function definition_list(values)
    local definitions = {}
    for key in pairs(values) do
        local variable, number = key:match("^([^:]+):(%d+)$")
        definitions[#definitions + 1] = { variable, tonumber(number) }
    end
    table.sort(definitions, function(a, b) return a[2] < b[2] or a[2] == b[2] and a[1] < b[1] end)
    local result = {}
    for _, definition in ipairs(definitions) do result[#result + 1] = definition[1] .. ":" .. definition[2] end
    return list(result)
end
local function function_analysis(fn, heading)
    local graph = C.new(fn)
    local flow, number = D.new(graph), 0
    local lines = { "== " .. fn.name .. " (" .. heading .. ") ==", "code:" }
    for _, line in ipairs(fn.code) do
        if type(line) == "string" then lines[#lines + 1] = line .. ":"
        else
            number = number + 1
            local text = "  #" .. number .. " " .. P.string(line)
            if graph.reachable[graph.block_of[number]] then
                local seen, chains = {}, {}
                for _, variable in ipairs(P.used(line)) do
                    if not seen[variable] then
                        seen[variable] = true
                        chains[#chains + 1] = variable .. ":" .. list(C.keys(reaching_numbers(flow, number, variable)))
                    end
                end
                if #chains > 0 then text = text .. " | " .. table.concat(chains, " ") end
            end
            lines[#lines + 1] = text
        end
    end
    lines[#lines + 1] = "blocks: " .. #graph.blocks
    local missing = {}
    for index, block in ipairs(graph.blocks) do
        lines[#lines + 1] = string.format("B%d %d-%d labels=%s preds=%s succs=%s", index, block.instructions[1], block.instructions[#block.instructions],
            list(block.labels), list(block.predecessors, "B"), list(block.successors, "B"))
        if not graph.reachable[index] then missing[#missing + 1] = index end
    end
    lines[#lines + 1] = "unreachable: " .. list(missing, "B")
    lines[#lines + 1] = "order: " .. list(graph.reverse_postorder, "B")
    lines[#lines + 1] = "dominators:"
    for _, index in ipairs(C.keys(graph.reachable)) do
        lines[#lines + 1] = "B" .. index .. " idom=" .. (graph.immediate[index] and "B" .. graph.immediate[index] or "-") .. " dom=" .. list(C.keys(graph.dominators[index]), "B")
    end
    lines[#lines + 1] = "dominator tree:"
    local stack = { { 1, 0 } }
    while #stack > 0 do
        local item = table.remove(stack)
        lines[#lines + 1] = string.rep("  ", item[2]) .. "B" .. item[1]
        for index = #graph.blocks, 2, -1 do if graph.immediate[index] == item[1] then stack[#stack + 1] = { index, item[2] + 1 } end end
    end
    lines[#lines + 1] = "loops: " .. #graph.loops
    for _, loop in ipairs(graph.loops) do
        lines[#lines + 1] = string.format("header=B%d latches=%s depth=%d blocks=%s exits=%s", loop.header, list(loop.latches, "B"), loop.depth,
            list(C.keys(loop.blocks), "B"), list(C.keys(loop.exits), "B"))
    end
    local analyses = {
        { "reaching definitions", "reaching", flow.reaching_in, flow.reaching_out, definition_list },
        { "liveness", "liveness", flow.live_in, flow.live_out, function(values) return list(C.keys(values)) end },
        { "available expressions", "expressions", flow.expression_in, flow.expression_out, function(values) return list(C.keys(values)) end }
    }
    for _, analysis in ipairs(analyses) do
        lines[#lines + 1] = analysis[1] .. ": iterations=" .. flow.iterations[analysis[2]]
        for _, index in ipairs(C.keys(graph.reachable)) do lines[#lines + 1] = "B" .. index .. " in=" .. analysis[5](analysis[3][index]) .. " out=" .. analysis[5](analysis[4][index]) end
    end
    return lines
end
local function allocation_report(fn, registers)
    local graph = C.new(fn)
    local flow = D.new(graph)
    local allocation = R.allocate(fn, graph, flow, registers)
    local allocated = { name = fn.name, parameters = {}, code = {} }
    local function renamed(variable)
        local color = allocation.colors[variable]
        return color ~= nil and "R" .. color or variable
    end
    for i, parameter in ipairs(fn.parameters) do allocated.parameters[i] = renamed(parameter) end
    local moves, spill_uses, spill_defs, pressure, edges, used = 0, 0, 0, 0, 0, {}
    for _, line in ipairs(fn.code) do
        if type(line) == "string" then allocated.code[#allocated.code + 1] = line
        else
            local instruction = P.copy(line)
            if instruction.destination then
                if allocation.spills[instruction.destination] then spill_defs = spill_defs + 1 end
                instruction.destination = renamed(instruction.destination)
            end
            for _, field in ipairs(P.fields(line)) do
                local value = line[field]
                if type(value) == "string" then
                    if allocation.spills[value] then spill_uses = spill_uses + 1 end
                    instruction[field] = renamed(value)
                end
            end
            if instruction.kind == "copy" and instruction.destination == instruction.a then moves = moves + 1
            else allocated.code[#allocated.code + 1] = instruction end
        end
    end
    for _, parameter in ipairs(fn.parameters) do if allocation.spills[parameter] then spill_defs = spill_defs + 1 end end
    for _, states in ipairs({ flow.live_before, flow.live_after }) do for _, state in pairs(states) do pressure = math.max(pressure, C.count(state)) end end
    for _, node in ipairs(allocation.nodes) do
        edges = edges + C.count(allocation.neighbors[node])
        local color = allocation.colors[node]
        if color ~= nil then used[color] = true end
    end
    local lines = { "== " .. fn.name .. " ==", string.format("nodes=%d edges=%d registers=%d", #allocation.nodes, edges // 2, registers) }
    for _, node in ipairs(allocation.nodes) do
        lines[#lines + 1] = string.format("%s degree=%d cost=%s neighbors=%s", node, C.count(allocation.neighbors[node]), R.cost_string(allocation.costs[node]), list(C.keys(allocation.neighbors[node])))
    end
    lines[#lines + 1] = "simplify: " .. list(allocation.order)
    local potential = {}
    for _, item in ipairs(allocation.potential) do potential[#potential + 1] = item[1] .. "(" .. R.cost_string(allocation.costs[item[1]]) .. "/" .. item[2] .. ")" end
    lines[#lines + 1] = "potential spills: " .. list(potential)
    for _, node in ipairs(allocation.nodes) do lines[#lines + 1] = node .. " -> " .. (allocation.spills[node] and "spill" or renamed(node)) end
    lines[#lines + 1] = string.format("summary: pressure=%d used=%d spilled=%d moves=%d spill_uses=%d spill_defs=%d", pressure, C.count(used), C.count(allocation.spills), moves, spill_uses, spill_defs)
    append(lines, P.function_lines(allocated))
    return allocated, lines
end
local function increment(values, key, amount) values[key] = (values[key] or 0) + (amount or 1) end
local function sum(values) local result = 0; for _, value in pairs(values) do result = result + value end; return result end
local function interpret(program, inputs)
    local functions, arrays, input_position = {}, {}, 1
    for _, fn in ipairs(program.functions) do
        local instructions, labels = {}, {}
        for _, line in ipairs(fn.code) do
            if type(line) == "string" then labels[line] = #instructions + 1 else instructions[#instructions + 1] = line end
        end
        functions[fn.name] = { parameters = fn.parameters, instructions = instructions, labels = labels }
    end
    for _, array in ipairs(program.arrays) do
        local values = {}
        for i = 0, array[2] - 1 do values[i] = 0 end
        arrays[array[1]] = values
    end
    local result = { output = {}, steps = {}, calls = {}, kinds = {} }
    local function value(operand, variables) if type(operand) == "string" then return variables[operand] end; return operand end
    local call
    call = function(name, arguments)
        local fn, variables, pushed, position = functions[name], {}, {}, 1
        for i, parameter in ipairs(fn.parameters) do variables[parameter] = arguments[i] end
        increment(result.calls, name)
        while true do
            local instruction = fn.instructions[position]
            position = position + 1
            local kind = instruction.kind
            increment(result.steps, name); increment(result.kinds, kind)
            if kind == "copy" then variables[instruction.destination] = value(instruction.a, variables)
            elseif kind == "bin" then variables[instruction.destination] = P.calculate(instruction.operation, value(instruction.a, variables), value(instruction.b, variables))
            elseif kind == "load" then variables[instruction.destination] = arrays[instruction.name][value(instruction.a, variables)]
            elseif kind == "store" then arrays[instruction.name][value(instruction.a, variables)] = value(instruction.b, variables)
            elseif kind == "goto" then position = fn.labels[instruction.name]
            elseif kind == "if" then
                if P.calculate(instruction.operation, value(instruction.a, variables), value(instruction.b, variables)) ~= 0 then position = fn.labels[instruction.name] end
            elseif kind == "param" then pushed[#pushed + 1] = value(instruction.a, variables)
            elseif kind == "call" then
                local values, start = {}, #pushed - instruction.count + 1
                for i = start, #pushed do values[#values + 1] = pushed[i] end
                for i = #pushed, start, -1 do pushed[i] = nil end
                local returned = call(instruction.name, values)
                if instruction.destination then variables[instruction.destination] = returned end
            elseif kind == "return" then return value(instruction.a, variables)
            elseif kind == "read" then variables[instruction.destination], input_position = inputs[input_position], input_position + 1
            elseif kind == "print" then result.output[#result.output + 1] = value(instruction.a, variables) end
        end
    end
    call("main", {})
    return result
end
local function static_kinds(program)
    local result = {}
    for _, fn in ipairs(program.functions) do for _, line in ipairs(fn.code) do if type(line) ~= "string" then increment(result, line.kind) end end end
    return result
end
local function comparison_report(original, optimized, allocated, runs)
    local programs, profiles, dynamic, total_steps = { original, optimized, allocated }, {}, {}, {}
    for i = 1, 3 do profiles[i], dynamic[i], total_steps[i] = {}, {}, 0 end
    local original_calls, lines, same = {}, {}, 0
    for run_number, inputs in ipairs(runs) do
        lines[#lines + 1] = "run " .. run_number .. ": inputs=" .. #inputs
        local outputs = {}
        for index, version in ipairs(versions) do
            local result = interpret(programs[index], inputs)
            local steps, calls = sum(result.steps), sum(result.calls)
            outputs[index] = list(result.output)
            lines[#lines + 1] = string.format("  %s: steps=%d calls=%d output=%s", version, steps, calls, outputs[index])
            for name, count in pairs(result.steps) do increment(profiles[index], name, count) end
            for kind, count in pairs(result.kinds) do increment(dynamic[index], kind, count) end
            total_steps[index] = total_steps[index] + steps
            if index == 1 then for name, count in pairs(result.calls) do increment(original_calls, name, count) end end
        end
        local equal = outputs[1] == outputs[2] and outputs[2] == outputs[3]
        if equal then same = same + 1 end
        lines[#lines + 1] = "  result: " .. (equal and "same" or "different")
    end
    lines[#lines + 1] = "== profile =="
    for _, fn in ipairs(original.functions) do
        local name = fn.name
        lines[#lines + 1] = string.format("%s: calls=%d original=%d optimized=%d allocated=%d", name, original_calls[name] or 0, profiles[1][name] or 0, profiles[2][name] or 0, profiles[3][name] or 0)
    end
    local original_kinds, optimized_kinds = static_kinds(original), static_kinds(optimized)
    lines[#lines + 1] = "== summary =="
    lines[#lines + 1] = string.format("runs=%d same=%d different=%d", #runs, same, #runs - same)
    lines[#lines + 1] = string.format("instructions: original=%d optimized=%d", sum(original_kinds), sum(optimized_kinds))
    local kinds = {}
    for _, kind in ipairs(P.kinds) do kinds[#kinds + 1] = kind .. "=" .. (original_kinds[kind] or 0) .. "->" .. (optimized_kinds[kind] or 0) end
    lines[#lines + 1] = "kinds: " .. table.concat(kinds, " ")
    lines[#lines + 1] = string.format("steps: original=%d optimized=%d allocated=%d", total_steps[1], total_steps[2], total_steps[3])
    for index, version in ipairs(versions) do
        local counts = {}
        for _, kind in ipairs(P.kinds) do counts[#counts + 1] = kind .. "=" .. (dynamic[index][kind] or 0) end
        lines[#lines + 1] = "dynamic " .. version .. ": " .. table.concat(counts, " ")
    end
    return lines
end
local settings = assert(io.open("input/params.txt", "r"))
local registers = tonumber(settings:read("*l"):match(" (%d+)$"))
local selected, enabled = {}, {}
for word in settings:read("*l"):gmatch("%S+") do selected[word] = true end
local maximum_rounds = tonumber(settings:read("*l"):match(" (%d+)$"))
settings:close()
for _, name in ipairs(pass_order) do if selected[name] then enabled[#enabled + 1] = name end end
local input, runs = assert(io.open("input/input.txt", "r")), {}
local number_of_runs = tonumber(input:read("*l"))
for _ = 1, number_of_runs do
    local values = {}
    for word in input:read("*l"):gmatch("%S+") do values[#values + 1] = tonumber(word) end
    local run = {}
    for i = 1, values[1] do run[i] = values[i + 1] end
    runs[#runs + 1] = run
end
input:close()
local original = P.read("input/program.tac")
local analysis = call_graph(original, "original")
for _, fn in ipairs(original.functions) do append(analysis, function_analysis(fn, "original")) end
local working = { arrays = original.arrays, functions = {} }
for _, fn in ipairs(original.functions) do working.functions[#working.functions + 1] = P.function_copy(fn) end
local pass_lines, totals = {}, {}
for _, fn in ipairs(working.functions) do append(pass_lines, optimize(fn, enabled, maximum_rounds, totals)) end
local graph_lines, reachable = call_graph(working, "optimized")
append(analysis, graph_lines)
local removed, optimized = {}, { arrays = working.arrays, functions = {} }
for _, fn in ipairs(working.functions) do
    if selected.unreachable and not reachable[fn.name] then removed[#removed + 1] = fn.name else optimized.functions[#optimized.functions + 1] = fn end
end
append(pass_lines, { "== program ==", "removed functions: " .. list(removed), "== total ==" })
local total_counts = {}
for _, name in ipairs(enabled) do total_counts[#total_counts + 1] = name .. "=" .. (totals[name] or 0) end
pass_lines[#pass_lines + 1] = table.concat(total_counts, " ")
local allocated, allocation_lines = { arrays = optimized.arrays, functions = {} }, {}
for _, fn in ipairs(optimized.functions) do
    append(analysis, function_analysis(fn, "optimized"))
    local allocated_function, lines = allocation_report(fn, registers)
    allocated.functions[#allocated.functions + 1] = allocated_function
    append(allocation_lines, lines)
end
local reports = {
    ["optimized.tac"] = P.program_lines(optimized), ["analysis.txt"] = analysis, ["passes.txt"] = pass_lines,
    ["regalloc.txt"] = allocation_lines, ["comparison.txt"] = comparison_report(original, optimized, allocated, runs)
}
for filename, lines in pairs(reports) do
    local output = assert(io.open("output/" .. filename, "w"))
    output:write(table.concat(lines, "\n"), "\n")
    output:close()
end
