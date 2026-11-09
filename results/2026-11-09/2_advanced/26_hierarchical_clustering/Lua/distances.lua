local M = {types = {"euclidean", "manhattan", "correlation"}}

function M.sum(values)
    local total = 0.0
    for _, value in ipairs(values) do total = total + value end
    return total
end

function M.squared(first, second)
    local total = 0.0
    for f = 1, #first do
        local difference = first[f] - second[f]
        total = total + difference * difference
    end
    return total
end

function M.statistics(rows)
    local means, deviations = {}, {}
    for f = 1, #rows[1] do
        local total = 0.0
        for _, row in ipairs(rows) do total = total + row[f] end
        local mean, spread = total / #rows, 0.0
        for _, row in ipairs(rows) do spread = spread + (row[f] - mean) * (row[f] - mean) end
        means[f], deviations[f] = mean, math.sqrt(spread / (#rows - 1))
    end
    return means, deviations
end

function M.standardize(rows, means, deviations)
    local vectors = {}
    for i, row in ipairs(rows) do
        vectors[i] = {}
        for f, value in ipairs(row) do vectors[i][f] = (value - means[f]) / deviations[f] end
    end
    return vectors
end

function M.distance(first, second, kind)
    if kind == "euclidean" then return math.sqrt(M.squared(first, second)) end
    local total = 0.0
    if kind == "manhattan" then
        for f = 1, #first do total = total + math.abs(first[f] - second[f]) end
        return total
    end
    local mean_first, mean_second = M.sum(first) / #first, M.sum(second) / #second
    local cross, spread_first, spread_second = 0.0, 0.0, 0.0
    for f = 1, #first do
        local a, b = first[f] - mean_first, second[f] - mean_second
        cross = cross + a * b
        spread_first, spread_second = spread_first + a * a, spread_second + b * b
    end
    return 1 - cross / math.sqrt(spread_first * spread_second)
end

function M.matrix(vectors, kind)
    local matrix = {}
    for i = 1, #vectors do
        matrix[i] = {}
        for j = 1, #vectors do matrix[i][j] = 0.0 end
    end
    for i = 1, #vectors do
        for j = i + 1, #vectors do
            local value = M.distance(vectors[i], vectors[j], kind)
            matrix[i][j], matrix[j][i] = value, value
        end
    end
    return matrix
end

return M
