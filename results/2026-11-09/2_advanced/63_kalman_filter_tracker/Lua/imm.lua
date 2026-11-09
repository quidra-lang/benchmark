local K = require("kalman")
local M = require("matrix")
local I = {}
I.__index = I
function I.new(densities, transition, initial, sigma, velocity, measurement)
    return setmetatable({ models = { K.new("CV", densities[1], sigma, velocity, 0.0, measurement), K.new("CV", densities[2], sigma, velocity, 0.0, measurement) },
        transition = { { transition[1], transition[2] }, { transition[3], transition[4] } }, probabilities = { initial[1], initial[2] } }, I)
end
function I:step(interval, measurement)
    local mu, p = self.probabilities, self.transition
    local predicted, old_x, old_p, likelihoods = {}, { self.models[1].x, self.models[2].x }, { self.models[1].P, self.models[2].P }, {}
    for j = 1, 2 do predicted[j] = p[1][j] * mu[1] + p[2][j] * mu[2] end
    for j, model in ipairs(self.models) do
        local w1, w2 = p[1][j] * mu[1] / predicted[j], p[2][j] * mu[2] / predicted[j]
        local mixed, covariance = {}, M.zeros(4)
        for r = 1, 4 do mixed[r] = w1 * old_x[1][r] + w2 * old_x[2][r] end
        for r = 1, 4 do
            for s = 1, 4 do covariance[r][s] = w1 * (old_p[1][r][s] + (old_x[1][r] - mixed[r]) * (old_x[1][s] - mixed[s]))
                + w2 * (old_p[2][r][s] + (old_x[2][r] - mixed[r]) * (old_x[2][s] - mixed[s])) end
        end
        model.x, model.P = mixed, covariance
        model:predict(interval)
        local likelihood = 1.0
        if measurement then
            local distance2, _, innovation_covariance = model:update(measurement)
            likelihood = math.exp(-distance2 / 2) / (2 * math.pi * math.sqrt(M.determinant2(innovation_covariance)))
        end
        likelihoods[j] = likelihood
    end
    local denominator = likelihoods[1] * predicted[1] + likelihoods[2] * predicted[2]
    self.probabilities = { likelihoods[1] * predicted[1] / denominator, likelihoods[2] * predicted[2] / denominator }
end
function I:estimate()
    local result = {}
    for r = 1, 4 do result[r] = self.probabilities[1] * self.models[1].x[r] + self.probabilities[2] * self.models[2].x[r] end
    return result
end
return I
