local selection = require("selection")
local M = {}
local Fit = {}
Fit.__index = Fit
local function zeros(count)
    local values = {}
    for i = 1, count do
        values[i] = 0.0
    end
    return values
end
function Fit:fit_values(values)
    local n, size = #values, #values - 2
    local z = zeros(size)
    for i = 1, size do
        local value = (values[i + 2] - values[i + 1]) / self.h[i + 1]
            - (values[i + 1] - values[i]) / self.h[i]
        if i >= 2 then
            value = value - self.l1[i] * z[i - 1]
        end
        if i >= 3 then
            value = value - self.l2[i] * z[i - 2]
        end
        z[i] = value
    end
    local gamma = zeros(n)
    for i = size, 1, -1 do
        local value = z[i] / self.d[i]
        if i + 1 <= size then
            value = value - self.l1[i + 1] * gamma[i + 2]
        end
        if i + 2 <= size then
            value = value - self.l2[i + 2] * gamma[i + 3]
        end
        gamma[i + 1] = value
    end
    local omega = {(gamma[2] - gamma[1]) / self.h[1]}
    for i = 2, n - 1 do
        omega[i] = (gamma[i + 1] - gamma[i]) / self.h[i]
            - (gamma[i] - gamma[i - 1]) / self.h[i - 1]
    end
    omega[n] = 0 - (gamma[n] - gamma[n - 1]) / self.h[n - 1]
    local fitted = {}
    for i, value in ipairs(values) do
        fitted[i] = value - self.penalty * omega[i]
    end
    return {fitted, gamma}
end
function Fit:evaluate_fit(fit, position)
    local fitted, gamma = fit[1], fit[2]
    local n, x0 = #self.positions, position / 100
    local index = 1
    while index <= n and self.positions[index] < position do
        index = index + 1
    end
    if index <= n and self.positions[index] == position then
        return fitted[index]
    end
    if index == 1 then
        local slope = (fitted[2] - fitted[1]) / self.h[1] - self.h[1] * gamma[2] / 6
        return fitted[1] - (self.x[1] - x0) * slope
    end
    if index == n + 1 then
        local slope = (fitted[n] - fitted[n - 1]) / self.h[n - 1]
            + self.h[n - 1] * gamma[n - 1] / 6
        return fitted[n] + (x0 - self.x[n]) * slope
    end
    local i = index - 1
    local left, right = x0 - self.x[i], self.x[i + 1] - x0
    return (left * fitted[i + 1] + right * fitted[i]) / self.h[i]
        - left * right * ((1 + left / self.h[i]) * gamma[i + 1]
            + (1 + right / self.h[i]) * gamma[i]) / 6
end
function Fit:prepare_basis()
    if self.basis then
        return
    end
    self.basis, self.leverage = {}, {}
    for i = 1, #self.positions do
        local unit = zeros(#self.positions)
        unit[i] = 1.0
        self.basis[i] = self:fit_values(unit)
        self.leverage[i] = self.basis[i][1][i]
    end
    self.edf = selection.sum(self.leverage)
end
function Fit:estimate(position)
    return self:evaluate_fit(self.fit, position)
end
function Fit:weights(position)
    self:prepare_basis()
    local weights = {}
    for i, fit in ipairs(self.basis) do
        weights[i] = self:evaluate_fit(fit, position)
    end
    return weights
end
function M.fit(positions, values, penalty, diagnostics)
    local self = setmetatable({positions = positions, penalty = penalty, x = {}, h = {}}, Fit)
    for i, position in ipairs(positions) do
        self.x[i] = position / 100
        if i > 1 then
            self.h[i - 1] = self.x[i] - self.x[i - 1]
        end
    end
    local size = #positions - 2
    local a, b, c = {}, {}, {}
    for i = 1, size do
        a[i], c[i] = 1 / self.h[i], 1 / self.h[i + 1]
        b[i] = -(a[i] + c[i])
    end
    local diagonal, first, second = {}, {}, {}
    for i = 1, size do
        diagonal[i] = (self.h[i] + self.h[i + 1]) / 3
            + penalty * (a[i] * a[i] + b[i] * b[i] + c[i] * c[i])
        if i < size then
            first[i] = self.h[i + 1] / 6 + penalty * c[i] * (b[i] + b[i + 1])
        end
        if i < size - 1 then
            second[i] = penalty * c[i] * c[i + 1]
        end
    end
    self.d, self.l1, self.l2 = zeros(size), zeros(size), zeros(size)
    for i = 1, size do
        if i >= 3 then
            self.l2[i] = second[i - 2] / self.d[i - 2]
        end
        if i >= 2 then
            local correction = i >= 3 and self.l2[i] * self.d[i - 2] * self.l1[i - 1] or 0.0
            self.l1[i] = (first[i - 1] - correction) / self.d[i - 1]
        end
        local value = diagonal[i]
        if i >= 2 then
            value = value - self.l1[i] * self.l1[i] * self.d[i - 1]
        end
        if i >= 3 then
            value = value - self.l2[i] * self.l2[i] * self.d[i - 2]
        end
        self.d[i] = value
    end
    self.fit = self:fit_values(values)
    self.fitted = self.fit[1]
    if diagnostics then
        self:prepare_basis()
    end
    return self
end
return M
