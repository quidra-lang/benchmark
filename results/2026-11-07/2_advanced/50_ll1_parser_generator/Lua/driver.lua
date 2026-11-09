local grammar = require("grammar_parser")
local M = {}
function M.node(symbol)
    return {symbol = symbol, mark = nil, children = {}}
end
function M.parse(tokens, positions, source, sets, parse_table)
    local input, locations = {table.unpack(tokens)}, {table.unpack(positions)}
    input[#input + 1], locations[#locations + 1] = "$", #tokens + 1
    local root = M.node(source.start)
    local stack = {{symbol = "$"}, {symbol = source.start, node = root}}
    local result = {root = root, trace = {}, left_parse = {}, events = {}, counts = {predict = 0, match = 0, skip = 0, pop = 0, missing = 0, max_stack = 0}}
    local cursor, step = 1, 0
    while true do
        step = step + 1
        local top, token = stack[#stack], input[cursor]
        local before = {}
        for _, item in ipairs(stack) do
            before[#before + 1] = item.symbol
        end
        local remaining = {table.unpack(input, cursor)}
        local action, kind, terminate = nil, nil, false
        result.counts.max_stack = math.max(result.counts.max_stack, #stack)
        if top.symbol == "$" and token == "$" then
            action, terminate = "accept", true
        elseif top.symbol == "$" then
            action, kind = "error: skip " .. token, "skip"
        elseif not grammar.is_nonterminal(top.symbol) then
            if top.symbol == token then
                action = "match " .. token
                stack[#stack], cursor = nil, cursor + 1
                result.counts.match = result.counts.match + 1
            else
                action, kind = "error: missing " .. top.symbol, "missing"
                top.node.mark, stack[#stack] = "missing", nil
            end
        elseif parse_table.choices[top.symbol][token] then
            local number = parse_table.choices[top.symbol][token]
            local production = parse_table.productions[number]
            action = "predict " .. number .. ": " .. production.notation
            result.left_parse[#result.left_parse + 1] = number
            result.counts.predict = result.counts.predict + 1
            stack[#stack] = nil
            if #production.rhs == 0 then
                top.node.children[1] = M.node("%empty")
            else
                for _, symbol in ipairs(production.rhs) do
                    top.node.children[#top.node.children + 1] = M.node(symbol)
                end
                for index = #top.node.children, 1, -1 do
                    local node = top.node.children[index]
                    stack[#stack + 1] = {symbol = node.symbol, node = node}
                end
            end
        elseif token == "$" or sets.follow[top.symbol][token] then
            action, kind = "error: pop " .. top.symbol, "pop"
            top.node.mark, stack[#stack] = "error", nil
        else
            action, kind = "error: skip " .. token, "skip"
        end
        if kind then
            result.counts[kind] = result.counts[kind] + 1
            result.events[#result.events + 1] = {step = step, kind = kind, symbol = top.symbol, token = token, position = locations[cursor]}
            if kind == "skip" then
                cursor = cursor + 1
            end
        end
        result.trace[#result.trace + 1] = {tostring(step), table.concat(before, " "), table.concat(remaining, " "), action}
        if terminate then
            break
        end
    end
    return result
end
return M
