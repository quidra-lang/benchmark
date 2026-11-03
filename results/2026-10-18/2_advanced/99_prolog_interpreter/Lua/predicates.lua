local T = require("terms")
local U = require("unify")
local P = { deterministic = {} }
for _, group in ipairs({
    { 0, "true", "fail", "false", "nl" },
    { 1, "var", "nonvar", "atom", "number", "integer", "atomic", "compound", "callable", "is_list", "write", "writeq" },
    { 2, "=", "\\=", "==", "\\==", "is", "=:=", "=\\=", "<", ">", "=<", ">=", "=..", "copy_term", "atom_length", "atom_chars" },
    { 3, "functor", "arg" }
}) do for i = 2, #group do P.deterministic[T.signature(group[i], group[1])] = true end end
local supported = {}
for _, pair in ipairs({ { "+", 2 }, { "-", 2 }, { "*", 2 }, { "//", 2 }, { "mod", 2 }, { "rem", 2 }, { "-", 1 }, { "abs", 1 }, { "min", 2 }, { "max", 2 } }) do supported[T.signature(pair[1], pair[2])] = true end
local function quotient(a, b)
    local value = math.abs(a) // math.abs(b)
    return (a < 0) ~= (b < 0) and -value or value
end
function P.evaluate(term)
    term = T.dereference(term)
    if T.is_variable(term) then T.fault("instantiation_error") end
    if type(term) == "number" then return term end
    if type(term) == "string" then T.fault(T.type_error("evaluable", T.indicator_term(T.indicator(term)))) end
    if not supported[T.indicator(term)] then T.fault(T.type_error("evaluable", T.indicator_term(T.indicator(term)))) end
    local values = {}
    for i, argument in ipairs(term.args) do values[i] = P.evaluate(argument) end
    local a, b, name, result = values[1], values[2], term.name
    if #values == 1 then result = name == "-" and -a or math.abs(a)
    else
        if (name == "//" or name == "mod" or name == "rem") and b == 0 then T.fault(T.compound("evaluation_error", "zero_divisor")) end
        if name == "+" then result = a + b elseif name == "-" then result = a - b elseif name == "*" then result = a * b
        elseif name == "//" then result = quotient(a, b) elseif name == "mod" then result = a % b elseif name == "rem" then result = a - b * quotient(a, b)
        elseif name == "min" then result = math.min(a, b) else result = math.max(a, b) end
    end
    if result < -2147483648 or result > 2147483647 then T.fault(T.compound("evaluation_error", "int_overflow")) end
    return result
end
function P.require_integer(term)
    term = T.dereference(term)
    if T.is_variable(term) then T.fault("instantiation_error") end
    if type(term) ~= "number" then T.fault(T.type_error("integer", term)) end
    return term
end
function P.require_atom(term)
    term = T.dereference(term)
    if T.is_variable(term) then T.fault("instantiation_error") end
    if type(term) ~= "string" then T.fault(T.type_error("atom", term)) end
    return term
end
function P.require_list(term)
    local elements, tail = T.list_parts(term)
    if T.is_variable(tail) then T.fault("instantiation_error") end
    if tail ~= "[]" then T.fault(T.type_error("list", term)) end
    return elements
end
local function fresh(count)
    local result = {}
    for i = 1, count do result[i] = T.variable() end
    return result
end
function P.execute(goal, trail, output)
    local name = T.is_compound(goal) and goal.name or goal
    local args = {}
    if T.is_compound(goal) then for i, argument in ipairs(goal.args) do args[i] = T.dereference(argument) end end
    local a, b, c = args[1], args[2], args[3]
    if name == "true" then return true elseif name == "fail" or name == "false" then return false
    elseif name == "=" then return trail:unify(a, b)
    elseif name == "\\=" then
        local mark = trail:mark()
        local result = trail:unify(a, b)
        trail:undo(mark)
        return not result
    elseif name == "==" then return U.identical(a, b) elseif name == "\\==" then return not U.identical(a, b)
    elseif name == "var" then return T.is_variable(a) elseif name == "nonvar" then return not T.is_variable(a)
    elseif name == "atom" then return type(a) == "string" elseif name == "number" or name == "integer" then return type(a) == "number"
    elseif name == "atomic" then return type(a) == "string" or type(a) == "number" elseif name == "compound" then return T.is_compound(a)
    elseif name == "callable" then return type(a) == "string" or T.is_compound(a)
    elseif name == "is_list" then local _, tail = T.list_parts(a); return tail == "[]"
    elseif name == "is" then return trail:unify(a, P.evaluate(b))
    elseif name == "=:=" or name == "=\\=" or name == "<" or name == ">" or name == "=<" or name == ">=" then
        local left = P.evaluate(a)
        local right = P.evaluate(b)
        if name == "=:=" then return left == right elseif name == "=\\=" then return left ~= right
        elseif name == "<" then return left < right elseif name == ">" then return left > right elseif name == "=<" then return left <= right else return left >= right end
    elseif name == "functor" then
        if not T.is_variable(a) then
            if T.is_compound(a) then return trail:unify(b, a.name) and trail:unify(c, #a.args) end
            return trail:unify(b, a) and trail:unify(c, 0)
        end
        if T.is_variable(b) or T.is_variable(c) then T.fault("instantiation_error") end
        if T.is_compound(b) then T.fault(T.type_error("atomic", b)) end
        if type(c) ~= "number" then T.fault(T.type_error("integer", c)) end
        if c < 0 then T.fault(T.domain_error("not_less_than_zero", c)) end
        if c > 255 then T.fault(T.compound("representation_error", "max_arity")) end
        if c == 0 then return trail:unify(a, b) end
        if type(b) == "number" then T.fault(T.type_error("atom", b)) end
        return trail:unify(a, T.application(b, fresh(c)))
    elseif name == "arg" then
        if T.is_variable(a) or T.is_variable(b) then T.fault("instantiation_error") end
        if type(a) ~= "number" then T.fault(T.type_error("integer", a)) end
        if not T.is_compound(b) then T.fault(T.type_error("compound", b)) end
        return a >= 1 and a <= #b.args and trail:unify(b.args[a], c)
    elseif name == "=.." then
        if T.is_compound(a) then
            local elements = { a.name }
            for _, argument in ipairs(a.args) do elements[#elements + 1] = argument end
            return trail:unify(T.make_list(elements), b)
        elseif not T.is_variable(a) then return trail:unify(T.make_list({ a }), b) end
        local elements = P.require_list(b)
        if #elements == 0 then T.fault(T.domain_error("non_empty_list", "[]")) end
        local head = T.dereference(elements[1])
        if T.is_variable(head) then T.fault("instantiation_error") end
        if #elements == 1 then
            if T.is_compound(head) then T.fault(T.type_error("atomic", head)) end
            return trail:unify(a, head)
        end
        if type(head) ~= "string" then T.fault(T.type_error("atom", head)) end
        if #elements > 256 then T.fault(T.compound("representation_error", "max_arity")) end
        local arguments = {}
        for i = 2, #elements do arguments[#arguments + 1] = elements[i] end
        return trail:unify(a, T.application(head, arguments))
    elseif name == "copy_term" then return trail:unify(T.copy(a), b)
    elseif name == "atom_length" then
        local atom = P.require_atom(a)
        if not T.is_variable(b) and type(b) ~= "number" then T.fault(T.type_error("integer", b)) end
        return trail:unify(#atom, b)
    elseif name == "atom_chars" then
        if not T.is_variable(a) then
            local atom, elements = P.require_atom(a), {}
            for i = 1, #atom do elements[i] = atom:sub(i, i) end
            return trail:unify(b, T.make_list(elements))
        end
        local elements, characters = P.require_list(b), {}
        for _, element in ipairs(elements) do
            local character = T.dereference(element)
            if T.is_variable(character) then T.fault("instantiation_error") end
            if type(character) ~= "string" or #character ~= 1 then T.fault(T.type_error("character", character)) end
            characters[#characters + 1] = character
        end
        return trail:unify(a, table.concat(characters))
    elseif name == "write" or name == "writeq" then output(a, name == "writeq"); return true
    elseif name == "nl" then output(nil, false); return true end
end
return P
