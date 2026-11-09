local E = require("evaluation")
local K = {}
K.__index = K
function K.new(words)
    return setmetatable({ name = words[2], kind = words[3], degree = tonumber(words[4]),
        gamma = tonumber(words[words[3] == "poly" and 5 or 4]), coef0 = tonumber(words[6]) }, K)
end
function K:value(a, b)
    if self.kind == "rbf" then
        local e1, e2 = a[1] - b[1], a[2] - b[2]
        return math.exp(-self.gamma * (e1 * e1 + e2 * e2))
    end
    local dot = a[1] * b[1] + a[2] * b[2]
    if self.kind == "linear" then return dot end
    local factor, value = self.gamma * dot + self.coef0, 1.0
    for _ = 1, self.degree do value = value * factor end
    return value
end
function K:description()
    if self.kind == "linear" then return "linear" end
    if self.kind == "rbf" then return "rbf gamma " .. E.fixed(self.gamma) end
    return "poly degree " .. self.degree .. " gamma " .. E.fixed(self.gamma) .. " coef0 " .. E.fixed(self.coef0)
end
function K:matrix(points)
    local result = {}
    for i, a in ipairs(points) do
        local row = {}
        for j, b in ipairs(points) do row[j] = self:value(a, b) end
        result[i] = row
    end
    return result
end
function K.submatrix(matrix, indices)
    local result = {}
    for i, a in ipairs(indices) do
        local row = {}
        for j, b in ipairs(indices) do row[j] = matrix[a][b] end
        result[i] = row
    end
    return result
end
return K
