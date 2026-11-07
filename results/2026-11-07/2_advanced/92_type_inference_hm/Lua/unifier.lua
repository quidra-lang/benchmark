local U = {}
function U.variable() return { kind = "variable" } end
function U.type(kind, ...) return { kind = kind, children = { ... } } end
function U.scheme(value, quantified) return { value = value, quantified = quantified or {} } end
U.INT, U.BOOL, U.STRING = U.type("int"), U.type("bool"), U.type("string")
function U.resolve(value)
    local path = {}
    while value.kind == "variable" and value.binding do
        path[#path + 1], value = value, value.binding
    end
    for _, variable in ipairs(path) do variable.binding = value end
    return value
end
function U.occurs(variable, value)
    value = U.resolve(value)
    if value.kind == "variable" then return variable == value end
    for _, child in ipairs(value.children) do if U.occurs(variable, child) then return true end end
    return false
end
function U.unify(expected, found, nested)
    expected, found = U.resolve(expected), U.resolve(found)
    if expected == found then return end
    if expected.kind == "variable" then
        if U.occurs(expected, found) then
            error({ category = "unification", expected = expected, found = found, infinite = true, nested = nested }, 0)
        end
        expected.binding = found
    elseif found.kind == "variable" then
        if U.occurs(found, expected) then
            error({ category = "unification", expected = expected, found = found, infinite = true, nested = nested }, 0)
        end
        found.binding = expected
    elseif expected.kind ~= found.kind then
        error({ category = "unification", expected = expected, found = found, nested = nested }, 0)
    else
        for i, first in ipairs(expected.children) do U.unify(first, found.children[i], true) end
    end
end
function U.free(value, result)
    result, value = result or {}, U.resolve(value)
    if value.kind == "variable" then result[value] = true
    else for _, child in ipairs(value.children) do U.free(child, result) end end
    return result
end
function U.generalize(value, environment)
    local blocked, quantified = {}, U.free(value)
    for _, scheme in pairs(environment) do
        for variable in pairs(U.free(scheme.value)) do
            if not scheme.quantified[variable] then blocked[variable] = true end
        end
    end
    for variable in pairs(blocked) do quantified[variable] = nil end
    return U.scheme(value, quantified)
end
function U.instantiate(scheme)
    local replacements = {}
    local function clone(value)
        value = U.resolve(value)
        if value.kind == "variable" then
            if not scheme.quantified[value] then return value end
            if not replacements[value] then replacements[value] = U.variable() end
            return replacements[value]
        end
        local result = U.type(value.kind)
        for i, child in ipairs(value.children) do result.children[i] = clone(child) end
        return result
    end
    return clone(scheme.value)
end
return U
