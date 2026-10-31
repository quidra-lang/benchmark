local M = require("matrix")
local K = {}
K.__index = K
function K.transition(model, t)
    local result = M.identity(model == "CV" and 4 or 6)
    result[1][3], result[2][4] = t, t
    if model == "CA" then result[1][5], result[2][6], result[3][5], result[4][6] = t * t / 2, t * t / 2, t, t end
    return result
end
local function process_noise(model, t, q)
    local result, entries
    if model == "CV" then result, entries = M.zeros(4), { { 1, 1, q * t * t * t / 3 }, { 1, 3, q * t * t / 2 }, { 3, 3, q * t } }
    else
        result, entries = M.zeros(6), {
            { 1, 1, q * t * t * t * t * t / 20 }, { 1, 3, q * t * t * t * t / 8 }, { 1, 5, q * t * t * t / 6 },
            { 3, 3, q * t * t * t / 3 }, { 3, 5, q * t * t / 2 }, { 5, 5, q * t }
        }
    end
    for axis = 0, 1 do for _, entry in ipairs(entries) do result[entry[1] + axis][entry[2] + axis] = entry[3]; result[entry[2] + axis][entry[1] + axis] = entry[3] end end
    return result
end
function K.new(model, q, sigma, velocity, acceleration, measurement)
    local size, x, variances = model == "CV" and 4 or 6, { measurement[1], measurement[2] }, { sigma * sigma, sigma * sigma, velocity, velocity }
    for i = 3, size do x[i] = 0.0 end
    if size == 6 then variances[5], variances[6] = acceleration, acceleration end
    local H = M.zeros(2, size)
    H[1][1], H[2][2] = 1.0, 1.0
    return setmetatable({ model = model, q = q, x = x, P = M.diagonal(variances), H = H, R = M.diagonal({ sigma * sigma, sigma * sigma }) }, K)
end
function K:predict(interval)
    self.F = K.transition(self.model, interval)
    self.x = M.vector(self.F, self.x)
    self.P = M.add(M.product(M.product(self.F, self.P), M.transpose(self.F)), process_noise(self.model, interval, self.q))
    self.xp, self.Pp = self.x, self.P
end
function K:innovation(measurement)
    local residual = M.vector_subtract(measurement, M.vector(self.H, self.x))
    local covariance = M.add(M.product(M.product(self.H, self.P), M.transpose(self.H)), self.R)
    local precision = M.inverse(covariance)
    return { residual, covariance, precision, M.quadratic2(residual, precision) }
end
function K:update(measurement, innovation)
    innovation = innovation or self:innovation(measurement)
    local residual, covariance, precision, distance2 = table.unpack(innovation)
    local gain = M.product(M.product(self.P, M.transpose(self.H)), precision)
    local correction = M.subtract(M.identity(#self.x), M.product(gain, self.H))
    self.x = M.vector_add(self.x, M.vector(gain, residual))
    self.P = M.add(M.product(M.product(correction, self.P), M.transpose(correction)), M.product(M.product(gain, self.R), M.transpose(gain)))
    local likelihood = -math.log(2 * math.pi) - math.log(M.determinant2(covariance)) / 2 - distance2 / 2
    return distance2, likelihood, covariance
end
function K:snapshot() return { x = self.x, P = self.P, xp = self.xp, Pp = self.Pp, F = self.F } end
function K.smooth(history)
    local states = { [#history] = history[#history].x }
    for i = #history - 1, 1, -1 do
        local current, following = history[i], history[i + 1]
        local gain = M.product(M.product(current.P, M.transpose(following.F)), M.inverse(following.Pp))
        states[i] = M.vector_add(current.x, M.vector(gain, M.vector_subtract(states[i + 1], following.xp)))
    end
    return states
end
return K
