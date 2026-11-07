local grammar = require("grammar_parser")
local first_follow = require("first_follow")
local M = {}
function M.number(source)
    local result = {}
    for _, lhs in ipairs(source.order) do
        for _, rhs in ipairs(source.rules[lhs]) do
            result[#result + 1] = {number = #result + 1, lhs = lhs, rhs = rhs, notation = grammar.production(lhs, rhs)}
        end
    end
    return result
end
function M.build(source, sets)
    local result = {productions = M.number(source), cells = {}, choices = {}, conflicts = {}}
    local terminals = {table.unpack(sets.terminals)}
    terminals[#terminals + 1] = "$"
    for _, lhs in ipairs(source.order) do
        result.cells[lhs], result.choices[lhs] = {}, {}
        for _, token in ipairs(terminals) do
            result.cells[lhs][token] = {}
        end
    end
    for _, production in ipairs(result.productions) do
        local values, empty = first_follow.sequence(production.rhs, sets.nullable, sets.first)
        production.predict, production.reasons = values, {}
        for token in pairs(values) do
            production.reasons[token] = "FIRST"
        end
        if empty then
            for token in pairs(sets.follow[production.lhs]) do
                if not values[token] then
                    values[token], production.reasons[token] = true, "FOLLOW"
                end
            end
        end
        for token in pairs(values) do
            local cell = result.cells[production.lhs][token]
            cell[#cell + 1] = production.number
        end
    end
    for _, lhs in ipairs(source.order) do
        for _, token in ipairs(terminals) do
            local cell = result.cells[lhs][token]
            if #cell > 0 then
                local chosen, first, follow = cell[1], false, false
                for _, number in ipairs(cell) do
                    if result.productions[number].reasons[token] == "FIRST" then
                        if not first then
                            chosen = number
                        end
                        first = true
                    else
                        follow = true
                    end
                end
                result.choices[lhs][token] = chosen
                if #cell > 1 then
                    local kind = first and (follow and "FIRST/FOLLOW" or "FIRST/FIRST") or "FOLLOW/FOLLOW"
                    result.conflicts[#result.conflicts + 1] = {lhs = lhs, token = token, numbers = cell, chosen = chosen, kind = kind}
                end
            end
        end
    end
    return result
end
return M
