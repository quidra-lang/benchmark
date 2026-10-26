local distances = require("distances")
local M = {}

function M.correlation(first, second)
    local a, b = distances.sum(first) / #first, distances.sum(second) / #second
    local cross, sx, sy = 0.0, 0.0, 0.0
    for i = 1, #first do
        cross = cross + (first[i] - a) * (second[i] - b)
        sx, sy = sx + (first[i] - a) * (first[i] - a), sy + (second[i] - b) * (second[i] - b)
    end
    return cross / math.sqrt(sx * sy)
end

function M.contingency(first, second, rows, columns)
    local counts = {}
    for a = 1, rows do
        counts[a] = {}
        for b = 1, columns do counts[a][b] = 0 end
    end
    for i, a in ipairs(first) do counts[a][second[i]] = counts[a][second[i]] + 1 end
    return counts
end

function M.ari(counts)
    local function pairs(r) return r * (r - 1) // 2 end
    local count, same, row_pairs, column_pairs = 0, 0, 0, 0
    local columns = {}
    for b = 1, #counts[1] do columns[b] = 0 end
    for _, row in ipairs(counts) do
        local total = 0
        for b, value in ipairs(row) do
            total, same, columns[b] = total + value, same + pairs(value), columns[b] + value
        end
        count, row_pairs = count + total, row_pairs + pairs(total)
    end
    for _, value in ipairs(columns) do column_pairs = column_pairs + pairs(value) end
    local z = pairs(count)
    local numerator = 2 * (z * same - row_pairs * column_pairs)
    local denominator = z * (row_pairs + column_pairs) - 2 * row_pairs * column_pairs
    if denominator == 0 then return {1, 1} end
    local a, b = math.abs(numerator), math.abs(denominator)
    while b ~= 0 do a, b = b, a % b end
    if denominator < 0 then a = -a end
    return {numerator // a, denominator // a}
end

function M.silhouettes(partition, groups, delta)
    local sizes, values = {}, {}
    for g = 1, groups do sizes[g] = 0 end
    for _, g in ipairs(partition) do sizes[g] = sizes[g] + 1 end
    for i, own in ipairs(partition) do
        if sizes[own] == 1 then values[i] = 0.0
        else
            local sums, outer = {}, nil
            for g = 1, groups do sums[g] = 0.0 end
            for j, other in ipairs(partition) do if j ~= i then sums[other] = sums[other] + delta[i][j] end end
            local inner = sums[own] / (sizes[own] - 1)
            for g = 1, groups do if g ~= own then outer = math.min(outer or math.huge, sums[g] / sizes[g]) end end
            values[i] = (outer - inner) / math.max(inner, outer)
        end
    end
    return values
end

return M
