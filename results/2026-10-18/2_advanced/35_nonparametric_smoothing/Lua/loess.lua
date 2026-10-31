local selection = require("selection")
local M = {}
function M.median(values)
    local ordered = {table.unpack(values)}
    table.sort(ordered)
    local middle = #ordered // 2
    if #ordered % 2 == 1 then
        return ordered[middle + 1]
    end
    return (ordered[middle] + ordered[middle + 1]) / 2
end
local function zeros(count)
    local values = {}
    for i = 1, count do
        values[i] = 0.0
    end
    return values
end
local function cholesky(matrix)
    local lower = {}
    for row = 1, #matrix do
        lower[row] = zeros(#matrix)
        for column = 1, row do
            local sigma = matrix[row][column]
            for k = 1, column - 1 do
                sigma = sigma - lower[row][k] * lower[column][k]
            end
            if row == column then
                lower[row][column] = math.sqrt(sigma)
            else
                lower[row][column] = sigma / lower[column][column]
            end
        end
    end
    return lower
end
local function solve(lower, right)
    local intermediate, solution = zeros(#right), zeros(#right)
    for row = 1, #right do
        local value = right[row]
        for k = 1, row - 1 do
            value = value - lower[row][k] * intermediate[k]
        end
        intermediate[row] = value / lower[row][row]
    end
    for row = #right, 1, -1 do
        local value = intermediate[row]
        for k = row + 1, #right do
            value = value - lower[k][row] * solution[k]
        end
        solution[row] = value / lower[row][row]
    end
    return solution
end
local Fit = {}
Fit.__index = Fit
function Fit:local_fit(position)
    local count, neighborhood = #self.positions, {}
    for i = 1, count do
        neighborhood[i] = i
    end
    table.sort(neighborhood, function(a, b)
        local da, db = math.abs(self.positions[a] - position), math.abs(self.positions[b] - position)
        return da < db or (da == db and a < b)
    end)
    local q = self.span * count // 100
    local distance = math.abs(self.positions[neighborhood[q]] - position)
    local selected = {}
    for i = 1, q do
        selected[i] = neighborhood[i]
    end
    table.sort(selected)
    local size = self.degree + 1
    local matrix, right, rows = {}, zeros(size), {}
    for k = 1, size do
        matrix[k] = zeros(size)
    end
    for _, i in ipairs(selected) do
        local a = math.abs(self.positions[i] - position) / distance
        local s = 1 - a * a * a
        local weight = s * s * s * self.rho[i]
        local delta = self.positions[i] / 100 - position / 100
        local basis = {1.0, delta}
        if self.degree == 2 then
            basis[3] = delta * delta
        end
        rows[#rows + 1] = {i, weight, basis}
        for row = 1, size do
            right[row] = right[row] + weight * basis[row] * self.values[i]
            for column = 1, size do
                matrix[row][column] = matrix[row][column] + weight * basis[row] * basis[column]
            end
        end
    end
    local lower = cholesky(matrix)
    local beta = solve(lower, right)
    local unit = zeros(size)
    unit[1] = 1.0
    local zeta = solve(lower, unit)
    local weights = zeros(count)
    for _, row in ipairs(rows) do
        local sum = 0.0
        for k = 1, size do
            sum = sum + zeta[k] * row[3][k]
        end
        weights[row[1]] = row[2] * sum
    end
    return {beta[1], zeta[1], weights}
end
function Fit:evaluate(position)
    if not self.cache[position] then
        self.cache[position] = self:local_fit(position)
    end
    return self.cache[position]
end
function Fit:estimate(position)
    return self:evaluate(position)[1]
end
function Fit:weights(position)
    return self:evaluate(position)[3]
end
function M.fit(positions, values, span, degree, iterations, diagnostics)
    local self = setmetatable({positions = positions, values = values, span = span,
        degree = degree, rho = {}, records = {}, cache = {}}, Fit)
    for i = 1, #positions do
        self.rho[i] = 1.0
    end
    if not diagnostics then
        return self
    end
    local fits = {}
    for i, position in ipairs(positions) do
        fits[i] = self:local_fit(position)
    end
    for iteration = 1, iterations do
        local residuals, absolute = {}, {}
        for i, value in ipairs(values) do
            residuals[i] = value - fits[i][1]
            absolute[i] = math.abs(residuals[i])
        end
        local scale, zero = M.median(absolute), 0
        for i, residual in ipairs(residuals) do
            local u = residual / (6 * scale)
            local v = 1 - u * u
            self.rho[i] = math.abs(u) < 1 and v * v or 0.0
            if self.rho[i] == 0 then
                zero = zero + 1
            end
        end
        local updated, change = {}, 0.0
        for i, position in ipairs(positions) do
            updated[i] = self:local_fit(position)
            change = math.max(change, math.abs(updated[i][1] - fits[i][1]))
        end
        self.records[#self.records + 1] = {iteration, scale, zero, change}
        fits = updated
    end
    self.fitted, self.leverage = {}, {}
    for i, position in ipairs(positions) do
        self.cache[position] = fits[i]
        self.fitted[i] = fits[i][1]
        self.leverage[i] = self.rho[i] * fits[i][2]
    end
    self.edf = selection.sum(self.leverage)
    return self
end
return M
