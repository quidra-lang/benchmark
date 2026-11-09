local Lexer = require("lexer")
local Parser = require("parser")
local V = require("values_fields")
local Builtins = require("builtins")
local Streams = require("streams")
local special_names = { "FILENAME", "FNR", "FS", "NF", "NR", "OFS", "ORS", "SUBSEP" }
local function keys(values, comparator)
    local result = {}
    for key in pairs(values) do result[#result + 1] = key end
    table.sort(result, comparator)
    return result
end
local function count(values)
    local result = 0
    for _ in pairs(values) do result = result + 1 end
    return result
end
local function clear(values) for key in pairs(values) do values[key] = nil end end
local A = {}
A.__index = A
function A.new(items)
    local result = setmetatable({ items = items, functions = {}, rules = {}, function_table = {}, global_names = {},
        bindings = {}, global_bindings = {}, local_bindings = {}, array_names = {}, statement_lines = {}, nodes = {}, errors = {} }, A)
    for _, name in ipairs(special_names) do result.global_names[name] = true end
    for _, item in ipairs(items) do
        local target = item.kind == "function" and result.functions or result.rules
        target[#target + 1] = item
    end
    return result
end
function A:binding(scope, name)
    local values = self.global_bindings
    if scope then
        if not self.local_bindings[scope] then self.local_bindings[scope] = {} end
        values = self.local_bindings[scope]
    end
    if not values[name] then
        local binding = { scope = scope, name = name }
        binding.parent = binding
        values[name], self.bindings[binding] = binding, true
    end
    return values[name]
end
function A:error(position, priority, message) self.errors[#self.errors + 1] = { position = position, priority = priority, message = message } end
function A:prepare()
    for _, name in ipairs(special_names) do self:binding(false, name) end
    for _, fn in ipairs(self.functions) do
        if self.function_table[fn.name] then self:error(fn.name_position, 1, "function " .. fn.name .. " redefined")
        else self.function_table[fn.name] = fn end
        fn.parameter_names = {}
        for _, parameter in ipairs(fn.parameters) do
            if fn.parameter_names[parameter.name] then self:error(parameter.position, 2, "duplicate parameter " .. parameter.name) end
            fn.parameter_names[parameter.name] = true
        end
    end
    for _, item in ipairs(self.items) do
        local fn = item.kind == "function" and item or false
        local pending = { item }
        while #pending > 0 do
            local node = table.remove(pending)
            self.nodes[#self.nodes + 1] = node
            if Parser.statements[node.kind] then self.statement_lines[node.position[1]] = true end
            if node.kind == "name" or node.kind == "array" or node.kind == "parameter" then
                local scope = fn and fn.parameter_names[node.name] and fn or false
                node.binding = self:binding(scope, node.name)
                if not scope then self.global_names[node.name] = true end
                if self.function_table[node.name] then self:error(node.position, 3, "function " .. node.name .. " used as variable") end
            elseif node.kind == "call" then
                local target = self.function_table[node.name]
                if not target then self:error(node.position, 4, "undefined function " .. node.name)
                else
                    node.target_function = target
                    if #node.arguments > #target.parameters then self:error(node.position, 5, "too many arguments to " .. node.name) end
                end
            end
            for i = #node.children, 1, -1 do pending[#pending + 1] = node.children[i] end
        end
    end
    if #self.errors > 0 then
        table.sort(self.errors, function(a, b)
            if a.position[1] ~= b.position[1] then return a.position[1] < b.position[1] end
            if a.position[2] ~= b.position[2] then return a.position[2] < b.position[2] end
            return a.priority < b.priority
        end)
        local err = self.errors[1]
        error({ category = "static", position = err.position, message = err.message }, 0)
    end
    local links = {}
    for _, node in ipairs(self.nodes) do
        if node.kind == "array" then self.array_names[node.binding] = true
        elseif node.kind == "membership" or node.kind == "delete" or node.kind == "for_in" then self.array_names[node.array.binding] = true
        elseif node.kind == "builtin" and node.name == "split" then self.array_names[node.arguments[2].binding] = true
        elseif node.kind == "call" then
            for i, argument in ipairs(node.arguments) do
                if argument.kind == "name" then links[#links + 1] = { argument.binding, node.target_function.parameters[i].binding } end
            end
        end
    end
    local function root(binding)
        while binding.parent ~= binding do binding.parent, binding = binding.parent.parent, binding.parent end
        return binding
    end
    for _, link in ipairs(links) do root(link[1]).parent = root(link[2]) end
    local array_roots = {}
    for binding in pairs(self.array_names) do array_roots[root(binding)] = true end
    self.array_names = {}
    for binding in pairs(self.bindings) do if array_roots[root(binding)] then self.array_names[binding] = true end end
    return self
end
local function transfer(kind, value) error({ category = "transfer", kind = kind, value = value or V.UNINITIALIZED }, 0) end
local function arithmetic(operator, first, second, position)
    local a, b, result = V.to_number(first), V.to_number(second)
    if operator == "/" or operator == "%" then
        if b == 0 then Builtins.fail(position, "division by zero") end
        local quotient = math.abs(a) // math.abs(b)
        if (a < 0) ~= (b < 0) then quotient = -quotient end
        result = operator == "/" and quotient or a - quotient * b
    elseif operator == "^" then
        if b < 0 then Builtins.fail(position, "negative exponent") end
        result = 1
        while b > 0 do
            if b % 2 == 1 then result = result * a end
            b = b // 2
            if b > 0 then a = a * a end
        end
    elseif operator == "+" then result = a + b elseif operator == "-" then result = a - b else result = a * b end
    return V.number(result)
end
local E = {}
E.__index = E
function E.new(analysis, options, operands)
    local result = setmetatable({ analysis = analysis, options = options, operands = operands, global_names = {}, globals = {},
        locals = {}, streams = Streams.new(), lines = {}, phase = "BEGIN", exit_status = 0, operand_position = 1,
        current_operand = false, input_lines = {}, input_position = 1 }, E)
    for name in pairs(analysis.global_names) do
        result.global_names[name] = true
        result.globals[name] = analysis.array_names[analysis.global_bindings[name]] and {} or V.UNINITIALIZED
    end
    local values = { FILENAME = V.string(""), FNR = V.number(0), FS = V.string(" "), NF = V.number(0), NR = V.number(0),
        OFS = V.string(" "), ORS = V.string("\n"), SUBSEP = V.string(string.char(28)) }
    for name, value in pairs(values) do result.globals[name] = value end
    result.record = V.record(function(name) return result:global_value(name) end)
    for line in pairs(analysis.statement_lines) do result.lines[line] = 0 end
    for _, rule in ipairs(analysis.rules) do rule.count, rule.inside = 0, false end
    for _, fn in ipairs(analysis.functions) do fn.call_count, fn.active_calls, fn.max_depth = 0, 0, 0 end
    return result
end
function E:global_value(name)
    if name == "NF" then return V.number(#self.record.fields) end
    return self.globals[name]
end
function E:variable(binding)
    if binding.scope then return self.locals[#self.locals][binding.name] end
    return self:global_value(binding.name)
end
function E:assign_global_input(name, text) self.global_names[name], self.globals[name] = true, V.input(text) end
function E:subscript(expressions)
    local values = {}
    for _, expression in ipairs(expressions) do values[#values + 1] = V.to_string(self:evaluate(expression)) end
    return table.concat(values, V.to_string(self:global_value("SUBSEP")))
end
function E:location(node)
    if node.kind == "name" then return { kind = "variable", binding = node.binding }
    elseif node.kind == "array" then
        local key = self:subscript(node.indexes)
        return { kind = "array", array = self:variable(node.binding), key = key }
    end
    local index = V.to_number(self:evaluate(node.index))
    if index < 0 then Builtins.fail(node.position, "negative field index") end
    return { kind = "field", index = index }
end
function E:read(location)
    if location.kind == "variable" then return self:variable(location.binding)
    elseif location.kind == "field" then return self.record:read(location.index) end
    if location.array[location.key] == nil then location.array[location.key] = V.UNINITIALIZED end
    return location.array[location.key]
end
function E:store(location, value, position)
    if location.kind == "field" then self.record:write(location.index, value)
    elseif location.kind == "array" then location.array[location.key] = value
    elseif location.binding.scope then self.locals[#self.locals][location.binding.name] = value
    elseif location.binding.name == "NF" then
        local size = V.to_number(value)
        if size < 0 then Builtins.fail(position, "negative NF") end
        self.record:resize(size)
    else self.globals[location.binding.name] = value end
end
function E:evaluate(node)
    local kind = node.kind
    if kind == "number" then return V.number(node.value)
    elseif kind == "string" then return V.string(node.value)
    elseif kind == "name" or kind == "array" or kind == "field" then return self:read(self:location(node))
    elseif kind == "paren" then return self:evaluate(node.expression)
    elseif kind == "assignment" then
        local location = self:location(node.location)
        local value = self:evaluate(node.value)
        if node.operator ~= "=" then value = arithmetic(node.operator:sub(1, -2), self:read(location), value, node.position) end
        self:store(location, value, node.position)
        return self:read(location)
    elseif kind == "increment" then
        local location = self:location(node.location)
        local old = V.to_number(self:read(location))
        local value = old + node.delta
        self:store(location, V.number(value), node.position)
        return V.number(node.prefix and value or old)
    elseif kind == "conditional" then
        local branch = V.truth(self:evaluate(node.condition)) and node.first or node.second
        return self:evaluate(branch)
    elseif kind == "unary" then
        local value = self:evaluate(node.operand)
        if node.operator == "!" then return V.number(not V.truth(value) and 1 or 0) end
        local integer = V.to_number(value)
        return V.number(node.operator == "-" and -integer or integer)
    elseif kind == "membership" then
        local key = self:subscript(node.indexes)
        return V.number(self:variable(node.array.binding)[key] ~= nil and 1 or 0)
    elseif kind == "binary" then
        local first, operator = self:evaluate(node.left), node.operator
        if operator == "||" and V.truth(first) then return V.number(1) end
        if operator == "&&" and not V.truth(first) then return V.number(0) end
        local second = self:evaluate(node.right)
        if operator == "||" or operator == "&&" then return V.number(V.truth(second) and 1 or 0)
        elseif operator == "concat" then return V.string(V.to_string(first) .. V.to_string(second))
        elseif Parser.comparisons[operator] then
            local order, result = V.compare(first, second)
            if operator == "<" then result = order < 0 elseif operator == "<=" then result = order <= 0
            elseif operator == "==" then result = order == 0 elseif operator == "!=" then result = order ~= 0
            elseif operator == ">=" then result = order >= 0 else result = order > 0 end
            return V.number(result and 1 or 0)
        end
        return arithmetic(operator, first, second, node.position)
    elseif kind == "call" then return self:call(node)
    elseif kind == "builtin" then return self:builtin(node) end
    return self:getline(node)
end
function E:call(node)
    local fn, frame = node.target_function, {}
    for i, parameter in ipairs(fn.parameters) do
        local is_array = self.analysis.array_names[parameter.binding]
        if node.arguments[i] then frame[parameter.name] = is_array and self:variable(node.arguments[i].binding) or self:evaluate(node.arguments[i])
        else frame[parameter.name] = is_array and {} or V.UNINITIALIZED end
    end
    fn.call_count, fn.active_calls = fn.call_count + 1, fn.active_calls + 1
    fn.max_depth = math.max(fn.max_depth, fn.active_calls)
    self.locals[#self.locals + 1] = frame
    local ok, err = pcall(self.statement, self, fn.body)
    table.remove(self.locals)
    fn.active_calls = fn.active_calls - 1
    if not ok then
        if type(err) == "table" and err.category == "transfer" and err.kind == "return" then return err.value end
        error(err, 0)
    end
    return V.UNINITIALIZED
end
function E:builtin(node)
    local name, arguments = node.name, node.arguments
    if name == "length" then
        if #arguments == 0 then return V.number(#V.to_string(self.record.zero)) end
        local argument = arguments[1]
        if argument.kind == "name" and self.analysis.array_names[argument.binding] then return V.number(count(self:variable(argument.binding))) end
        return V.number(#V.to_string(self:evaluate(argument)))
    elseif name == "split" then
        local text = V.to_string(self:evaluate(arguments[1]))
        local separator = arguments[3] and V.to_string(self:evaluate(arguments[3])) or V.to_string(self:global_value("FS"))
        local array = self:variable(arguments[2].binding)
        clear(array)
        local pieces = V.split(text, separator)
        for i, piece in ipairs(pieces) do array[tostring(i)] = V.input(piece) end
        return V.number(#pieces)
    elseif name == "close" then return V.number(self.streams:close(V.to_string(self:evaluate(arguments[1])))) end
    local values = {}
    for i, argument in ipairs(arguments) do values[i] = self:evaluate(argument) end
    return Builtins.invoke(name, values, node.position)
end
function E:getline(node)
    local status, line
    if node.filename then
        local filename = V.to_string(self:evaluate(node.filename))
        status, line = self.streams:getline(filename)
    elseif self.phase == "END" then return V.number(0)
    else
        line = self:next_record()
        status = line ~= nil and 1 or 0
    end
    if status == 1 then
        if not node.target then self.record:set(line)
        else
            local location = self:location(node.target)
            self:store(location, V.input(line), node.position)
        end
    end
    return V.number(status)
end
function E:output(node)
    local arguments = {}
    for i, argument in ipairs(node.arguments) do arguments[i] = self:evaluate(argument) end
    local text
    if node.kind == "print" then
        if #arguments == 0 then arguments[1] = self.record.zero end
        local parts = {}
        for i, value in ipairs(arguments) do parts[i] = V.to_string(value) end
        text = table.concat(parts, V.to_string(self:global_value("OFS"))) .. V.to_string(self:global_value("ORS"))
    else text = Builtins.format(arguments, node.position) end
    local filename = node.filename and V.to_string(self:evaluate(node.filename)) or nil
    self.streams:write(text, filename, node.redirect, node.redirect_position)
end
function E:loop_body(body)
    local ok, err = pcall(self.statement, self, body)
    if not ok then
        if type(err) == "table" and err.category == "transfer" then
            if err.kind == "break" then return false elseif err.kind == "continue" then return true end
        end
        error(err, 0)
    end
    return true
end
function E:statement(node)
    local kind = node.kind
    if kind == "block" then for _, child in ipairs(node.statements) do self:statement(child) end; return
    elseif kind == "empty" then return end
    self.lines[node.position[1]] = self.lines[node.position[1]] + 1
    if kind == "expression_statement" then self:evaluate(node.expression)
    elseif kind == "print" or kind == "printf" then self:output(node)
    elseif kind == "if" then
        local branch = V.truth(self:evaluate(node.condition)) and node.first or node.second
        if branch then self:statement(branch) end
    elseif kind == "while" then
        while V.truth(self:evaluate(node.condition)) do if not self:loop_body(node.body) then break end end
    elseif kind == "do" then
        repeat
            if not self:loop_body(node.body) then break end
        until not V.truth(self:evaluate(node.condition))
    elseif kind == "for" then
        if node.initial then self:evaluate(node.initial) end
        while not node.condition or V.truth(self:evaluate(node.condition)) do
            if not self:loop_body(node.body) then break end
            if node.update then self:evaluate(node.update) end
        end
    elseif kind == "for_in" then
        local subscripts = keys(self:variable(node.array.binding), V.key_less)
        for _, key in ipairs(subscripts) do
            self:store({ kind = "variable", binding = node.variable.binding }, V.input(key), node.variable.position)
            if not self:loop_body(node.body) then break end
        end
    elseif kind == "delete" then
        local array = self:variable(node.array.binding)
        if not node.indexes then clear(array) else array[self:subscript(node.indexes)] = nil end
    elseif kind == "next" then
        if self.phase == "BEGIN" or self.phase == "END" then Builtins.fail(node.position, "next used in BEGIN or END") end
        transfer("next")
    elseif kind == "exit" then
        if node.value then self.exit_status = V.to_number(self:evaluate(node.value)) end
        transfer("exit")
    elseif kind == "return" then transfer("return", node.value and self:evaluate(node.value) or V.UNINITIALIZED)
    else transfer(kind) end
end
function E:next_record()
    while true do
        if self.input_position <= #self.input_lines then
            local line = self.input_lines[self.input_position]
            self.input_position = self.input_position + 1
            self.current_operand.records = self.current_operand.records + 1
            self.globals.NR = V.number(V.to_number(self:global_value("NR")) + 1)
            self.globals.FNR = V.number(V.to_number(self:global_value("FNR")) + 1)
            return line
        end
        if self.operand_position > #self.operands then return nil end
        local operand = self.operands[self.operand_position]
        self.operand_position = self.operand_position + 1
        if operand.kind == "assignment" then self:assign_global_input(operand.name, operand.value)
        else
            self.current_operand, self.input_lines, self.input_position = operand, assert(Streams.read_records(operand.name)), 1
            self.globals.FILENAME, self.globals.FNR = V.string(operand.name), V.number(0)
        end
    end
end
function E:run_actions(phase)
    self.phase = phase
    for _, rule in ipairs(self.analysis.rules) do
        if rule.flavor == phase then rule.count = rule.count + 1; self:statement(rule.action) end
    end
end
function E:matches(rule)
    if rule.flavor == "all" then return true
    elseif rule.flavor == "pattern" then return V.truth(self:evaluate(rule.patterns[1])) end
    if not rule.inside and V.truth(self:evaluate(rule.patterns[1])) then rule.inside = true end
    if not rule.inside then return false end
    if V.truth(self:evaluate(rule.patterns[2])) then rule.inside = false end
    return true
end
function E:run_records()
    local has_records, rules = false, {}
    for _, rule in ipairs(self.analysis.rules) do
        if rule.flavor ~= "BEGIN" then has_records = true end
        if rule.flavor ~= "BEGIN" and rule.flavor ~= "END" then rules[#rules + 1] = rule end
    end
    if not has_records then return end
    self.phase = "records"
    while true do
        local line = self:next_record()
        if line == nil then return end
        self.record:set(line)
        local ok, err = pcall(function()
            for _, rule in ipairs(rules) do
                if self:matches(rule) then
                    rule.count = rule.count + 1
                    if rule.action then self:statement(rule.action)
                    else self.streams:write(V.to_string(self.record.zero) .. V.to_string(self:global_value("ORS"))) end
                end
            end
        end)
        if not ok and not (type(err) == "table" and err.category == "transfer" and err.kind == "next") then error(err, 0) end
    end
end
function E:execute()
    local function allow_exit(ok, err)
        if not ok and not (type(err) == "table" and err.category == "transfer" and err.kind == "exit") then error(err, 0) end
    end
    local ok, err = pcall(function()
        for _, option in ipairs(self.options) do self:assign_global_input(option[1], option[2]) end
        allow_exit(pcall(function() self:run_actions("BEGIN"); self:run_records() end))
        allow_exit(pcall(self.run_actions, self, "END"))
    end)
    if not ok then
        if type(err) ~= "table" or err.category ~= "runtime" then error(err, 0) end
        self.error = err
    end
end
function E:statistics()
    local status = "status: exit " .. self.exit_status
    if self.error then status = string.format("status: runtime error at %d:%d: %s", self.error.position[1], self.error.position[2], self.error.message) end
    local lines = { status, "[inputs]" }
    for _, operand in ipairs(self.operands) do if operand.kind == "file" then lines[#lines + 1] = operand.name .. " records=" .. operand.records end end
    lines[#lines + 1] = "[getline]"
    for _, name in ipairs(self.streams.input_order) do
        local source = self.streams.inputs[name]
        lines[#lines + 1] = name .. " " .. (source.ever_opened and "reads=" .. source.reads or "missing")
    end
    lines[#lines + 1] = "[rules]"
    for _, rule in ipairs(self.analysis.rules) do lines[#lines + 1] = string.format("%d:%d %s count=%d", rule.position[1], rule.position[2], rule.flavor, rule.count) end
    lines[#lines + 1] = "[functions]"
    for _, fn in ipairs(self.analysis.functions) do lines[#lines + 1] = string.format("%s calls=%d depth=%d", fn.name, fn.call_count, fn.max_depth) end
    lines[#lines + 1] = "[outputs]"
    lines[#lines + 1] = string.format("stdout.txt writes=%d bytes=%d", self.streams.stdout.writes, self.streams.stdout.bytes)
    for _, name in ipairs(self.streams.output_order) do
        local output = self.streams.outputs[name]
        lines[#lines + 1] = string.format("%s writes=%d bytes=%d", name, output.writes, output.bytes)
    end
    lines[#lines + 1] = "[lines]"
    for _, line in ipairs(keys(self.lines)) do lines[#lines + 1] = line .. " count=" .. self.lines[line] end
    lines[#lines + 1] = "[globals]"
    for _, name in ipairs(keys(self.global_names)) do
        local value = self:global_value(name)
        local binding = self.analysis.global_bindings[name]
        local text = binding and self.analysis.array_names[binding] and "array (" .. count(value) .. ")" or V.describe(value)
        lines[#lines + 1] = name .. " = " .. text
    end
    return lines
end
local options, operands = Streams.arguments()
local input = assert(io.open("input/program.awk", "r"))
local source = input:read("*a")
input:close()
local ok, analysis = pcall(function() return A.new(Parser.new(Lexer.tokenize(source)):parse()):prepare() end)
local statistics, streams
if not ok then
    if type(analysis) ~= "table" then error(analysis, 0) end
    if analysis.category == "syntax" then statistics = { string.format("status: syntax error at %d:%d", analysis.position[1], analysis.position[2]) }
    elseif analysis.category == "static" then statistics = { string.format("status: error at %d:%d: %s", analysis.position[1], analysis.position[2], analysis.message) }
    else error(analysis, 0) end
    streams = Streams.new()
else
    local engine = E.new(analysis, options, operands)
    engine:execute()
    statistics, streams = engine:statistics(), engine.streams
end
streams:save()
local output = assert(io.open("output/stats.txt", "w"))
output:write(table.concat(statistics, "\n"), "\n")
output:close()
