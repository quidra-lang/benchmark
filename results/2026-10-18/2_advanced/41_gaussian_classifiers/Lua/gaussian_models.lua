local linalg = require("linalg")
local M, Model = {}, {}
Model.__index = Model
function M.argmax(values)
    local best = 1
    for index = 2, #values do
        if values[index] > values[best] then
            best = index
        end
    end
    return best
end
function M.argmin(values)
    local best = 1
    for index = 2, #values do
        if values[index] < values[best] then
            best = index
        end
    end
    return best
end
function M.statistics(rows, features, count)
    local p, groups, vectors = #features, {}, {}
    for k = 1, count do
        groups[k] = {}
    end
    for index, row in ipairs(rows) do
        local vector = {}
        for j, feature in ipairs(features) do
            vector[j] = row.values[feature]
        end
        vectors[index] = vector
        local group = groups[row.class_index]
        group[#group + 1] = vector
    end
    local stats = {row_count = #rows, counts = {}, means = {}, scatter = {}, center = {}, variances = {}}
    for k, group in ipairs(groups) do
        stats.counts[k], stats.means[k], stats.scatter[k] = #group, {}, linalg.zeros(p)
        for j = 1, p do
            local total = 0.0
            for _, vector in ipairs(group) do
                total = total + vector[j]
            end
            stats.means[k][j] = total / #group
        end
        for a = 1, p do
            for b = 1, p do
                local total = 0.0
                for _, vector in ipairs(group) do
                    total = total + (vector[a] - stats.means[k][a]) * (vector[b] - stats.means[k][b])
                end
                stats.scatter[k][a][b] = total
            end
        end
    end
    for j = 1, p do
        local total = 0.0
        for _, vector in ipairs(vectors) do
            total = total + vector[j]
        end
        stats.center[j] = total / #rows
        total = 0.0
        for _, vector in ipairs(vectors) do
            local delta = vector[j] - stats.center[j]
            total = total + delta * delta
        end
        stats.variances[j] = total / #rows
    end
    stats.pooled = linalg.zeros(p)
    for a = 1, p do
        for b = 1, p do
            local total = 0.0
            for k = 1, count do
                total = total + stats.scatter[k][a][b]
            end
            stats.pooled[a][b] = total / (#rows - count)
        end
    end
    return stats
end
function M.train(rows, features, count, name, prior, epsilon, gamma)
    local stats, p = M.statistics(rows, features, count), #features
    local model = setmetatable({name = name, features = features, statistics = stats, epsilon = epsilon, gamma = gamma,
        means = stats.means, priors = {}, covariances = {}, factors = {}, log_determinants = {}, log_priors = {}}, Model)
    model.max_variance = stats.variances[M.argmax(stats.variances)]
    model.added_variance = epsilon * model.max_variance
    for k = 1, count do
        model.priors[k] = prior == "empirical" and stats.counts[k] / #rows or 1 / count
        model.log_priors[k] = math.log(model.priors[k])
        local covariance = linalg.zeros(p)
        for a = 1, p do
            for b = 1, p do
                if name == "LDA" then
                    covariance[a][b] = stats.pooled[a][b]
                elseif name == "NB" then
                    if a == b then
                        covariance[a][b] = stats.scatter[k][a][b] / stats.counts[k] + model.added_variance
                    end
                else
                    local value = stats.scatter[k][a][b] / (stats.counts[k] - 1)
                    covariance[a][b] = a == b and value or value * (1 - gamma)
                end
            end
        end
        model.covariances[k] = covariance
        model.factors[k] = linalg.cholesky(covariance)
        model.log_determinants[k] = linalg.log_determinant(model.factors[k])
    end
    model.normalizer = p * math.log(2 * math.pi) / 2
    return model
end
function Model:vector(values)
    local result = {}
    for j, feature in ipairs(self.features) do
        result[j] = values[feature]
    end
    return result
end
function Model:squared_distances(vector)
    local result = {}
    for k, mean in ipairs(self.means) do
        local delta = {}
        for j = 1, #vector do
            delta[j] = vector[j] - mean[j]
        end
        result[k] = linalg.quadratic(self.factors[k], delta)
    end
    return result
end
function Model:distances(values)
    return self:squared_distances(self:vector(values))
end
function Model:scores(vector)
    local distances, scores = self:squared_distances(vector), {}
    for k, value in ipairs(distances) do
        scores[k] = self.log_priors[k] - self.normalizer - self.log_determinants[k] / 2 - value / 2
    end
    return scores
end
function Model:predict(values)
    return M.argmax(self:scores(self:vector(values)))
end
function Model:infer_vector(vector, costs)
    local scores = self:scores(vector)
    local predicted = M.argmax(scores)
    local maximum, exponentials, total = scores[predicted], {}, 0.0
    for k, score in ipairs(scores) do
        exponentials[k] = math.exp(score - maximum)
        total = total + exponentials[k]
    end
    local posterior, log_posterior = {}, {}
    local log_total = math.log(total)
    for k, score in ipairs(scores) do
        posterior[k], log_posterior[k] = exponentials[k] / total, (score - maximum) - log_total
    end
    local decision = predicted
    if costs then
        local risks = {}
        for b = 1, #scores do
            local value = 0.0
            for k = 1, #scores do
                value = value + posterior[k] * costs[k][b]
            end
            risks[b] = value
        end
        decision = M.argmin(risks)
    end
    return {predicted = predicted, posterior = posterior, log_posterior = log_posterior, confidence = posterior[M.argmax(posterior)], decision = decision}
end
function Model:infer(values, costs)
    return self:infer_vector(self:vector(values), costs)
end
return M
