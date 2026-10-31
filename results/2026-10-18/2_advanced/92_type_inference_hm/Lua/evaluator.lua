local E = {}
E.__index = E
local function copy(environment)
    local result = {}
    for name, value in pairs(environment) do result[name] = value end
    return result
end
function E.failure(position, message) error({ category = "runtime", position = position, message = message }, 0) end
function E.builtin(behavior) return { kind = "builtin", behavior = behavior } end
function E.new() return setmetatable({ calls = 0 }, E) end
local function checked(value, position)
    if value < -2147483648 or value > 2147483647 then E.failure(position, "integer overflow") end
    return value
end
local function compare(first, second, position)
    if type(first) == "table" then
        if first.kind == "closure" or first.kind == "builtin" then E.failure(position, "functional value compared") end
        for i = 1, math.min(#first.items, #second.items) do
            local order = compare(first.items[i], second.items[i], position)
            if order ~= 0 then return order end
        end
        return #first.items < #second.items and -1 or (#first.items > #second.items and 1 or 0)
    end
    if first == second then return 0 end
    if type(first) == "boolean" then return first and 1 or -1 end
    return first < second and -1 or 1
end
local function binary(operator, first, second, position)
    if operator == "+" then return checked(first + second, position)
    elseif operator == "-" then return checked(first - second, position)
    elseif operator == "*" then return checked(first * second, position)
    elseif operator == "/" or operator == "mod" then
        if second == 0 then E.failure(position, "division by zero") end
        local quotient = math.abs(first) // math.abs(second)
        if (first < 0) ~= (second < 0) then quotient = -quotient end
        if operator == "/" then return checked(quotient, position) end
        return first - second * quotient
    elseif operator == "^" then return first .. second
    elseif operator == "::" then
        local items = { first }
        for _, value in ipairs(second.items) do items[#items + 1] = value end
        return { kind = "list", items = items }
    end
    local order = compare(first, second, position)
    if operator == "=" then return order == 0
    elseif operator == "<>" then return order ~= 0
    elseif operator == "<" then return order < 0
    elseif operator == ">" then return order > 0
    elseif operator == "<=" then return order <= 0 end
    return order >= 0
end
local function match(pattern, value, bindings)
    local kind, children = pattern.kind, pattern.children
    if kind == "wildcard" then return true
    elseif kind == "name" then bindings[pattern.value] = value; return true
    elseif kind == "integer" or kind == "boolean" or kind == "string" then return pattern.value == value
    elseif kind == "cons" then
        if #value.items == 0 then return false end
        local tail = {}
        for i = 2, #value.items do tail[#tail + 1] = value.items[i] end
        return match(children[1], value.items[1], bindings) and match(children[2], { kind = "list", items = tail }, bindings)
    elseif kind == "list" and #value.items ~= #children then return false end
    for i, child in ipairs(children) do if not match(child, value.items[i], bindings) then return false end end
    return true
end
function E:expression(expression, environment)
    local kind, children = expression.kind, expression.children
    if kind == "integer" or kind == "boolean" or kind == "string" then return expression.value
    elseif kind == "name" then return environment[expression.value]
    elseif kind == "fun" then
        return { kind = "closure", parameter = expression.value.spelling, body = children[1], environment = copy(environment) }
    elseif kind == "apply" then
        local fn = self:expression(children[1], environment)
        local argument = self:expression(children[2], environment)
        self.calls = self.calls + 1
        if fn.kind == "builtin" then return fn.behavior(argument, expression.position) end
        local inner = copy(fn.environment)
        if fn.parameter ~= "_" then inner[fn.parameter] = argument end
        return self:expression(fn.body, inner)
    elseif kind == "binary" then
        local first = self:expression(children[1], environment)
        local operator = expression.value.spelling
        if operator == "&&" then
            if not first then return false end
            return self:expression(children[2], environment)
        elseif operator == "||" then
            if first then return true end
            return self:expression(children[2], environment)
        end
        local second = self:expression(children[2], environment)
        return binary(operator, first, second, expression.value.position)
    elseif kind == "negate" then return checked(-self:expression(children[1], environment), expression.value.position)
    elseif kind == "if" then
        local branch = self:expression(children[1], environment) and children[2] or children[3]
        return self:expression(branch, environment)
    elseif kind == "pair" or kind == "list" then
        local items = {}
        for i, child in ipairs(children) do items[i] = self:expression(child, environment) end
        return { kind = kind, items = items }
    elseif kind == "match" then
        local value = self:expression(children[1], environment)
        for _, arm in ipairs(expression.value) do
            local bindings = {}
            if match(arm[1], value, bindings) then
                local inner = copy(environment)
                for name, bound in pairs(bindings) do inner[name] = bound end
                return self:expression(arm[2], inner)
            end
        end
        E.failure(expression.position, "match failure")
    elseif kind == "let" then
        local inner = self:group(expression.value, environment)
        return self:expression(children[1], inner)
    end
end
function E:group(group, environment)
    local result = copy(environment)
    if group.rec_position then
        for _, binding in ipairs(group.bindings) do
            local expression = binding.expression
            result[binding.name] = { kind = "closure", parameter = expression.value.spelling,
                body = expression.children[1], environment = result }
        end
    else
        local values = {}
        for i, binding in ipairs(group.bindings) do values[i] = self:expression(binding.expression, environment) end
        for i, binding in ipairs(group.bindings) do result[binding.name] = values[i] end
    end
    return result
end
return E
