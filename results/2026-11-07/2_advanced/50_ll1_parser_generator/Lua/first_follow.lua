local grammar = require("grammar_parser")
local M = {}
function M.terminal_order(values)
    local result = {}
    for value in pairs(values) do
        result[#result + 1] = value
    end
    table.sort(result, function(a, b)
        if a == "$" then
            return false
        elseif b == "$" then
            return true
        end
        return a < b
    end)
    return result
end
function M.terminals(source)
    local result = {}
    for _, lhs in ipairs(source.order) do
        for _, rhs in ipairs(source.rules[lhs]) do
            for _, symbol in ipairs(rhs) do
                if not grammar.is_nonterminal(symbol) then
                    result[symbol] = true
                end
            end
        end
    end
    return M.terminal_order(result)
end
local function merge(target, values)
    local changed = false
    for value in pairs(values) do
        if not target[value] then
            target[value], changed = true, true
        end
    end
    return changed
end
function M.sequence(symbols, nullable, first)
    local result = {}
    for _, symbol in ipairs(symbols) do
        if not grammar.is_nonterminal(symbol) then
            result[symbol] = true
            return result, false
        end
        merge(result, first[symbol])
        if not nullable[symbol] then
            return result, false
        end
    end
    return result, true
end
function M.analyze(source)
    local result = {nullable = {}, first = {}, follow = {}, passes = {}, terminals = M.terminals(source)}
    for _, lhs in ipairs(source.order) do
        result.nullable[lhs], result.first[lhs], result.follow[lhs] = false, {}, {}
    end
    local changed, passes = true, 0
    while changed do
        changed, passes = false, passes + 1
        for _, lhs in ipairs(source.order) do
            if not result.nullable[lhs] then
                for _, rhs in ipairs(source.rules[lhs]) do
                    local empty = true
                    for _, symbol in ipairs(rhs) do
                        if not grammar.is_nonterminal(symbol) or not result.nullable[symbol] then
                            empty = false
                            break
                        end
                    end
                    if empty then
                        result.nullable[lhs], changed = true, true
                        break
                    end
                end
            end
        end
    end
    result.passes.nullable = passes
    changed, passes = true, 0
    while changed do
        changed, passes = false, passes + 1
        for _, lhs in ipairs(source.order) do
            for _, rhs in ipairs(source.rules[lhs]) do
                local values = M.sequence(rhs, result.nullable, result.first)
                if merge(result.first[lhs], values) then
                    changed = true
                end
            end
        end
    end
    result.passes.first = passes
    result.follow[source.start]["$"] = true
    changed, passes = true, 0
    while changed do
        changed, passes = false, passes + 1
        for _, lhs in ipairs(source.order) do
            for _, rhs in ipairs(source.rules[lhs]) do
                for index, symbol in ipairs(rhs) do
                    if grammar.is_nonterminal(symbol) then
                        local suffix = {table.unpack(rhs, index + 1)}
                        local values, empty = M.sequence(suffix, result.nullable, result.first)
                        if merge(result.follow[symbol], values) then
                            changed = true
                        end
                        if empty and merge(result.follow[symbol], result.follow[lhs]) then
                            changed = true
                        end
                    end
                end
            end
        end
    end
    result.passes.follow = passes
    return result
end
return M
