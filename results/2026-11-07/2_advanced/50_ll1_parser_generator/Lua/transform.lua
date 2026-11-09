local grammar = require("grammar_parser")
local M = {}
local function append(target, values)
    for _, value in ipairs(values) do
        target[#target + 1] = value
    end
end
local function fresh(source, name)
    repeat
        name = name:sub(1, -2) .. "'>"
    until not source.rules[name]
    return name
end
local function leading_reachable(source, start, target)
    local queue, visited, cursor = {start}, {[start] = true}, 1
    while cursor <= #queue do
        local lhs = queue[cursor]
        cursor = cursor + 1
        for _, rhs in ipairs(source.rules[lhs]) do
            local symbol = rhs[1]
            if symbol == target then
                return true
            end
            if symbol and grammar.is_nonterminal(symbol) and not visited[symbol] then
                visited[symbol], queue[#queue + 1] = true, symbol
            end
        end
    end
    return false
end
local function unique(values)
    local result = {}
    for _, rhs in ipairs(values) do
        local present = false
        for _, prior in ipairs(result) do
            if grammar.same(rhs, prior) then
                present = true
                break
            end
        end
        if not present then
            result[#result + 1] = rhs
        end
    end
    return result
end
function M.eliminate(source)
    local result, log = grammar.copy(source), {}
    for index, lhs in ipairs(source.order) do
        for earlier = 1, index - 1 do
            local other = source.order[earlier]
            local starts = false
            for _, rhs in ipairs(result.rules[lhs]) do
                if rhs[1] == other then
                    starts = true
                    break
                end
            end
            if starts and leading_reachable(result, other, lhs) then
                local replaced = {}
                for _, rhs in ipairs(result.rules[lhs]) do
                    if rhs[1] == other then
                        for _, alternative in ipairs(result.rules[other]) do
                            local body = {table.unpack(alternative)}
                            append(body, {table.unpack(rhs, 2)})
                            replaced[#replaced + 1] = body
                        end
                    else
                        replaced[#replaced + 1] = rhs
                    end
                end
                result.rules[lhs] = unique(replaced)
                log[#log + 1] = "substitute " .. other .. " into " .. lhs
            end
        end
        local retained, recursive, ordinary = {}, {}, {}
        for _, rhs in ipairs(result.rules[lhs]) do
            if #rhs == 1 and rhs[1] == lhs then
                log[#log + 1] = "remove cycle " .. lhs .. " -> " .. lhs
            else
                retained[#retained + 1] = rhs
            end
        end
        for _, rhs in ipairs(retained) do
            if rhs[1] == lhs then
                recursive[#recursive + 1] = {table.unpack(rhs, 2)}
            else
                ordinary[#ordinary + 1] = rhs
            end
        end
        if #recursive > 0 then
            local name = fresh(result, lhs)
            local alternatives, tails = {}, {}
            for _, rhs in ipairs(ordinary) do
                local body = {table.unpack(rhs)}
                body[#body + 1] = name
                alternatives[#alternatives + 1] = body
            end
            for _, rhs in ipairs(recursive) do
                rhs[#rhs + 1] = name
                tails[#tails + 1] = rhs
            end
            tails[#tails + 1] = {}
            result.rules[lhs], result.rules[name] = alternatives, tails
            for position, symbol in ipairs(result.order) do
                if symbol == lhs then
                    table.insert(result.order, position + 1, name)
                    break
                end
            end
            log[#log + 1] = "eliminate left recursion in " .. lhs .. " with " .. name
        else
            result.rules[lhs] = retained
        end
    end
    return result, log
end
function M.factor(source)
    local result, log, cursor = grammar.copy(source), {}, 1
    while cursor <= #result.order do
        local lhs = result.order[cursor]
        local alternatives, seen, created = {}, {}, {}
        for _, rhs in ipairs(result.rules[lhs]) do
            local first = rhs[1]
            if not first then
                alternatives[#alternatives + 1] = rhs
            elseif not seen[first] then
                seen[first] = true
                local group = {}
                for _, member in ipairs(result.rules[lhs]) do
                    if member[1] == first then
                        group[#group + 1] = member
                    end
                end
                if #group == 1 then
                    alternatives[#alternatives + 1] = rhs
                else
                    local length = #rhs
                    for _, member in ipairs(group) do
                        length = math.min(length, #member)
                        local matching = 0
                        while matching < length and rhs[matching + 1] == member[matching + 1] do
                            matching = matching + 1
                        end
                        length = matching
                    end
                    local name = fresh(result, lhs)
                    local prefix = {table.unpack(rhs, 1, length)}
                    local body = {table.unpack(prefix)}
                    body[#body + 1] = name
                    alternatives[#alternatives + 1] = body
                    result.rules[name] = {}
                    for _, member in ipairs(group) do
                        result.rules[name][#result.rules[name] + 1] = {table.unpack(member, length + 1)}
                    end
                    created[#created + 1] = name
                    log[#log + 1] = "left factor " .. lhs .. " on " .. grammar.alternative(prefix) .. " with " .. name
                end
            end
        end
        result.rules[lhs] = alternatives
        for index, name in ipairs(created) do
            table.insert(result.order, cursor + index, name)
        end
        cursor = cursor + 1
    end
    return result, log
end
return M
