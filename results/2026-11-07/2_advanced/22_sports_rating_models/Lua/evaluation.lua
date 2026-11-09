local report = require("report")
local Fraction = report.Fraction
local M = {}

function M.sigma(value) return 1 / (1 + math.exp(-value)) end
function M.fit_link(features, results, iterations)
    local alpha, beta = 0.0, 0.0
    for _ = 1, iterations do
        local g0, g1, h00, h01, h11 = 0.0, 0.0, 0.0, 0.0, 0.0
        for index, z in ipairs(features) do
            local p = M.sigma(alpha + beta * z)
            local w, delta = p * (1 - p), results[index] - p
            g0, g1, h00, h01, h11 = g0 + delta, g1 + delta * z, h00 + w, h01 + w * z, h11 + w * z * z
        end
        local determinant = h00 * h11 - h01 * h01
        alpha, beta = alpha + (h11 * g0 - h01 * g1) / determinant, beta + (h00 * g1 - h01 * g0) / determinant
    end
    return alpha, beta
end
function M.log_loss(p, y)
    if y == 1 then return -math.log(p) end
    if y == 0 then return -math.log(1 - p) end
    return -(math.log(p) / 2 + math.log(1 - p) / 2)
end
function M.brier_score(p, y) return (p - y) * (p - y) end
function M.correctness2(p, y)
    if y == 0.5 then return 1 end
    return (p > 0.5 and y == 1 or p < 0.5 and y == 0) and 2 or 0
end
function M.average_ranks2(values)
    local ranks = {}
    for i, value in ipairs(values) do
        local greater, equal = 0, 0
        for _, other in ipairs(values) do
            local order = report.compare(other, value)
            if order > 0 then greater = greater + 1 elseif order == 0 then equal = equal + 1 end
        end
        ranks[i] = 2 * greater + equal + 1
    end
    return ranks
end
function M.kendall_tau(first, second)
    local count, numerator = #first, 0
    for i = 1, count do
        for j = i + 1, count do numerator = numerator + report.compare(first[i], first[j]) * report.compare(second[i], second[j]) end
    end
    return Fraction.new(numerator, count * (count - 1) // 2)
end
function M.spearman_rho(first, second)
    local a, b, squares, count = M.average_ranks2(first), M.average_ranks2(second), 0, #first
    for i = 1, count do local difference = a[i] - b[i] squares = squares + difference * difference end
    local denominator = 4 * count * (count * count - 1)
    return Fraction.new(denominator - 6 * squares, denominator)
end

return M
