local M = {}
local function less(first, second)
    return first.weight < second.weight or (first.weight == second.weight and first.minimum < second.minimum)
end
function M.tree_lengths(frequencies)
    local lengths, nodes = {}, {}
    for index, frequency in ipairs(frequencies) do
        lengths[index] = 0
        if frequency > 0 then
            nodes[#nodes + 1] = {weight = frequency, minimum = index - 1, symbol = index - 1}
        end
    end
    if #nodes == 0 then
        return lengths
    end
    if #nodes == 1 then
        lengths[nodes[1].symbol + 1] = 1
        return lengths
    end
    while #nodes > 1 do
        table.sort(nodes, less)
        local first, second = table.remove(nodes, 1), table.remove(nodes, 1)
        nodes[#nodes + 1] = {weight = first.weight + second.weight, minimum = math.min(first.minimum, second.minimum), first = first, second = second}
    end
    local pending = {{node = nodes[1], depth = 0}}
    while #pending > 0 do
        local item = table.remove(pending)
        if item.node.symbol ~= nil then
            lengths[item.node.symbol + 1] = item.depth
        else
            pending[#pending + 1] = {node = item.node.first, depth = item.depth + 1}
            pending[#pending + 1] = {node = item.node.second, depth = item.depth + 1}
        end
    end
    return lengths
end
function M.limited_lengths(frequencies, maximum)
    local weights, halvings = {table.unpack(frequencies)}, 0
    while true do
        local lengths = M.tree_lengths(weights)
        local longest = 0
        for _, length in ipairs(lengths) do
            longest = math.max(longest, length)
        end
        if longest <= maximum then
            return lengths, halvings
        end
        for index, weight in ipairs(weights) do
            weights[index] = (weight + 1) // 2
        end
        halvings = halvings + 1
    end
end
function M.canonical(lengths)
    local ordered, codes = {}, {}
    for index, length in ipairs(lengths) do
        codes[index] = 0
        if length > 0 then
            ordered[#ordered + 1] = index
        end
    end
    table.sort(ordered, function(a, b) return lengths[a] < lengths[b] or (lengths[a] == lengths[b] and a < b) end)
    local code, previous = 0, 0
    for index, symbol in ipairs(ordered) do
        if index > 1 then
            code = (code + 1) << (lengths[symbol] - previous)
        end
        codes[symbol], previous = code, lengths[symbol]
    end
    return codes
end
return M
