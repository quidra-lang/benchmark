local Crossing = {}

function Crossing.positions(orders)
    local result = {}
    for _, layer in ipairs(orders) do for index, vertex in ipairs(layer) do result[vertex] = index - 1 end end
    return result
end

function Crossing.accumulator(segments, position, lower_size)
    local capacity = 1
    while capacity < lower_size do capacity = capacity * 2 end
    local tree, pairs, count = {}, {}, 0
    for i = 0, 2 * capacity - 2 do tree[i] = 0 end
    for _, segment in ipairs(segments) do pairs[#pairs + 1] = {position[segment[1]], position[segment[2]]} end
    table.sort(pairs, function(a, b) return a[1] == b[1] and a[2] < b[2] or a[1] < b[1] end)
    for _, pair in ipairs(pairs) do
        local index = pair[2] + capacity - 1
        tree[index] = tree[index] + 1
        while index > 0 do
            if index % 2 == 1 then count = count + tree[index + 1] end
            index = (index - 1) // 2
            tree[index] = tree[index] + 1
        end
    end
    return count
end

function Crossing.brute(segments, position)
    local count = 0
    for i, first in ipairs(segments) do
        for j = i + 1, #segments do
            local second = segments[j]
            if (position[first[1]] - position[second[1]]) * (position[first[2]] - position[second[2]]) < 0 then count = count + 1 end
        end
    end
    return count
end

function Crossing.gap_counts(gaps, orders)
    local result, position = {}, Crossing.positions(orders)
    for i, segments in ipairs(gaps) do result[i] = Crossing.accumulator(segments, position, #orders[i + 1]) end
    return result
end

function Crossing.total(gaps, orders)
    local count = 0
    for _, value in ipairs(Crossing.gap_counts(gaps, orders)) do count = count + value end
    return count
end

function Crossing.local_cost(gaps, orders, layer)
    local position, count = Crossing.positions(orders), 0
    for gap = layer - 1, layer do
        if gap >= 1 and gap <= #gaps then count = count + Crossing.accumulator(gaps[gap], position, #orders[gap + 1]) end
    end
    return count
end

function Crossing.adjacent_cost(first, second, upper, lower, position)
    local count = 0
    for _, neighbors in ipairs({upper, lower}) do
        for _, a in ipairs(neighbors[first]) do for _, b in ipairs(neighbors[second]) do if position[a] > position[b] then count = count + 1 end end end
    end
    return count
end

return Crossing
