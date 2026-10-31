local matrix = require("matrix")
local M = {}
function M.prepare(rows, scaling)
    local n, size, means = #rows, #rows[1], {}
    for j = 1, size do
        local sum = 0.0
        for i = 1, n do
            sum = sum + rows[i][j]
        end
        means[j] = sum / n
    end
    local covariance, correlation, deviations, scales = {}, {}, {}, {}
    for j = 1, size do
        covariance[j], correlation[j] = {}, {}
    end
    for j = 1, size do
        for k = j, size do
            local sum = 0.0
            for i = 1, n do
                sum = sum + (rows[i][j] - means[j]) * (rows[i][k] - means[k])
            end
            covariance[j][k], covariance[k][j] = sum / (n - 1), sum / (n - 1)
        end
        deviations[j] = math.sqrt(covariance[j][j])
        scales[j] = scaling == "covariance" and 1.0 or deviations[j]
    end
    for j = 1, size do
        for k = 1, size do
            correlation[j][k] = j == k and 1.0 or covariance[j][k] / (deviations[j] * deviations[k])
        end
    end
    local values = scaling == "covariance" and covariance or correlation
    local standardized = M.standardize(rows, means, scales)
    return {means = means, deviations = deviations, scales = scales, covariance = covariance,
        correlation = correlation, values = values, standardized = standardized}
end
function M.standardize(rows, means, scales)
    local result = {}
    for i, row in ipairs(rows) do
        result[i] = {}
        for j = 1, #means do
            result[i][j] = row[j] == false and 0.0 or (row[j] - means[j]) / scales[j]
        end
    end
    return result
end
function M.scores(standardized, vectors)
    local result = {}
    for i, row in ipairs(standardized) do
        result[i] = {}
        for k, vector in ipairs(vectors) do
            result[i][k] = matrix.dot(row, vector)
        end
    end
    return result
end
function M.residual(row, scores, vectors, count)
    local result = {}
    for j, value in ipairs(row) do
        local reconstructed = 0.0
        for k = 1, count do
            reconstructed = reconstructed + scores[k] * vectors[k][j]
        end
        result[j] = value - reconstructed
    end
    return result
end
function M.t2(scores, eigenvalues, count)
    local result = 0.0
    for k = 1, count do
        result = result + (scores[k] * scores[k]) / eigenvalues[k]
    end
    return result
end
return M
