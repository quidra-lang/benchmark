local matrix = require("matrix")
local M = {}
function M.off(values)
    local result = 0.0
    for p = 1, #values - 1 do
        for q = p + 1, #values do
            result = result + values[p][q] * values[p][q]
        end
    end
    return result
end
local function rotate(a, vectors, p, q)
    local off = a[p][q]
    if off == 0.0 then
        return
    end
    local theta = (a[q][q] - a[p][p]) / (2.0 * off)
    local t = 1.0 / (math.abs(theta) + math.sqrt(theta * theta + 1.0))
    if theta < 0.0 then
        t = -t
    end
    local c = 1.0 / math.sqrt(t * t + 1.0)
    local s = t * c
    for r = 1, #a do
        if r ~= p and r ~= q then
            local rp, rq = a[r][p], a[r][q]
            a[r][p], a[p][r] = c * rp - s * rq, c * rp - s * rq
            a[r][q], a[q][r] = s * rp + c * rq, s * rp + c * rq
        end
    end
    a[p][p], a[q][q] = a[p][p] - t * off, a[q][q] + t * off
    a[p][q], a[q][p] = 0.0, 0.0
    for r = 1, #vectors do
        local rp, rq = vectors[r][p], vectors[r][q]
        vectors[r][p], vectors[r][q] = c * rp - s * rq, s * rp + c * rq
    end
end
function M.jacobi(values)
    local a, vectors = matrix.copy(values), matrix.identity(#values)
    local initial, count = M.off(a), 0
    if initial > 0.0 then
        for sweep = 1, 100 do
            for p = 1, #values - 1 do
                for q = p + 1, #values do
                    rotate(a, vectors, p, q)
                end
            end
            local off = M.off(a)
            if count == 0 and off < 1e-16 * initial then
                count = sweep
            end
            if off < 1e-22 * initial then
                break
            end
        end
    end
    local order = {}
    for index = 1, #values do
        order[index] = index
    end
    table.sort(order, function(first, second)
        if a[first][first] ~= a[second][second] then
            return a[first][first] > a[second][second]
        end
        return first < second
    end)
    local eigenvalues, eigenvectors = {}, {}
    for index, column in ipairs(order) do
        eigenvalues[index] = a[column][column]
        eigenvectors[index] = matrix.orient(matrix.normalize(matrix.column(vectors, column)))
    end
    return {values = eigenvalues, vectors = eigenvectors, sweeps = count}
end
function M.power(values, reference)
    local work, result = matrix.copy(values), {}
    for k = 1, #values do
        local x = {}
        for j = 1, #values do
            x[j] = 1.0
        end
        local agreement
        local opposite = {}
        for j, value in ipairs(reference.vectors[k]) do
            opposite[j] = -value
        end
        for iteration = 1, 1000 do
            x = matrix.normalize(matrix.product(work, x))
            local difference = math.min(matrix.maximum_difference(x, reference.vectors[k]), matrix.maximum_difference(x, opposite))
            if not agreement and difference < 0.000001 then
                agreement = iteration
            end
        end
        local product = matrix.product(work, x)
        local value = matrix.dot(x, product)
        local vector = matrix.orient(matrix.normalize(x))
        local matched = math.abs(value - reference.values[k]) <= 1e-8 * reference.values[1]
            and matrix.maximum_difference(vector, reference.vectors[k]) <= 0.000001
        result[k] = {value = value, vector = vector, agreement = agreement, matched = matched}
        work = matrix.deflate(work, value, vector)
    end
    return result
end
return M
