local stumps = require("stumps")
local M = {}
local function uniform(count)
    local result = {}
    for i = 1, count do
        result[i] = 1.0 / count
    end
    return result
end
local function update(rows, weights, stump)
    local sum = 0.0
    for i, row in ipairs(rows) do
        weights[i] = weights[i] * math.exp(-row.label * stumps.output(stump, row.values))
    end
    for _, value in ipairs(weights) do
        sum = sum + value
    end
    for i, value in ipairs(weights) do
        weights[i] = value / sum
    end
end
function M.real(rows, params)
    local weights, rounds, bound = uniform(#rows), {}, 1.0
    local cuts = stumps.cuts(rows, stumps.prepare(rows), params.bins)
    for _ = 1, params.rounds do
        local candidate = stumps.choose(stumps.real_candidates(rows, weights, cuts, params.bins))
        local z = candidate.error
        if z >= 1.0 - params.convergence then
            return {rounds = rounds, stop = "converged", cuts = cuts}
        end
        local values = {}
        for bin = 1, params.bins do
            values[bin] = 0.5 * math.log((candidate.positive[bin] + params.smoothing) / (candidate.negative[bin] + params.smoothing))
        end
        local stump = {feature = candidate.feature, thresholds = cuts[candidate.feature], values = values}
        bound = bound * z
        rounds[#rounds + 1] = {stump = stump, z = z, bound = bound, weights = {table.unpack(weights)}}
        update(rows, weights, stump)
    end
    return {rounds = rounds, stop = "completed", cuts = cuts}
end
function M.gentle(rows, params)
    local weights, rounds, targets = uniform(#rows), {}, {}
    local prepared = stumps.prepare(rows)
    for i, row in ipairs(rows) do
        targets[i] = row.label + 0.0
    end
    for _ = 1, params.rounds do
        local candidate = stumps.regression(rows, targets, weights, prepared)
        rounds[#rounds + 1] = {stump = candidate.stump, error = candidate.error, weights = {table.unpack(weights)}}
        update(rows, weights, candidate.stump)
    end
    return {rounds = rounds, stop = "completed"}
end
function M.logit(rows, params)
    local scores, probabilities, rounds = {}, {}, {}
    local prepared = stumps.prepare(rows)
    for i = 1, #rows do
        scores[i], probabilities[i] = 0.0, 0.5
    end
    for _ = 1, params.rounds do
        local q, targets, sum = {}, {}, 0.0
        for i, row in ipairs(rows) do
            local p = probabilities[i]
            q[i] = p * (1.0 - p)
            targets[i] = math.max(-params.clip, math.min(params.clip, ((row.label == 1 and 1.0 or 0.0) - p) / q[i]))
            sum = sum + q[i]
        end
        local weights = {}
        for i, value in ipairs(q) do
            weights[i] = value / sum
        end
        local candidate = stumps.regression(rows, targets, weights, prepared)
        local original = candidate.stump
        local stump = {feature = original.feature, thresholds = original.thresholds,
            values = {original.values[1] / 2.0, original.values[2] / 2.0}}
        for i, row in ipairs(rows) do
            scores[i] = scores[i] + stumps.output(stump, row.values)
            probabilities[i] = 1.0 / (1.0 + math.exp(-2.0 * scores[i]))
        end
        local loss = 0.0
        for i, row in ipairs(rows) do
            loss = loss + math.log(1.0 + math.exp(-2.0 * row.label * scores[i]))
        end
        rounds[#rounds + 1] = {stump = stump, error = candidate.error, loss = loss / #rows, weights = weights}
    end
    return {rounds = rounds, stop = "completed"}
end
return M
