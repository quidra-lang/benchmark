local lexer = require("lexer")
local Parser = require("parser")
local U = require("unifier")
local Inferencer = require("inference")
local Evaluator = require("evaluator")
local function copy(source)
    local result = {}
    for key, value in pairs(source) do result[key] = value end
    return result
end
local function position_less(a, b)
    return a[2] < b[2] or (a[2] == b[2] and a[3] < b[3])
end
local function print_value(value)
    local kind = type(value)
    if kind == "boolean" then return value and "true" or "false"
    elseif kind == "number" then return tostring(value)
    elseif kind == "string" then
        local escaped = value:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n"):gsub("\t", "\\t")
        return '"' .. escaped .. '"'
    elseif value.kind == "pair" then return "(" .. print_value(value.items[1]) .. ", " .. print_value(value.items[2]) .. ")"
    elseif value.kind == "list" then
        local parts = {}
        for _, item in ipairs(value.items) do parts[#parts + 1] = print_value(item) end
        return "[" .. table.concat(parts, "; ") .. "]"
    end
    return "<fun>"
end
local function type_printer(quantified)
    local names, count = {}, 0
    local function render(value)
        value = U.resolve(value)
        if value.kind == "variable" then
            if not names[value] then
                local prefix = quantified and not quantified[value] and "'_" or "'"
                names[value] = prefix .. string.char(97 + count % 26) .. (count >= 26 and tostring(count // 26) or "")
                count = count + 1
            end
            return names[value]
        end
        if value.kind == "int" or value.kind == "bool" or value.kind == "string" then return value.kind end
        local first = U.resolve(value.children[1])
        local left = render(first)
        if value.kind == "list" then
            if first.kind == "pair" or first.kind == "function" then left = "(" .. left .. ")" end
            return left .. " list"
        end
        local second = U.resolve(value.children[2])
        local right = render(second)
        if value.kind == "pair" then
            if first.kind == "pair" or first.kind == "function" then left = "(" .. left .. ")" end
            if second.kind == "pair" or second.kind == "function" then right = "(" .. right .. ")" end
            return left .. " * " .. right
        end
        if first.kind == "function" then left = "(" .. left .. ")" end
        return left .. " -> " .. right
    end
    return render
end
local function format_declared_type(expression)
    local kind = expression.kind
    if kind == "type_variable" then return expression.value end
    if kind == "int" or kind == "bool" or kind == "string" then return kind end
    local first = expression.children[1]
    local left = format_declared_type(first)
    if kind == "list" then
        if first.kind == "pair" or first.kind == "function" then left = "(" .. left .. ")" end
        return left .. " list"
    end
    local second = expression.children[2]
    local right = format_declared_type(second)
    if kind == "pair" then
        if first.kind == "pair" or first.kind == "function" then left = "(" .. left .. ")" end
        if second.kind == "pair" or second.kind == "function" then right = "(" .. right .. ")" end
        return left .. " * " .. right
    end
    if first.kind == "function" then left = "(" .. left .. ")" end
    return left .. " -> " .. right
end
local function signature_type(expression, variables)
    if expression.kind == "type_variable" then
        if not variables[expression.value] then variables[expression.value] = U.variable() end
        return variables[expression.value]
    end
    local result = U.type(expression.kind)
    for i, child in ipairs(expression.children) do result.children[i] = signature_type(child, variables) end
    return result
end
local function identical(first, second)
    first, second = U.resolve(first), U.resolve(second)
    if first.kind == "variable" or second.kind == "variable" then return first == second end
    if first.kind ~= second.kind then return false end
    for i, child in ipairs(first.children) do if not identical(child, second.children[i]) then return false end end
    return true
end
local function signature_matches(inferred, declared, assignments)
    inferred, declared = U.resolve(inferred), U.resolve(declared)
    if inferred.kind == "variable" then
        if assignments[inferred] then return identical(assignments[inferred], declared) end
        assignments[inferred] = declared
        return true
    end
    if declared.kind == "variable" or inferred.kind ~= declared.kind then return false end
    for i, child in ipairs(inferred.children) do
        if not signature_matches(child, declared.children[i], assignments) then return false end
    end
    return true
end
local function check_signatures(group, signatures)
    for i, binding in ipairs(group.bindings) do
        if signatures[i] then
            local declared = signature_type(signatures[i][2], {})
            local inferred = binding.scheme.value
            if not signature_matches(inferred, declared, {}) then
                Inferencer.error("signature", binding.position, { name = binding.name, inferred = inferred, declared = declared })
            end
            binding.scheme = U.scheme(declared, U.free(declared))
        end
    end
end
local function distance(first, second)
    local previous = {}
    for i = 0, #second do previous[i] = i end
    for i = 1, #first do
        local current = { [0] = i }
        for j = 1, #second do
            current[j] = math.min(current[j - 1] + 1, previous[j] + 1,
                previous[j - 1] + (first:sub(i, i) == second:sub(j, j) and 0 or 1))
        end
        previous = current
    end
    return previous[#second]
end
local function type_error_message(err)
    local details, render = err.details, type_printer()
    if err.kind == "unbound" then
        local message, best, best_distance = "unbound variable '" .. details.name .. "'", false, 3
        for _, candidate in ipairs(details.candidates) do
            local d = distance(details.name, candidate)
            if d <= 2 and d < #details.name and (d < best_distance or (d == best_distance and candidate < best)) then
                best, best_distance = candidate, d
            end
        end
        if best then message = message .. " (did you mean '" .. best .. "'?)" end
        return message
    elseif err.kind == "not_function" then return "expected a function but found " .. render(details.found)
    elseif err.kind == "check" then
        local expected, found = render(details.expected), render(details.found)
        local message = "expected " .. expected .. " but found " .. found
        local failure = details.failure
        if failure.infinite then
            local variable, value = failure.expected, failure.found
            if variable.kind ~= "variable" then variable, value = value, variable end
            local variable_text, value_text = render(variable), render(value)
            message = message .. " (infinite type " .. variable_text .. " = " .. value_text .. ")"
        elseif failure.nested then
            local first, second = render(failure.expected), render(failure.found)
            message = message .. " (" .. first .. " vs " .. second .. ")"
        end
        return message
    elseif err.kind == "duplicate_pattern" then return "variable '" .. details.name .. "' is bound twice in this pattern"
    elseif err.kind == "duplicate_let" then return "variable '" .. details.name .. "' is bound twice in this let"
    elseif err.kind == "recursive_function" then return "'" .. details.name .. "' in let rec must be a function" end
    local inferred, declared = render(details.inferred), render(details.declared)
    return "'" .. details.name .. "' has type " .. inferred .. " but its signature is " .. declared
end
local function builtins()
    local first, second = U.variable(), U.variable()
    local fst = U.scheme(U.type("function", U.type("pair", first, second), first), { [first] = true, [second] = true })
    first, second = U.variable(), U.variable()
    local snd = U.scheme(U.type("function", U.type("pair", first, second), second), { [first] = true, [second] = true })
    local result = U.variable()
    local types = { fst = fst, snd = snd, ["not"] = U.scheme(U.type("function", U.BOOL, U.BOOL)),
        string_of_int = U.scheme(U.type("function", U.INT, U.STRING)),
        failwith = U.scheme(U.type("function", U.STRING, result), { [result] = true }) }
    local values = { fst = Evaluator.builtin(function(value) return value.items[1] end),
        snd = Evaluator.builtin(function(value) return value.items[2] end),
        ["not"] = Evaluator.builtin(function(value) return not value end),
        string_of_int = Evaluator.builtin(function(value) return tostring(value) end),
        failwith = Evaluator.builtin(function(value, position) Evaluator.failure(position, "failure " .. print_value(value)) end) }
    return types, values
end
local function leading_parameters(expression)
    local parameters = {}
    while expression.kind == "fun" do
        parameters[#parameters + 1], expression = expression.value.spelling, expression.children[1]
    end
    return parameters, expression
end
local format_expression
local function format_group(group)
    local bindings = {}
    for _, binding in ipairs(group.bindings) do
        local parameters, body = leading_parameters(binding.expression)
        local parts = { binding.name }
        for _, parameter in ipairs(parameters) do parts[#parts + 1] = parameter end
        parts[#parts + 1], parts[#parts + 2] = "=", format_expression(body, 0)
        bindings[#bindings + 1] = table.concat(parts, " ")
    end
    return (group.rec_position and "let rec " or "let ") .. table.concat(bindings, " and ")
end
local function ends_with_match(expression)
    if expression.kind == "match" then return true
    elseif expression.kind == "let" or expression.kind == "fun" then return ends_with_match(expression.children[1])
    elseif expression.kind == "if" then return ends_with_match(expression.children[3]) end
    return false
end
local function format_pattern(pattern)
    local kind = pattern.kind
    if kind == "wildcard" or kind == "name" then return pattern.value
    elseif kind == "integer" or kind == "boolean" or kind == "string" then return print_value(pattern.value)
    elseif kind == "list" then
        local elements = {}
        for _, child in ipairs(pattern.children) do elements[#elements + 1] = format_pattern(child) end
        return "[" .. table.concat(elements, "; ") .. "]"
    end
    local first, second = pattern.children[1], pattern.children[2]
    local left, right = format_pattern(first), format_pattern(second)
    if kind == "pair" then return "(" .. left .. ", " .. right .. ")" end
    if first.kind == "cons" then left = "(" .. left .. ")" end
    return left .. " :: " .. right
end
format_expression = function(expression, minimum)
    minimum = minimum or 0
    local kind, children, strength, text = expression.kind, expression.children, 9
    if kind == "integer" or kind == "boolean" or kind == "string" then text = print_value(expression.value)
    elseif kind == "name" then text = expression.value
    elseif kind == "fun" then
        local parameters, body = leading_parameters(expression)
        strength, text = 0, "fun " .. table.concat(parameters, " ") .. " -> " .. format_expression(body)
    elseif kind == "apply" then strength, text = 8, format_expression(children[1], 8) .. " " .. format_expression(children[2], 9)
    elseif kind == "binary" then
        local operator = expression.value.spelling
        local info = Parser.operators[operator]
        strength = info[1]
        text = format_expression(children[1], info[2] and strength + 1 or strength) .. " " .. operator .. " "
            .. format_expression(children[2], info[2] and strength or strength + 1)
    elseif kind == "negate" then strength, text = 7, "-" .. format_expression(children[1], 7)
    elseif kind == "if" then
        strength, text = 0, "if " .. format_expression(children[1]) .. " then " .. format_expression(children[2]) .. " else " .. format_expression(children[3])
    elseif kind == "pair" then text = "(" .. format_expression(children[1]) .. ", " .. format_expression(children[2]) .. ")"
    elseif kind == "list" then
        local elements = {}
        for _, child in ipairs(children) do elements[#elements + 1] = format_expression(child) end
        text = "[" .. table.concat(elements, "; ") .. "]"
    elseif kind == "let" then strength, text = 0, format_group(expression.value) .. " in " .. format_expression(children[1])
    elseif kind == "match" then
        local arms = {}
        for i, arm in ipairs(expression.value) do
            local body = format_expression(arm[2])
            if i < #expression.value and ends_with_match(arm[2]) then body = "(" .. body .. ")" end
            arms[#arms + 1] = format_pattern(arm[1]) .. " -> " .. body
        end
        strength, text = 0, "match " .. format_expression(children[1]) .. " with " .. table.concat(arms, " | ")
    end
    return strength < minimum and "(" .. text .. ")" or text
end
local function format_item(item)
    if item.kind == "signature" then
        return "val " .. item.value[1].spelling .. " : " .. format_declared_type(item.value[2]) .. ";;"
    elseif item.kind == "declaration" then return format_group(item.value) .. ";;" end
    return format_expression(item.value) .. ";;"
end
local function coverage_type(value)
    value = U.resolve(value)
    local result = { kind = value.kind, children = {} }
    if value.kind == "variable" or value.kind == "function" then result.kind = "opaque"
    else for i, child in ipairs(value.children) do result.children[i] = coverage_type(child) end end
    return result
end
local function coverage_pattern(pattern)
    local kind = pattern.kind
    if kind == "wildcard" or kind == "name" then return false end
    if kind == "integer" or kind == "boolean" or kind == "string" then
        return { tag = kind, value = pattern.value, args = {} }
    end
    if kind == "list" then
        local result = { tag = "nil", args = {} }
        for i = #pattern.children, 1, -1 do
            result = { tag = "cons", args = { coverage_pattern(pattern.children[i]), result } }
        end
        return result
    end
    return { tag = kind == "pair" and "pair" or "cons",
        args = { coverage_pattern(pattern.children[1]), coverage_pattern(pattern.children[2]) } }
end
local function constructors(value_type)
    if value_type.kind == "bool" then return { { tag = "boolean", value = false }, { tag = "boolean", value = true } }
    elseif value_type.kind == "list" then return { { tag = "nil" }, { tag = "cons" } }
    elseif value_type.kind == "pair" then return { { tag = "pair" } } end
    return {}
end
local function constructor_arguments(constructor, value_type)
    if constructor.tag == "pair" then return value_type.children
    elseif constructor.tag == "cons" then return { value_type.children[1], value_type } end
    return {}
end
local function same_constructor(a, b) return a.tag == b.tag and a.value == b.value end
local function specialize(matrix, constructor, arity)
    local result = {}
    for _, row in ipairs(matrix) do
        if not row[1] or same_constructor(row[1], constructor) then
            local selected = {}
            for i = 1, arity do selected[i] = row[1] and row[1].args[i] or false end
            for i = 2, #row do selected[#selected + 1] = row[i] end
            result[#result + 1] = selected
        end
    end
    return result
end
local function sequence(prefix, values, first)
    local result = { table.unpack(prefix) }
    for i = first or 1, #values do result[#result + 1] = values[i] end
    return result
end
local function coverage_checker()
    local memo, identities, next_id = {}, {}, 0
    local function identity(value)
        if not value then return "0" end
        if not identities[value] then next_id = next_id + 1; identities[value] = tostring(next_id) end
        return identities[value]
    end
    local function key(matrix, query, types)
        local parts = {}
        for _, row in ipairs(matrix) do
            local entries = {}
            for i, pattern in ipairs(row) do entries[i] = identity(pattern) end
            parts[#parts + 1] = table.concat(entries, ",")
        end
        local q, t = {}, {}
        for i, pattern in ipairs(query) do q[i] = identity(pattern) end
        for i, value in ipairs(types) do t[i] = identity(value) end
        return table.concat(parts, ";") .. "|" .. table.concat(q, ",") .. "|" .. table.concat(t, ",")
    end
    local useful
    useful = function(matrix, query, types)
        if #query == 0 then return #matrix == 0 end
        if #matrix == 0 then return true end
        local memo_key = key(matrix, query, types)
        if memo[memo_key] ~= nil then return memo[memo_key] end
        local head, result = query[1], false
        if head then
            local argument_types = constructor_arguments(head, types[1])
            result = useful(specialize(matrix, head, #head.args), sequence(head.args, query, 2), sequence(argument_types, types, 2))
        else
            local possible, complete = constructors(types[1]), true
            for _, constructor in ipairs(possible) do
                local present = false
                for _, row in ipairs(matrix) do
                    if row[1] and same_constructor(row[1], constructor) then present = true; break end
                end
                if not present then complete = false; break end
            end
            if #possible > 0 and complete then
                for _, constructor in ipairs(possible) do
                    local argument_types = constructor_arguments(constructor, types[1])
                    local arguments = {}
                    for i = 1, #argument_types do arguments[i] = false end
                    if useful(specialize(matrix, constructor, #arguments), sequence(arguments, query, 2), sequence(argument_types, types, 2)) then
                        result = true
                        break
                    end
                end
            else
                local default = {}
                for _, row in ipairs(matrix) do if not row[1] then default[#default + 1] = sequence({}, row, 2) end end
                result = useful(default, sequence({}, query, 2), sequence({}, types, 2))
            end
        end
        memo[memo_key] = result
        return result
    end
    return useful
end
local function expression_nodes(expression, result)
    result[#result + 1] = expression
    if expression.kind == "let" then
        for _, binding in ipairs(expression.value.bindings) do expression_nodes(binding.expression, result) end
    end
    for _, child in ipairs(expression.children) do expression_nodes(child, result) end
    if expression.kind == "match" then for _, arm in ipairs(expression.value) do expression_nodes(arm[2], result) end end
end
local function classify(expression, targets, references)
    local _, body = leading_parameters(expression)
    local calls = {}
    local visit
    visit = function(node, tail)
        local kind, children = node.kind, node.children
        if kind == "name" then
            if targets[references[node]] then calls[#calls + 1] = false end
        elseif kind == "apply" then
            local arguments, fn = {}, node
            while fn.kind == "apply" do arguments[#arguments + 1], fn = fn.children[2], fn.children[1] end
            if fn.kind == "name" and targets[references[fn]] then calls[#calls + 1] = tail
            else visit(fn, false) end
            for i = #arguments, 1, -1 do visit(arguments[i], false) end
        elseif kind == "if" then
            visit(children[1], false)
            visit(children[2], tail)
            visit(children[3], tail)
        elseif kind == "match" then
            visit(children[1], false)
            for _, arm in ipairs(node.value) do visit(arm[2], tail) end
        elseif kind == "let" then
            for _, binding in ipairs(node.value.bindings) do visit(binding.expression, false) end
            visit(children[1], tail)
        elseif kind == "binary" and (node.value.spelling == "&&" or node.value.spelling == "||") then
            visit(children[1], false)
            visit(children[2], tail)
        else for _, child in ipairs(children) do visit(child, false) end end
    end
    visit(body, true)
    if #calls == 0 then return "" end
    for _, tail in ipairs(calls) do if not tail then return "recursive" end end
    return "tail recursive"
end
local S = {}
S.__index = S
function S.new() return setmetatable({ symbols = {}, references = {}, groups = {}, warnings = {} }, S) end
function S:symbol(name, position, top_level)
    local symbol = { name = name, position = position, top_level = top_level, used = false }
    self.symbols[#self.symbols + 1] = symbol
    return symbol
end
function S:bind_pattern(pattern, environment)
    if pattern.kind == "name" then environment[pattern.value] = self:symbol(pattern.value, pattern.position) end
    for _, child in ipairs(pattern.children) do self:bind_pattern(child, environment) end
end
function S:group(group, environment, top_level)
    local inner, targets = copy(environment), {}
    for _, binding in ipairs(group.bindings) do
        local symbol = self:symbol(binding.name, binding.position, top_level)
        inner[binding.name], targets[symbol] = symbol, true
    end
    self.groups[#self.groups + 1] = { group, targets }
    local right_environment = group.rec_position and inner or environment
    for _, binding in ipairs(group.bindings) do self:expression(binding.expression, right_environment) end
    return inner
end
function S:match_warnings(expression)
    local useful, matrix = coverage_checker(), {}
    local matched_type = { coverage_type(expression.children[1].inferred) }
    for i, arm in ipairs(expression.value) do
        local query = { coverage_pattern(arm[1]) }
        if i > 1 and not useful(matrix, query, matched_type) then
            self.warnings[#self.warnings + 1] = { arm[1].position, 2, "this match case is unused" }
        end
        matrix[#matrix + 1] = query
    end
    if useful(matrix, { false }, matched_type) then
        self.warnings[#self.warnings + 1] = { expression.position, 1, "this match is not exhaustive" }
    end
end
function S:expression(expression, environment)
    local kind = expression.kind
    if kind == "name" then
        local symbol = environment[expression.value]
        self.references[expression] = symbol or false
        if symbol then symbol.used = true end
    elseif kind == "fun" then
        local inner, parameter = copy(environment), expression.value
        if parameter.spelling ~= "_" then inner[parameter.spelling] = self:symbol(parameter.spelling, parameter.position) end
        self:expression(expression.children[1], inner)
    elseif kind == "let" then
        local inner = self:group(expression.value, environment)
        self:expression(expression.children[1], inner)
    elseif kind == "match" then
        self:expression(expression.children[1], environment)
        self:match_warnings(expression)
        for _, arm in ipairs(expression.value) do
            local inner = copy(environment)
            self:bind_pattern(arm[1], inner)
            self:expression(arm[2], inner)
        end
    else for _, child in ipairs(expression.children) do self:expression(child, environment) end end
end
function S:item(item, environment_names)
    local environment = {}
    for name in pairs(environment_names) do environment[name] = false end
    if item.kind == "declaration" then self:group(item.value, environment, true)
    else self:expression(item.value, environment) end
    for _, entry in ipairs(self.groups) do
        local group, targets = entry[1], entry[2]
        if group.rec_position then
            local referenced = false
            for _, binding in ipairs(group.bindings) do
                local nodes = {}
                expression_nodes(binding.expression, nodes)
                for _, node in ipairs(nodes) do if targets[self.references[node]] then referenced = true; break end end
                binding.classification = classify(binding.expression, targets, self.references)
            end
            if not referenced then self.warnings[#self.warnings + 1] = { group.rec_position, 3, "unused rec flag" } end
        end
    end
    for _, symbol in ipairs(self.symbols) do
        if not symbol.top_level and not symbol.used and symbol.name:sub(1, 1) ~= "_" then
            self.warnings[#self.warnings + 1] = { symbol.position, 4, "unused variable '" .. symbol.name .. "'" }
        end
    end
    table.sort(self.warnings, function(a, b)
        if a[1][2] == b[1][2] and a[1][3] == b[1][3] then return a[2] < b[2] end
        return position_less(a[1], b[1])
    end)
    return self.warnings
end
local filenames = { "prelude.ml", "program.ml" }
local sources, source_lines, statistics = {}, {}, {}
for _, filename in ipairs(filenames) do
    local input = assert(io.open("input/" .. filename, "r"))
    sources[filename] = input:read("*a")
    input:close()
    source_lines[filename] = {}
    for line in sources[filename]:gmatch("(.-)\n") do source_lines[filename][#source_lines[filename] + 1] = line end
    statistics[filename] = { items = 0, bindings = 0, syntax = 0, type = 0, runtime = 0, warnings = 0, calls = 0 }
end
local types, values, errors, formatted = {}, {}, {}, {}
local type_environment, value_environment = builtins()
local current_file
local function report(kind, position, message)
    local counter = kind == "warning" and "warnings" or kind:match("^(%S+)")
    statistics[current_file][counter] = statistics[current_file][counter] + 1
    local filename, line, column = position[1], position[2], position[3]
    errors[#errors + 1] = string.format("%s:%d:%d: %s: %s", filename, line, column, kind, message)
    if line <= #source_lines[filename] then
        errors[#errors + 1] = "    " .. source_lines[filename][line]
        errors[#errors + 1] = string.rep(" ", column + 3) .. "^"
    end
end
local function unused_signature(signature)
    report("warning", signature[1].position, "signature for '" .. signature[1].spelling .. "' is never used")
end
local function classification_suffix(binding)
    return binding.classification ~= "" and " (" .. binding.classification .. ")" or ""
end
local function write_types(item, inferred, local_bindings)
    if item.kind == "declaration" then
        for _, binding in ipairs(item.value.bindings) do
            types[#types + 1] = binding.name .. " : " .. type_printer()(binding.scheme.value) .. classification_suffix(binding)
        end
    else types[#types + 1] = "- : " .. type_printer()(inferred) end
    table.sort(local_bindings, function(a, b) return position_less(a.position, b.position) end)
    for _, binding in ipairs(local_bindings) do
        types[#types + 1] = string.format("  %s (%d:%d) : %s%s", binding.name, binding.position[2], binding.position[3],
            type_printer(binding.scheme.quantified)(binding.scheme.value), classification_suffix(binding))
    end
end
local function process_item(item, pending, evaluator, counts)
    formatted[#formatted + 1] = format_item(item)
    if item.kind == "signature" then
        local name = item.value[1].spelling
        if pending[name] then unused_signature(pending[name]) end
        pending[name] = item.value
        return
    end
    local signatures, inferencer = {}, Inferencer.new()
    if item.kind == "declaration" then
        for i, binding in ipairs(item.value.bindings) do
            signatures[i], pending[binding.name] = pending[binding.name] or false, nil
        end
    end
    local inferred
    local ok, err = pcall(function()
        if item.kind == "declaration" then
            inferencer:group(item.value, type_environment)
            check_signatures(item.value, signatures)
        else inferred = inferencer:expression(item.value, type_environment) end
    end)
    if not ok then
        if type(err) ~= "table" or err.category ~= "type" then error(err) end
        report("type error", err.position, type_error_message(err))
        return
    end
    local warnings = S.new():item(item, type_environment)
    write_types(item, inferred, inferencer.local_bindings)
    for _, warning in ipairs(warnings) do report("warning", warning[1], warning[3]) end
    local environment, evaluated
    ok, err = pcall(function()
        if item.kind == "declaration" then
            environment = evaluator:group(item.value, value_environment)
            evaluated = {}
            for i, binding in ipairs(item.value.bindings) do evaluated[i] = environment[binding.name] end
        else evaluated = evaluator:expression(item.value, value_environment) end
    end)
    if not ok then
        if type(err) ~= "table" or err.category ~= "runtime" then error(err) end
        report("runtime error", err.position, err.message)
        return
    end
    if item.kind == "declaration" then
        local new_types = copy(type_environment)
        for i, binding in ipairs(item.value.bindings) do
            values[#values + 1] = binding.name .. " = " .. print_value(evaluated[i])
            new_types[binding.name] = binding.scheme
        end
        type_environment, value_environment = new_types, environment
        counts.bindings = counts.bindings + #item.value.bindings
    else values[#values + 1] = "- = " .. print_value(evaluated) end
end
local function syntax_message(token)
    if token.kind == "invalid" then return token.value
    elseif token.kind == "EOF" then return "unexpected end of file" end
    return "unexpected '" .. token.spelling .. "'"
end
for _, filename in ipairs(filenames) do
    current_file = filename
    local counts, pending, evaluator = statistics[filename], {}, Evaluator.new()
    types[#types + 1], values[#values + 1], formatted[#formatted + 1] = "== " .. filename .. " ==",
        "== " .. filename .. " ==", "(* " .. filename .. " *)"
    local parser = Parser.new(lexer.tokenize(sources[filename], filename))
    while parser:peek().kind ~= "EOF" do
        counts.items = counts.items + 1
        local ok, item = pcall(parser.item, parser)
        if not ok then
            if type(item) ~= "table" or item.category ~= "syntax" then error(item) end
            report("syntax error", item.token.position, syntax_message(item.token))
            parser:recover()
        else process_item(item, pending, evaluator, counts) end
    end
    local remaining = {}
    for _, signature in pairs(pending) do remaining[#remaining + 1] = signature end
    table.sort(remaining, function(a, b) return position_less(a[1].position, b[1].position) end)
    for _, signature in ipairs(remaining) do unused_signature(signature) end
    counts.calls = evaluator.calls
end
errors[#errors + 1] = "== summary =="
for _, filename in ipairs(filenames) do
    local counts = statistics[filename]
    errors[#errors + 1] = string.format("%s: items=%d bindings=%d syntax=%d type=%d runtime=%d warnings=%d calls=%d", filename,
        counts.items, counts.bindings, counts.syntax, counts.type, counts.runtime, counts.warnings, counts.calls)
end
for _, entry in ipairs({ { "types.txt", types }, { "values.txt", values }, { "errors.txt", errors }, { "formatted.ml", formatted } }) do
    local output = assert(io.open("output/" .. entry[1], "w"))
    output:write(table.concat(entry[2], "\n"), "\n")
    output:close()
end
