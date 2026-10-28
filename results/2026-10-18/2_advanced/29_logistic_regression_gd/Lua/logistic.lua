local M = {}
function M.score(weights, vector)
    local total = 0.0
    for j, weight in ipairs(weights) do
        total = total + weight * vector[j]
    end
    return total
end
function M.probability(score)
    if score >= 0 then
        return 1.0 / (1.0 + math.exp(-score))
    end
    local exponential = math.exp(score)
    return exponential / (1.0 + exponential)
end
function M.loss(score, target)
    return math.max(score, 0.0) - target * score + math.log(1.0 + math.exp(-math.abs(score)))
end
function M.average_loss(weights, vectors, targets)
    local total = 0.0
    for i, vector in ipairs(vectors) do
        total = total + M.loss(M.score(weights, vector), targets[i])
    end
    return total / #vectors
end
function M.penalty(weights)
    local total = 0.0
    for j = 2, #weights do
        total = total + weights[j] * weights[j]
    end
    return total
end
function M.objective(weights, vectors, targets, lambda)
    return M.average_loss(weights, vectors, targets) + lambda * M.penalty(weights) / 2.0
end
function M.gradient(weights, vectors, targets, lambda)
    local totals = {}
    for j = 1, #weights do
        totals[j] = 0.0
    end
    for i, vector in ipairs(vectors) do
        local error = M.probability(M.score(weights, vector)) - targets[i]
        for j = 1, #weights do
            totals[j] = totals[j] + error * vector[j]
        end
    end
    local result = {totals[1] / #vectors}
    for j = 2, #weights do
        result[j] = totals[j] / #vectors + lambda * weights[j]
    end
    return result
end
function M.hessian(weights, vectors, lambda)
    local totals, matrix = {}, {}
    for j = 1, #weights do
        totals[j], matrix[j] = {}, {}
        for k = 1, #weights do
            totals[j][k], matrix[j][k] = 0.0, 0.0
        end
    end
    for _, vector in ipairs(vectors) do
        local pi = M.probability(M.score(weights, vector))
        local variance = pi * (1.0 - pi)
        for j = 1, #weights do
            for k = 1, j do
                totals[j][k] = totals[j][k] + variance * vector[j] * vector[k]
            end
        end
    end
    for j = 1, #weights do
        for k = 1, j do
            local value = totals[j][k] / #vectors
            if j == k and j >= 2 then
                value = value + lambda
            end
            matrix[j][k], matrix[k][j] = value, value
        end
    end
    return matrix
end
return M
