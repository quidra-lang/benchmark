local lexer = require("lexer")
local Parser = require("parser")
local Analyzer = require("semantic")
local G = require("codegen")
local VM = require("vm")
local rules = { "const-jump", "not-compare", "not-jump", "invert-branch", "thread", "jump-next", "unreachable" }
local reports = { ["listing.txt"] = {}, ["output.txt"] = {}, ["diagnostics.txt"] = {}, ["stats.txt"] = {} }
local function append(target, source)
    for _, line in ipairs(source) do target[#target + 1] = line end
end
local function position_less(a, b) return a[1] < b[1] or (a[1] == b[1] and a[2] < b[2]) end
local function position_text(p) return p[1] .. ":" .. p[2] end
local function sum(values)
    local total = 0
    for _, value in ipairs(values) do total = total + value end
    return total
end
local function warnings(analysis)
    local result = {}
    for _, variable in ipairs(analysis.variables) do
        if variable.read_accesses == 0 then
            local role = variable.kind == "parameter" and "parameter" or "variable"
            result[#result + 1] = { variable.name_position, "unused " .. role .. " '" .. variable.name .. "'" }
        end
    end
    local function visit(node)
        if node.kind == "block" then
            for i = 1, #node.statements - 1 do
                if not Analyzer.can_complete(node.statements[i]) then
                    result[#result + 1] = { node.statements[i + 1].position, "unreachable statement" }
                    break
                end
            end
        end
        for _, child in ipairs(Parser.statement_children(node)) do visit(child) end
    end
    for _, fn in ipairs(analysis.functions) do visit(fn.body) end
    local reachable, pending = {}, { analysis.globals.main }
    while #pending > 0 do
        local fn = table.remove(pending)
        if not reachable[fn] then
            reachable[fn] = true
            for callee in pairs(fn.calls) do pending[#pending + 1] = callee end
        end
    end
    for _, fn in ipairs(analysis.functions) do
        if not reachable[fn] then result[#result + 1] = { fn.name_position, "function '" .. fn.name .. "' is never called" } end
    end
    table.sort(result, function(a, b) return position_less(a[1], b[1]) end)
    return result, reachable
end
local function is_recursive(fn)
    local pending, seen = {}, {}
    for callee in pairs(fn.calls) do pending[#pending + 1] = callee end
    while #pending > 0 do
        local current = table.remove(pending)
        if current == fn then return true end
        if not seen[current] then
            seen[current] = true
            for callee in pairs(current.calls) do pending[#pending + 1] = callee end
        end
    end
    return false
end
local F = {}
F.__index = F
local function literal(node) return node.kind == "integer" or node.kind == "boolean" end
local function literal_value(node, kind, value) return node.kind == kind and node.value == value end
local function as_integer(node)
    if node.kind == "boolean" then return node.value and 1 or 0 end
    return node.value
end
function F:new_literal(node, value)
    self.count = self.count + 1
    local kind = node.type == "bool" and "boolean" or "integer"
    if kind == "boolean" then value = value ~= 0 and value ~= false end
    return Parser.node(kind, node.position, { value = value, type = node.type })
end
function F:identity(expression) self.count = self.count + 1; return expression end
function F:expression(node)
    if node.kind == "unary" then
        node.operand = self:expression(node.operand)
        if literal(node.operand) then
            local value = VM.calculate(node.operator == "-" and "NEG" or "NOT", as_integer(node.operand))
            if value ~= nil then return self:new_literal(node, value) end
        end
    elseif node.kind == "binary" then
        node.left, node.right = self:expression(node.left), self:expression(node.right)
        local left, right, op = node.left, node.right, node.operator
        if literal(left) and literal(right) then
            local a, b, value = as_integer(left), as_integer(right)
            if op == "&&" then value = a ~= 0 and b ~= 0
            elseif op == "||" then value = a ~= 0 or b ~= 0
            else value = VM.calculate(G.binary[op], a, b) end
            if value ~= nil then return self:new_literal(node, value) end
        end
        if op == "&&" and literal_value(left, "boolean", false) then return self:new_literal(node, false) end
        if op == "||" and literal_value(left, "boolean", true) then return self:new_literal(node, true) end
        if (op == "&&" and literal_value(left, "boolean", true))
            or (op == "||" and literal_value(left, "boolean", false))
            or (op == "+" and literal_value(left, "integer", 0))
            or (op == "*" and literal_value(left, "integer", 1)) then return self:identity(right) end
        if ((op == "+" or op == "-") and literal_value(right, "integer", 0))
            or ((op == "*" or op == "/") and literal_value(right, "integer", 1))
            or (op == "&&" and literal_value(right, "boolean", true))
            or (op == "||" and literal_value(right, "boolean", false)) then return self:identity(left) end
    elseif node.kind == "array" then node.index = self:expression(node.index)
    elseif node.kind == "call" then
        for i, argument in ipairs(node.arguments) do node.arguments[i] = self:expression(argument) end
    end
    return node
end
function F:statement(node)
    local kind = node.kind
    if kind == "declaration" then
        if node.initializer then node.initializer = self:expression(node.initializer) end
    elseif kind == "assignment" then
        if node.index then node.index = self:expression(node.index) end
        node.value = self:expression(node.value)
    elseif kind == "call_statement" then node.expression = self:expression(node.expression)
    elseif kind == "print" then
        for i, argument in ipairs(node.arguments) do node.arguments[i] = self:expression(argument) end
    elseif kind == "return" then
        if node.value then node.value = self:expression(node.value) end
    elseif kind == "block" then
        for i, child in ipairs(node.statements) do node.statements[i] = self:statement(child) end
    elseif kind == "if" then
        node.condition = self:expression(node.condition)
        if node.condition.kind == "boolean" then
            local selected = node.condition.value and node.consequent or node.otherwise
            local replacement = selected and self:statement(selected) or Parser.node("empty", node.position)
            self.count = self.count + 1
            return replacement
        end
        node.consequent = self:statement(node.consequent)
        if node.otherwise then node.otherwise = self:statement(node.otherwise) end
    elseif kind == "while" then
        node.condition = self:expression(node.condition)
        if literal_value(node.condition, "boolean", false) then
            self.count = self.count + 1
            return Parser.node("empty", node.position)
        end
        node.body = self:statement(node.body)
    elseif kind == "for" then
        if node.initial then node.initial = self:statement(node.initial) end
        if node.condition then node.condition = self:expression(node.condition) end
        if node.update then node.update = self:statement(node.update) end
        node.body = self:statement(node.body)
    end
    return node
end
local function jumps_on(op, value) return (value == 0) == (op == "JUMPF") end
local function delete_instruction(code, p)
    table.remove(code, p)
    for _, instruction in ipairs(code) do
        if G.jumps[instruction.op] and instruction.args[1] > p then instruction.args[1] = instruction.args[1] - 1 end
    end
end
local function rewrite(code, i, targets)
    local first, second = code[i], code[i + 1]
    local free = second and not targets[i + 1]
    if free and first.op == "PUSH" and G.conditional[second.op] then
        if jumps_on(second.op, first.args[1]) then
            code[i] = G.instruction("JUMP", { second.args[1] }, second.position)
            delete_instruction(code, i + 1)
        else delete_instruction(code, i + 1); delete_instruction(code, i) end
        return 1
    elseif free and G.negated[first.op] and second.op == "NOT" then
        code[i] = G.instruction(G.negated[first.op], {}, first.position)
        delete_instruction(code, i + 1)
        return 2
    elseif free and first.op == "NOT" and G.conditional[second.op] then
        code[i] = G.instruction(G.inverse[second.op], { second.args[1] }, second.position)
        delete_instruction(code, i + 1)
        return 3
    elseif free and G.conditional[first.op] and first.args[1] == i + 2 and second.op == "JUMP" then
        code[i] = G.instruction(G.inverse[first.op], { second.args[1] }, first.position)
        delete_instruction(code, i + 1)
        return 4
    end
    if G.jumps[first.op] then
        local target, new_target = first.args[1], false
        if target <= #code then
            local destination, following = code[target], code[target + 1]
            if destination.op == "JUMP" then new_target = destination.args[1]
            elseif destination.op == "PUSH" and following and G.conditional[following.op] then
                new_target = jumps_on(following.op, destination.args[1]) and following.args[1] or target + 2
            end
            if new_target and new_target ~= target then first.args[1] = new_target; return 5 end
        end
        if target == i + 1 then
            if first.op == "JUMP" then delete_instruction(code, i) else code[i] = G.instruction("POP", {}, first.position) end
            return 6
        end
    end
    if free and G.transfers[first.op] then delete_instruction(code, i + 1); return 7 end
    return 0
end
local function optimize(original)
    local code, counts = {}, { 0, 0, 0, 0, 0, 0, 0 }
    for i, instruction in ipairs(original) do code[i] = G.instruction(instruction.op, { table.unpack(instruction.args) }, instruction.position) end
    while true do
        local targets, applied = {}, false
        for _, instruction in ipairs(code) do if G.jumps[instruction.op] then targets[instruction.args[1]] = true end end
        for i = 1, #code do
            local rule = rewrite(code, i, targets)
            if rule > 0 then counts[rule], applied = counts[rule] + 1, true; break end
        end
        if not applied then return code, counts end
    end
end
local function successors(code, i)
    local instruction, result = code[i], {}
    if not G.transfers[instruction.op] and i < #code then result[1] = i + 1 end
    if G.jumps[instruction.op] then
        local target = instruction.args[1]
        if target <= #code and result[1] ~= target then result[#result + 1] = target end
    end
    return result
end
local pushing = { PUSH = true, LOADG = true, LOADL = true, READ = true }
local popping = { POP = true, STOREG = true, STOREL = true, JUMPF = true, JUMPT = true, RETV = true,
    ADD = true, SUB = true, MUL = true, DIV = true, MOD = true, LT = true, LE = true, GT = true, GE = true, EQ = true, NE = true }
local function stack_effect(instruction, functions)
    local op, args = instruction.op, instruction.args
    if pushing[op] then return 1 elseif popping[op] then return -1 elseif op == "STOREA" then return -2
    elseif op == "CALL" then return -args[2] + (functions[args[1]].type ~= "void" and 1 or 0)
    elseif op == "PRINT" then return -args[1] end
    return 0
end
local function analyze_flow(unit, functions)
    local code, leaders = unit.after, { [1] = true }
    for i, instruction in ipairs(code) do
        if G.jumps[instruction.op] and instruction.args[1] <= #code then leaders[instruction.args[1]] = true end
        if (G.jumps[instruction.op] or G.transfers[instruction.op]) and i < #code then leaders[i + 1] = true end
    end
    local starts, block_numbers = {}, {}
    for leader in pairs(leaders) do starts[#starts + 1] = leader end
    table.sort(starts)
    for i, start in ipairs(starts) do block_numbers[start] = i - 1 end
    unit.blocks = {}
    for i, start in ipairs(starts) do
        local ending = starts[i + 1] and starts[i + 1] - 1 or #code
        local following = {}
        for _, target in ipairs(successors(code, ending)) do following[#following + 1] = block_numbers[target] end
        unit.blocks[i] = { start, ending, following }
    end
    local depths, pending, maximum = { [1] = 0 }, { 1 }, 0
    while #pending > 0 do
        local i = table.remove(pending)
        local after = depths[i] + stack_effect(code[i], functions)
        maximum = math.max(maximum, after)
        for _, target in ipairs(successors(code, i)) do
            if depths[target] == nil then depths[target], pending[#pending + 1] = after, target end
        end
    end
    unit.depth = maximum
end
local function link_units(units, version)
    local addresses, starts, offset = {}, {}, 0
    for _, unit in ipairs(units) do
        addresses[unit.name], starts[offset], unit[version .. "_start"] = offset, unit.name, offset
        offset = offset + #unit[version]
    end
    local code, owners = {}, {}
    for _, unit in ipairs(units) do
        local start = addresses[unit.name]
        for _, instruction in ipairs(unit[version]) do
            local args = { table.unpack(instruction.args) }
            if G.jumps[instruction.op] then args[1] = start + args[1] - 1
            elseif instruction.op == "CALL" then args[1] = addresses[args[1]] end
            code[#code + 1], owners[#owners + 1] = G.instruction(instruction.op, args, instruction.position), unit.name
        end
    end
    return code, owners, starts
end
local function compile(program)
    local tokens = lexer.tokenize(program.lines)
    local declarations = Parser.new(tokens):parse()
    local analysis = Analyzer.new(declarations, tokens[#tokens].position):analyze()
    program.analysis = analysis
    local reachable
    program.warnings, reachable = warnings(analysis)
    local globals, functions, function_table = {}, {}, {}
    for _, declaration in ipairs(declarations) do if declaration.kind == "global" then globals[#globals + 1] = declaration end end
    for _, fn in ipairs(analysis.functions) do
        if reachable[fn] then functions[#functions + 1], function_table[fn.name] = fn, fn end
    end
    local folder = setmetatable({ count = 0 }, F)
    for _, variable in ipairs(globals) do if variable.initializer then variable.initializer = folder:expression(variable.initializer) end end
    for _, fn in ipairs(functions) do fn.body = folder:statement(fn.body) end
    program.globals, program.folds = globals, folder.count
    program.units, program.global_size = G.generate(globals, functions, analysis.globals.main)
    program.peephole = { 0, 0, 0, 0, 0, 0, 0 }
    for _, unit in ipairs(program.units) do
        local counts
        unit.after, counts = optimize(unit.before)
        for i, count in ipairs(counts) do program.peephole[i] = program.peephole[i] + count end
        analyze_flow(unit, function_table)
        unit.recursive = unit.fn and is_recursive(unit.fn)
    end
    local before_owners, before_starts, after_starts
    program.before, before_owners, before_starts = link_units(program.units, "before")
    program.after, program.owners, after_starts = link_units(program.units, "after")
    program.execution = VM.new(program.after, program.owners, after_starts, program.global_size, program.inputs):run()
    program.comparison = VM.new(program.before, before_owners, before_starts, program.global_size, program.inputs):run()
end
local function spelling(instruction)
    local parts = { instruction.op }
    for _, argument in ipairs(instruction.args) do parts[#parts + 1] = tostring(argument) end
    return table.concat(parts, " ")
end
local function position_display(program, position)
    return { "  " .. program.source_text[position[1]], string.rep(" ", position[2] + 1) .. "^" }
end
local function sorted_keys(values)
    local keys = {}
    for key in pairs(values) do keys[#keys + 1] = key end
    table.sort(keys)
    return keys
end
local function listing(program)
    local lines = {}
    if #program.globals == 0 then lines[1] = "globals: none"
    else
        lines[1] = "globals:"
        for _, variable in ipairs(program.globals) do
            local typ = variable.size and "int[" .. variable.size .. "]" or variable.type
            lines[#lines + 1] = string.format("  %d %s %s", variable.address, variable.name, typ)
        end
    end
    lines[#lines + 1] = "functions:"
    for _, unit in ipairs(program.units) do
        local signature, callees = "", "main"
        if unit.fn then
            local parameter_types, called = {}, {}
            for _, parameter in ipairs(unit.fn.parameters) do parameter_types[#parameter_types + 1] = parameter.type end
            signature = " " .. unit.fn.type .. "(" .. table.concat(parameter_types, ",") .. ")"
            for fn in pairs(unit.fn.calls) do called[#called + 1] = fn.name end
            table.sort(called)
            callees = #called > 0 and table.concat(called, ",") or "-"
        end
        lines[#lines + 1] = string.format("  %s%s address=%d->%d size=%d->%d slots=%d stack=%d blocks=%d calls=%s%s",
            unit.name, signature, unit.before_start, unit.after_start, #unit.before, #unit.after, #unit.slots,
            unit.depth, #unit.blocks, callees, unit.recursive and " recursive" or "")
        for i, slot in ipairs(unit.slots) do lines[#lines + 1] = string.format("    slot %d %s %s", i - 1, slot.name, slot.type) end
    end
    lines[#lines + 1] = "references:"
    local declarations = { table.unpack(program.globals) }
    append(declarations, program.analysis.functions)
    for _, declaration in ipairs(declarations) do
        local used = {}
        for _, position in ipairs(declaration.references) do used[position[1]] = true end
        local parts = {}
        for _, line in ipairs(sorted_keys(used)) do parts[#parts + 1] = tostring(line) end
        lines[#lines + 1] = string.format("  %s defined %d used %s", declaration.name, declaration.name_position[1],
            #parts > 0 and table.concat(parts, " ") or "-")
    end
    for _, version in ipairs({ "before", "after" }) do
        local code = program[version]
        lines[#lines + 1] = version .. " peephole: " .. #code .. " instructions"
        for _, unit in ipairs(program.units) do
            lines[#lines + 1] = unit.name .. ":"
            local start = unit[version .. "_start"]
            for address = start, start + #unit[version] - 1 do
                lines[#lines + 1] = string.format("%5d  %s", address, spelling(code[address + 1]))
            end
        end
    end
    lines[#lines + 1] = "control flow:"
    for _, unit in ipairs(program.units) do
        lines[#lines + 1] = "  " .. unit.name
        for i, block in ipairs(unit.blocks) do
            local line = string.format("    B%d %d-%d", i - 1, unit.after_start + block[1] - 1, unit.after_start + block[2] - 1)
            if #block[3] > 0 then
                local following = {}
                for _, number in ipairs(block[3]) do following[#following + 1] = "B" .. number end
                line = line .. " -> " .. table.concat(following, " ")
            end
            lines[#lines + 1] = line
        end
    end
    return lines
end
local function diagnostics(program)
    local lines = {}
    if program.error then
        local err = program.error
        lines[1] = err.kind .. " error " .. position_text(err.position) .. ": " .. err.message
        append(lines, position_display(program, err.position))
        lines[#lines + 1] = "status: compile error"
        return lines
    end
    for _, warning in ipairs(program.warnings) do lines[#lines + 1] = "warning " .. position_text(warning[1]) .. ": " .. warning[2] end
    local execution = program.execution
    if not execution.error then lines[#lines + 1] = "status: ok"; return lines end
    local instruction = program.after[execution.error_pc + 1]
    lines[#lines + 1] = "runtime error " .. position_text(instruction.position) .. ": " .. execution.error .. " in " .. program.owners[execution.error_pc + 1]
    append(lines, position_display(program, instruction.position))
    local callers = #execution.frames - 1
    for i = #execution.frames, math.max(2, #execution.frames - 4), -1 do
        local address = execution.frames[i].return_address - 1
        lines[#lines + 1] = "  called from " .. program.owners[address + 1] .. " at " .. position_text(program.after[address + 1].position)
    end
    if callers > 5 then lines[#lines + 1] = "  ... " .. (callers - 5) .. " more" end
    lines[#lines + 1] = "status: runtime error"
    return lines
end
local function ordered_counts(values)
    local entries = {}
    for key, count in pairs(values) do entries[#entries + 1] = { key, count } end
    table.sort(entries, function(a, b) return a[2] > b[2] or (a[2] == b[2] and a[1] < b[1]) end)
    return entries
end
local function statistics(program)
    local execution, comparison = program.execution, program.comparison
    local same = #execution.output == #comparison.output and execution.error == comparison.error
    if same then for i, line in ipairs(execution.output) do if line ~= comparison.output[i] then same = false; break end end end
    local lines = { "code: " .. #program.before .. " -> " .. #program.after, "folds: " .. program.folds,
        "peephole: " .. sum(program.peephole) }
    for i, rule in ipairs(rules) do lines[#lines + 1] = "  " .. rule .. " " .. program.peephole[i] end
    append(lines, { "executed: " .. execution.executed, "executed before peephole: " .. comparison.executed,
        "behaviour: " .. (same and "same" or "different"), "max call depth: " .. execution.max_depth,
        "max stack: " .. execution.max_stack })
    local opcodes, functions, source_lines = {}, {}, {}
    for i, instruction in ipairs(program.after) do
        local count, owner, line = execution.counts[i], program.owners[i], instruction.position[1]
        opcodes[instruction.op] = (opcodes[instruction.op] or 0) + count
        functions[owner] = (functions[owner] or 0) + count
        source_lines[line] = (source_lines[line] or 0) + count
    end
    lines[#lines + 1] = "opcodes:"
    for _, entry in ipairs(ordered_counts(opcodes)) do if entry[2] > 0 then lines[#lines + 1] = "  " .. entry[1] .. " " .. entry[2] end end
    lines[#lines + 1] = "functions:"
    local names = {}
    for _, unit in ipairs(program.units) do if unit.fn then names[#names + 1] = unit.name end end
    table.sort(names, function(a, b) return functions[a] > functions[b] or (functions[a] == functions[b] and a < b) end)
    for _, name in ipairs(names) do
        lines[#lines + 1] = string.format("  %s calls=%d executed=%d", name, execution.calls[name] or 0, functions[name])
    end
    lines[#lines + 1] = "calls:"
    local pairs_list = {}
    for caller, callees in pairs(execution.pairs) do
        for callee, count in pairs(callees) do pairs_list[#pairs_list + 1] = { caller, callee, count } end
    end
    table.sort(pairs_list, function(a, b)
        if a[3] ~= b[3] then return a[3] > b[3] end
        if a[1] ~= b[1] then return a[1] < b[1] end
        return a[2] < b[2]
    end)
    for _, entry in ipairs(pairs_list) do lines[#lines + 1] = "  " .. entry[1] .. " -> " .. entry[2] .. " " .. entry[3] end
    lines[#lines + 1] = "hot lines:"
    local executed_lines, unexecuted, line_count = 0, {}, 0
    for _, entry in ipairs(ordered_counts(source_lines)) do
        line_count = line_count + 1
        if entry[2] > 0 then
            executed_lines = executed_lines + 1
            if executed_lines <= 5 then lines[#lines + 1] = string.format("  line %d: %d", entry[1], entry[2]) end
        else unexecuted[#unexecuted + 1] = entry[1] end
    end
    lines[#lines + 1] = "coverage: " .. executed_lines .. " of " .. line_count .. " lines"
    table.sort(unexecuted)
    local not_executed = {}
    for _, line in ipairs(unexecuted) do not_executed[#not_executed + 1] = tostring(line) end
    lines[#lines + 1] = "not executed: " .. (#not_executed > 0 and table.concat(not_executed, " ") or "none")
    lines[#lines + 1] = "hot spots:"
    local hotspots = {}
    for i, count in ipairs(execution.counts) do if count > 0 then hotspots[i - 1] = count end end
    local entries = ordered_counts(hotspots)
    for i = 1, math.min(5, #entries) do
        local entry = entries[i]
        lines[#lines + 1] = string.format("  pc=%d count=%d %s", entry[1], entry[2], spelling(program.after[entry[1] + 1]))
    end
    return lines
end
local function summary(programs)
    local compiled, runtime_errors, folds, executed = 0, 0, 0, 0
    local errors, peephole = { lexical = 0, syntax = 0, semantic = 0 }, { 0, 0, 0, 0, 0, 0, 0 }
    local rows = { { "program", "status", "code", "executed", "output" } }
    for _, program in ipairs(programs) do
        if program.error then
            errors[program.error.kind] = errors[program.error.kind] + 1
            rows[#rows + 1] = { program.name, program.error.kind .. " error", "-", "-", "-" }
        else
            compiled, folds, executed = compiled + 1, folds + program.folds, executed + program.execution.executed
            if program.execution.error then runtime_errors = runtime_errors + 1 end
            for i, count in ipairs(program.peephole) do peephole[i] = peephole[i] + count end
            rows[#rows + 1] = { program.name, program.execution.error and "runtime error" or "ok",
                tostring(#program.after), tostring(program.execution.executed), tostring(#program.execution.output) }
        end
    end
    local lines = { "== summary ==", "programs: " .. #programs, "compiled: " .. compiled,
        string.format("compile errors: lexical %d syntax %d semantic %d", errors.lexical, errors.syntax, errors.semantic),
        "runtime errors: " .. runtime_errors, "folds: " .. folds, "peephole: " .. sum(peephole) }
    for i, rule in ipairs(rules) do lines[#lines + 1] = "  " .. rule .. " " .. peephole[i] end
    lines[#lines + 1] = "executed: " .. executed
    local widths = { 0, 0, 0, 0, 0 }
    for _, row in ipairs(rows) do for i, value in ipairs(row) do widths[i] = math.max(widths[i], #value) end end
    for _, row in ipairs(rows) do
        local fields = {}
        for i, value in ipairs(row) do
            local padding = string.rep(" ", widths[i] - #value)
            fields[i] = i <= 2 and value .. padding or padding .. value
        end
        lines[#lines + 1] = "  " .. table.concat(fields, "  ")
    end
    return lines
end
local programs, by_name, current, line_number = {}, {}, false, 0
for text in io.lines("input/program.src") do
    line_number = line_number + 1
    if text:sub(1, 9) == "#program " then
        current = { name = text:sub(10), lines = {}, inputs = {}, source_text = {} }
        programs[#programs + 1], by_name[current.name] = current, current
    else
        current.lines[#current.lines + 1], current.source_text[line_number] = { line_number, text }, text
    end
end
for text in io.lines("input/input.txt") do
    if text:sub(1, 7) == "#input " then current = by_name[text:sub(8)]
    else for word in text:gmatch("%S+") do current.inputs[#current.inputs + 1] = tonumber(word) end end
end
for _, program in ipairs(programs) do
    local ok, err = pcall(compile, program)
    if not ok then
        if type(err) ~= "table" or err.category ~= "compile" then error(err) end
        program.error = err
    end
    local heading = "== program " .. program.name .. " =="
    for _, lines in pairs(reports) do lines[#lines + 1] = heading end
    append(reports["diagnostics.txt"], diagnostics(program))
    if program.error then
        reports["listing.txt"][#reports["listing.txt"] + 1] = "not compiled"
        reports["stats.txt"][#reports["stats.txt"] + 1] = "not compiled"
    else
        append(reports["listing.txt"], listing(program))
        append(reports["output.txt"], program.execution.output)
        append(reports["stats.txt"], statistics(program))
    end
end
append(reports["stats.txt"], summary(programs))
for name, lines in pairs(reports) do
    local output = assert(io.open("output/" .. name, "w"))
    output:write(table.concat(lines, "\n"), "\n")
    output:close()
end
