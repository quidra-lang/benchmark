local selection = require("selection")
local M = {}
local Fit = {}
Fit.__index = Fit
local kappa = {epanechnikov = 0.75, biweight = 0.9375, triweight = 1.09375}
function Fit:evaluate(position)
    if self.cache[position] then
        local result = self.cache[position]
        return result[1], result[2]
    end
    local used, kernels, differences = {}, {}, {}
    local x0, h = position / 100, self.bandwidth / 100
    for i, x in ipairs(self.positions) do
        if math.abs(x - position) < self.bandwidth then
            used[#used + 1] = i
            local delta = x / 100 - x0
            local u = delta / h
            local t = 1 - u * u
            local weight = kappa[self.kernel] * t
            if self.kernel ~= "epanechnikov" then
                weight = weight * t
            end
            if self.kernel == "triweight" then
                weight = weight * t
            end
            kernels[#kernels + 1] = weight
            differences[#differences + 1] = delta
        end
    end
    if #used < (self.local_linear and 2 or 1) then
        self.cache[position] = {}
        return nil, nil
    end
    local s0, t0, s1, s2, t1 = 0.0, 0.0, 0.0, 0.0, 0.0
    for j, i in ipairs(used) do
        local k, d = kernels[j], differences[j]
        s0 = s0 + k
        t0 = t0 + k * self.values[i]
        s1 = s1 + k * d
        s2 = s2 + k * d * d
        t1 = t1 + k * d * self.values[i]
    end
    local weights = {}
    for i = 1, #self.positions do
        weights[i] = 0.0
    end
    local estimate
    if self.local_linear then
        local determinant = s0 * s2 - s1 * s1
        estimate = (s2 * t0 - s1 * t1) / determinant
        for j, i in ipairs(used) do
            weights[i] = kernels[j] * (s2 - s1 * differences[j]) / determinant
        end
    else
        estimate = t0 / s0
        for j, i in ipairs(used) do
            weights[i] = kernels[j] / s0
        end
    end
    self.cache[position] = {estimate, weights}
    return estimate, weights
end
function Fit:estimate(position)
    return (self:evaluate(position))
end
function Fit:weights(position)
    local _, weights = self:evaluate(position)
    return weights
end
function M.fit(positions, values, bandwidth, kernel, local_linear, diagnostics)
    local self = setmetatable({positions = positions, values = values, bandwidth = bandwidth,
        kernel = kernel, local_linear = local_linear, cache = {}}, Fit)
    if diagnostics then
        self.fitted, self.leverage = {}, {}
        local valid = true
        for i, position in ipairs(positions) do
            local estimate, weights = self:evaluate(position)
            self.fitted[i] = estimate
            if weights then
                self.leverage[i] = weights[i]
            else
                valid = false
            end
        end
        if valid then
            self.edf = selection.sum(self.leverage)
        else
            self.fitted, self.leverage = nil, nil
        end
    end
    return self
end
return M
