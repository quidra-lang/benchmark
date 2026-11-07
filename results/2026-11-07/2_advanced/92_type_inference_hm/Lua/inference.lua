local U = require("unifier")
local I = {}
I.__index = I
local function copy(environment)
    local result = {}
    for name, value in pairs(environment) do result[name] = value end
    return result
end
function I.error(kind, position, details)
    error({ category = "type", kind = kind, position = position, details = details or {} }, 0)
end
function I.new() return setmetatable({ local_bindings = {} }, I) end
function I:check(expected, found, position)
    local ok, failure = pcall(U.unify, expected, found)
    if not ok then
        if type(failure) ~= "table" or failure.category ~= "unification" then error(failure) end
        I.error("check", position, { expected = expected, found = found, failure = failure })
    end
end
local function operator_types(operator)
    if operator == "+" or operator == "-" or operator == "*" or operator == "/" or operator == "mod" then
        return U.INT, U.INT, U.INT
    elseif operator == "^" then return U.STRING, U.STRING, U.STRING
    elseif operator == "&&" or operator == "||" then return U.BOOL, U.BOOL, U.BOOL end
    local variable = U.variable()
    if operator == "::" then
        local sequence = U.type("list", variable)
        return variable, sequence, sequence
    end
    return variable, variable, U.BOOL
end
function I:expression(expression, environment)
    local kind, children, result = expression.kind, expression.children
    if kind == "integer" then result = U.INT
    elseif kind == "boolean" then result = U.BOOL
    elseif kind == "string" then result = U.STRING
    elseif kind == "name" then
        if not environment[expression.value] then
            local candidates = {}
            for name in pairs(environment) do candidates[#candidates + 1] = name end
            I.error("unbound", expression.position, { name = expression.value, candidates = candidates })
        end
        result = U.instantiate(environment[expression.value])
    elseif kind == "fun" then
        local argument, inner = U.variable(), copy(environment)
        if expression.value.spelling ~= "_" then inner[expression.value.spelling] = U.scheme(argument) end
        result = U.type("function", argument, self:expression(children[1], inner))
    elseif kind == "apply" then
        local fn = U.resolve(self:expression(children[1], environment))
        local argument
        if fn.kind == "variable" then
            argument, result = U.variable(), U.variable()
            fn.binding = U.type("function", argument, result)
        elseif fn.kind == "function" then argument, result = fn.children[1], fn.children[2]
        else I.error("not_function", children[1].position, { found = fn }) end
        local found = self:expression(children[2], environment)
        self:check(argument, found, children[2].position)
    elseif kind == "binary" then
        local first, second
        first, second, result = operator_types(expression.value.spelling)
        self:check(first, self:expression(children[1], environment), children[1].position)
        self:check(second, self:expression(children[2], environment), children[2].position)
    elseif kind == "negate" then
        self:check(U.INT, self:expression(children[1], environment), children[1].position)
        result = U.INT
    elseif kind == "if" then
        self:check(U.BOOL, self:expression(children[1], environment), children[1].position)
        result = self:expression(children[2], environment)
        local found = self:expression(children[3], environment)
        self:check(result, found, children[3].position)
    elseif kind == "pair" then
        local first = self:expression(children[1], environment)
        local second = self:expression(children[2], environment)
        result = U.type("pair", first, second)
    elseif kind == "list" then
        local element = U.variable()
        for _, child in ipairs(children) do self:check(element, self:expression(child, environment), child.position) end
        result = U.type("list", element)
    elseif kind == "match" then
        local matched = self:expression(children[1], environment)
        result = U.variable()
        for _, arm in ipairs(expression.value) do
            local bindings = {}
            local pattern_type = self:pattern(arm[1], bindings)
            self:check(matched, pattern_type, arm[1].position)
            local inner = copy(environment)
            for name, value in pairs(bindings) do inner[name] = U.scheme(value) end
            self:check(result, self:expression(arm[2], inner), arm[2].position)
        end
    elseif kind == "let" then
        local inner = self:group(expression.value, environment, true)
        result = self:expression(children[1], inner)
    end
    expression.inferred = result
    return result
end
function I:pattern(pattern, bindings)
    local kind, children = pattern.kind, pattern.children
    if kind == "wildcard" then return U.variable()
    elseif kind == "name" then
        if bindings[pattern.value] then I.error("duplicate_pattern", pattern.position, { name = pattern.value }) end
        local result = U.variable()
        bindings[pattern.value] = result
        return result
    elseif kind == "integer" then return U.INT
    elseif kind == "boolean" then return U.BOOL
    elseif kind == "string" then return U.STRING
    elseif kind == "pair" then
        local first = self:pattern(children[1], bindings)
        local second = self:pattern(children[2], bindings)
        return U.type("pair", first, second)
    end
    local element = U.variable()
    local sequence = U.type("list", element)
    if kind == "cons" then
        self:check(element, self:pattern(children[1], bindings), children[1].position)
        self:check(sequence, self:pattern(children[2], bindings), children[2].position)
    else
        for _, child in ipairs(children) do self:check(element, self:pattern(child, bindings), child.position) end
    end
    return sequence
end
function I:group(group, environment, is_local)
    local names, inferred = {}, {}
    for _, binding in ipairs(group.bindings) do
        if names[binding.name] then I.error("duplicate_let", binding.position, { name = binding.name }) end
        names[binding.name] = true
        if group.rec_position and binding.expression.kind ~= "fun" then
            I.error("recursive_function", binding.position, { name = binding.name })
        end
    end
    if not group.rec_position then
        for i, binding in ipairs(group.bindings) do inferred[i] = self:expression(binding.expression, environment) end
    else
        local recursive = copy(environment)
        for i, binding in ipairs(group.bindings) do
            inferred[i] = U.variable()
            recursive[binding.name] = U.scheme(inferred[i])
        end
        for i, binding in ipairs(group.bindings) do
            local found = self:expression(binding.expression, recursive)
            self:check(inferred[i], found, binding.position)
        end
    end
    local result = copy(environment)
    for i, binding in ipairs(group.bindings) do
        binding.scheme = U.generalize(inferred[i], environment)
        result[binding.name] = binding.scheme
        if is_local then self.local_bindings[#self.local_bindings + 1] = binding end
    end
    return result
end
return I
