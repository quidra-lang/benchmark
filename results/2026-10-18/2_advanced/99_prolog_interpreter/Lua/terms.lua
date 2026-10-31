local T = {}
function T.variable() return { kind = "variable" } end
function T.compound(name, ...) return { kind = "compound", name = name, args = { ... } } end
function T.application(name, args) return { kind = "compound", name = name, args = args } end
function T.is_variable(term) return type(term) == "table" and term.kind == "variable" end
function T.is_compound(term) return type(term) == "table" and term.kind == "compound" end
function T.dereference(term)
    while T.is_variable(term) and term.binding ~= nil do term = term.binding end
    return term
end
function T.signature(name, arity) return name .. "\0" .. arity end
function T.indicator(term)
    term = T.dereference(term)
    if T.is_compound(term) then return T.signature(term.name, #term.args) end
    return T.signature(term, 0)
end
function T.decode(key)
    local position = assert(key:find("\0", 1, true))
    return key:sub(1, position - 1), tonumber(key:sub(position + 1))
end
function T.indicator_term(key)
    local name, arity = T.decode(key)
    return T.compound("/", name, arity)
end
function T.make_list(elements, tail)
    tail = tail or "[]"
    for i = #elements, 1, -1 do tail = T.compound(".", elements[i], tail) end
    return tail
end
function T.list_parts(term)
    local elements = {}
    term = T.dereference(term)
    while T.is_compound(term) and term.name == "." and #term.args == 2 do
        elements[#elements + 1] = term.args[1]
        term = T.dereference(term.args[2])
    end
    return elements, term
end
function T.copy_terms(...)
    local variables = {}
    local function copy(term)
        term = T.dereference(term)
        if T.is_variable(term) then
            if not variables[term] then variables[term] = T.variable() end
            return variables[term]
        elseif T.is_compound(term) then
            local args = {}
            for i, argument in ipairs(term.args) do args[i] = copy(argument) end
            return T.application(term.name, args)
        end
        return term
    end
    local result = {}
    for i = 1, select("#", ...) do result[i] = copy(select(i, ...)) end
    return table.unpack(result, 1, select("#", ...))
end
function T.copy(term) return T.copy_terms(term) end
function T.variables_in(...)
    local stack, result = {}, {}
    for i = select("#", ...), 1, -1 do stack[#stack + 1] = select(i, ...) end
    while #stack > 0 do
        local term = T.dereference(table.remove(stack))
        if T.is_variable(term) then result[#result + 1] = term
        elseif T.is_compound(term) then for i = #term.args, 1, -1 do stack[#stack + 1] = term.args[i] end end
    end
    return result
end
function T.same_kind(a, b)
    a, b = T.dereference(a), T.dereference(b)
    if T.is_variable(a) or T.is_variable(b) then return true end
    if T.is_compound(a) and T.is_compound(b) then return a.name == b.name and #a.args == #b.args end
    return type(a) == type(b) and a == b
end
function T.type_error(kind, term) return T.compound("type_error", kind, term) end
function T.domain_error(kind, term) return T.compound("domain_error", kind, term) end
function T.fault(term) error({ category = "fault", term = term }, 0) end
return T
