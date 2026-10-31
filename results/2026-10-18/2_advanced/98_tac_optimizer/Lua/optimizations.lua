local P = require("tac_parser")
local O = {}
function O.rewrite(fn, replacements, insertions)
    local result, number = {}, 0
    insertions = insertions or {}
    local function append(values) for _, value in ipairs(values) do result[#result + 1] = value end end
    for position, line in ipairs(fn.code) do
        append(insertions[position] or {})
        if type(line) == "string" then result[#result + 1] = line
        else number = number + 1; append(replacements[number] or { line }) end
    end
    append(insertions[#fn.code + 1] or {})
    fn.code = result
end
function O.fold(instruction)
    if instruction.kind ~= "bin" and instruction.kind ~= "if" then return instruction end
    local a, b = instruction.a, instruction.b
    local ac, bc = type(a) == "number", type(b) == "number"
    local operator = instruction.operation
    if ac and bc then
        if (operator == "/" or operator == "%") and b == 0 then return instruction end
        local value = P.calculate(operator, a, b)
        if instruction.kind == "if" then return value ~= 0 and { kind = "goto", name = instruction.name } or nil end
        if value >= -2147483648 and value <= 2147483647 then return { kind = "copy", destination = instruction.destination, a = value } end
    elseif instruction.kind == "bin" and ac ~= bc then
        local value
        if operator == "+" and (a == 0 or b == 0) then value = ac and b or a
        elseif operator == "-" and b == 0 then value = a
        elseif operator == "*" and (a == 1 or b == 1) then value = ac and b or a
        elseif operator == "/" and b == 1 then value = a
        elseif operator == "*" and (a == 0 or b == 0) then value = 0 end
        if value ~= nil then return { kind = "copy", destination = instruction.destination, a = value } end
    end
    return instruction
end
function O.cse(fn, graph, sources, candidates)
    fn.temporary_serial = fn.temporary_serial + 1
    local temporary, replacements = "_t" .. fn.temporary_serial, {}
    for number in pairs(sources) do
        local instruction = P.copy(graph.instructions[number])
        local destination = instruction.destination
        instruction.destination = temporary
        replacements[number] = { instruction, { kind = "copy", destination = destination, a = temporary } }
    end
    for _, number in ipairs(candidates) do replacements[number] = { { kind = "copy", destination = graph.instructions[number].destination, a = temporary } } end
    return temporary, replacements
end
function O.hoist(fn, graph, loop, moves)
    local header, outside, replacements, instructions = graph.blocks[loop.header], {}, {}, {}
    for _, number in ipairs(header.predecessors) do if not loop.blocks[number] then outside[#outside + 1] = number end end
    for _, number in ipairs(moves) do replacements[number] = {}; instructions[#instructions + 1] = graph.instructions[number] end
    local position, insertion, destination
    local preheader = #outside == 1 and graph.blocks[outside[1]] or nil
    if loop.header ~= 1 and preheader and #preheader.successors == 1 and preheader.successors[1] == loop.header then
        local last = preheader.instructions[#preheader.instructions]
        position = graph.positions[last]
        if graph.instructions[last].kind ~= "goto" and graph.instructions[last].kind ~= "if" then position = position + 1 end
        insertion, destination = instructions, "B" .. preheader.number
    else
        fn.preheader_serial = fn.preheader_serial + 1
        local label = "_p" .. fn.preheader_serial
        position, insertion, destination = header.start, { label }, "new " .. label
        for _, instruction in ipairs(instructions) do insertion[#insertion + 1] = instruction end
        local labels = {}
        for _, value in ipairs(header.labels) do labels[value] = true end
        for _, number in ipairs(outside) do
            local last = graph.blocks[number].instructions[#graph.blocks[number].instructions]
            local instruction = graph.instructions[last]
            if (instruction.kind == "goto" or instruction.kind == "if") and labels[instruction.name] then
                local replacement = P.copy(instruction)
                replacement.name, replacements[last] = label, { replacement }
            end
        end
    end
    O.rewrite(fn, replacements, { [position] = insertion })
    return destination
end
function O.unreachable(fn, graph)
    local blocks, jumps, labels, deleted, positions, remaining = {}, {}, {}, {}, {}, {}
    for number, block in ipairs(graph.blocks) do
        if not graph.reachable[number] then
            blocks[#blocks + 1] = number
            for position = block.start, block.finish do deleted[position] = true end
        end
    end
    for number, position in ipairs(graph.positions) do positions[position] = number end
    for position, line in ipairs(fn.code) do if not deleted[position] then remaining[#remaining + 1] = { line = line, number = positions[position] } end end
    local removed = {}
    for index, entry in ipairs(remaining) do
        local line = entry.line
        if type(line) ~= "string" and (line.kind == "goto" or line.kind == "if") then
            local following = index + 1
            while following <= #remaining and type(remaining[following].line) == "string" do
                if remaining[following].line == line.name then jumps[#jumps + 1], removed[entry.number] = entry.number, true; break end
                following = following + 1
            end
        end
    end
    local targets, kept = {}, {}
    for _, entry in ipairs(remaining) do
        if not removed[entry.number] then
            kept[#kept + 1] = entry
            local line = entry.line
            if type(line) ~= "string" and (line.kind == "goto" or line.kind == "if") then targets[line.name] = true end
        end
    end
    fn.code = {}
    for _, entry in ipairs(kept) do
        local line = entry.line
        if type(line) == "string" and not targets[line] then labels[#labels + 1] = line
        else fn.code[#fn.code + 1] = line end
    end
    return blocks, jumps, labels
end
return O
