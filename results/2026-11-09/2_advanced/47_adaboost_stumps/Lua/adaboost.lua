local stumps = require("stumps")
local M = {}
local function normalize(weights)
    local sum = 0.0
    for _, value in ipairs(weights) do
        sum = sum + value
    end
    for i, value in ipairs(weights) do
        weights[i] = value / sum
    end
    return sum
end
function M.discrete(rows, maximum, shrinkage, initial_weights)
    local weights = initial_weights and {table.unpack(initial_weights)} or {}
    if not initial_weights then
        for i = 1, #rows do
            weights[i] = 1.0 / #rows
        end
    end
    local prepared, rounds, bound = stumps.prepare(rows), {}, 1.0
    for _ = 1, maximum do
        local candidate = stumps.discrete(rows, weights, prepared)
        local error = candidate.error
        if error >= 0.5 then
            return {rounds = rounds, stop = "weak"}
        end
        local alpha = error <= 0.0000000001 and 1.0 or shrinkage * (0.5 * math.log((1.0 - error) / error))
        local polarity = candidate.polarity
        local stump = {feature = candidate.feature, thresholds = {candidate.threshold}, values = {-polarity * alpha, polarity * alpha}}
        local previous = {table.unpack(weights)}
        for i, row in ipairs(rows) do
            local decision = row.values[candidate.feature] > candidate.threshold and polarity or -polarity
            weights[i] = weights[i] * math.exp(decision == row.label and -alpha or alpha)
        end
        local z = normalize(weights)
        bound = bound * z
        rounds[#rounds + 1] = {stump = stump, polarity = polarity, error = error, alpha = alpha,
            z = z, bound = bound, weights = previous}
        if error <= 0.0000000001 then
            return {rounds = rounds, stop = "perfect"}
        end
    end
    return {rounds = rounds, stop = "completed"}
end
function M.samme(rows, classes, maximum)
    local weights, rounds, prepared = {}, {}, stumps.prepare(rows)
    for i = 1, #rows do
        weights[i] = 1.0 / #rows
    end
    for _ = 1, maximum do
        local candidate = stumps.multiclass(rows, weights, prepared, classes)
        local error = candidate.error
        if error >= (classes - 1) / classes then
            return {rounds = rounds, stop = "weak"}
        end
        local alpha = error <= 0.0000000001 and 1.0 or math.log((1.0 - error) / error) + math.log(classes - 1)
        for i, row in ipairs(rows) do
            if stumps.output(candidate.stump, row.values) ~= row.label then
                weights[i] = weights[i] * math.exp(alpha)
            end
        end
        normalize(weights)
        rounds[#rounds + 1] = {stump = candidate.stump, error = error, alpha = alpha}
        if error <= 0.0000000001 then
            return {rounds = rounds, stop = "perfect"}
        end
    end
    return {rounds = rounds, stop = "completed"}
end
return M
