local logistic, optimizers = require("logistic"), require("optimizers")
local M = {}
function M.shifted_scores(weights, vector)
    local scores, top = {}, nil
    for k, row in ipairs(weights) do
        scores[k] = logistic.score(row, vector)
        if not top or scores[k] > top then
            top = scores[k]
        end
    end
    for k = 1, #scores do
        scores[k] = scores[k] - top
    end
    return scores
end
function M.probabilities(weights, vector)
    local shifted, total, result = M.shifted_scores(weights, vector), 0.0, {}
    for _, value in ipairs(shifted) do
        total = total + math.exp(value)
    end
    for k, value in ipairs(shifted) do
        result[k] = math.exp(value) / total
    end
    return result
end
function M.predicted_class(probabilities)
    local best = 1
    for k = 2, #probabilities do
        if probabilities[k] > probabilities[best] then
            best = k
        end
    end
    return best - 1
end
function M.loss(weights, vector, label)
    local shifted, total = M.shifted_scores(weights, vector), 0.0
    for _, value in ipairs(shifted) do
        total = total + math.exp(value)
    end
    return math.log(total) - shifted[label + 1]
end
function M.average_loss(weights, vectors, labels)
    local total = 0.0
    for i, vector in ipairs(vectors) do
        total = total + M.loss(weights, vector, labels[i])
    end
    return total / #vectors
end
function M.penalty(weights)
    local total = 0.0
    for _, row in ipairs(weights) do
        for j = 2, #row do
            total = total + row[j] * row[j]
        end
    end
    return total
end
function M.objective(weights, vectors, labels, lambda)
    return M.average_loss(weights, vectors, labels) + lambda * M.penalty(weights) / 2.0
end
function M.gradient(weights, vectors, labels, lambda)
    local totals, result = {}, {}
    for k, row in ipairs(weights) do
        totals[k], result[k] = {}, {}
        for j = 1, #row do
            totals[k][j] = 0.0
        end
    end
    for i, vector in ipairs(vectors) do
        local probabilities = M.probabilities(weights, vector)
        for k, row in ipairs(totals) do
            local error = probabilities[k] - (labels[i] == k - 1 and 1.0 or 0.0)
            for j = 1, #row do
                row[j] = row[j] + error * vector[j]
            end
        end
    end
    for k, row in ipairs(totals) do
        result[k][1] = row[1] / #vectors
        for j = 2, #row do
            result[k][j] = row[j] / #vectors + lambda * weights[k][j]
        end
    end
    return result
end
function M.train(vectors, labels, classes, lambda, rate, iterations)
    local weights = {}
    for k = 1, classes do
        weights[k] = {}
        for j = 1, #vectors[1] do
            weights[k][j] = 0.0
        end
    end
    local checkpoints = {{iteration = 0, weights = weights}}
    for t = 1, iterations do
        local direction = M.gradient(weights, vectors, labels, lambda)
        local next_weights = {}
        for k, row in ipairs(weights) do
            next_weights[k] = optimizers.move(row, direction[k], rate)
        end
        weights = next_weights
        if t % 100 == 0 then
            checkpoints[#checkpoints + 1] = {iteration = t, weights = weights}
        end
    end
    return checkpoints
end
return M
