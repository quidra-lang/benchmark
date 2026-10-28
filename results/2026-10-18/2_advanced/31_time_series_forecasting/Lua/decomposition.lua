local M = {}
function M.total(values)
    local total = 0.0
    for _, value in ipairs(values) do
        total = total + value
    end
    return total
end
function M.mean(values)
    return M.total(values) / #values
end
function M.sample_variance(values)
    local mean, total = M.mean(values), 0.0
    for _, value in ipairs(values) do
        total = total + (value - mean) * (value - mean)
    end
    return total / (#values - 1)
end
function M.decompose(values, season)
    local count, half = #values, season // 2
    local result = {trend = {}, additive = {}, multiplicative = {}, residual_add = {}, residual_mult = {}, defined = {}}
    for i = 1, count do
        result.trend[i], result.residual_add[i], result.residual_mult[i] = false, false, false
    end
    for t = half + 1, count - half do
        local value = 0.5 * values[t - half]
        for i = t - half + 1, t + half - 1 do
            value = value + values[i]
        end
        value = value + 0.5 * values[t + half]
        result.trend[t], result.defined[#result.defined + 1] = value / season, t
    end
    for position = 0, season - 1 do
        local additive, multiplicative = {}, {}
        for _, t in ipairs(result.defined) do
            if (t - 1) % season == position then
                additive[#additive + 1], multiplicative[#multiplicative + 1] = values[t] - result.trend[t], values[t] / result.trend[t]
            end
        end
        result.additive[position + 1], result.multiplicative[position + 1] = M.mean(additive), M.mean(multiplicative)
    end
    local average_add, average_mult = M.total(result.additive) / season, M.total(result.multiplicative) / season
    for j = 1, season do
        result.additive[j], result.multiplicative[j] = result.additive[j] - average_add, result.multiplicative[j] / average_mult
    end
    for _, t in ipairs(result.defined) do
        local position = (t - 1) % season + 1
        result.residual_add[t] = values[t] - result.trend[t] - result.additive[position]
        result.residual_mult[t] = values[t] / (result.trend[t] * result.multiplicative[position])
    end
    return result
end
function M.least_squares_line(values)
    local center, average = (#values + 1) / 2.0, M.mean(values)
    local numerator, denominator = 0.0, 0.0
    for t, value in ipairs(values) do
        numerator, denominator = numerator + (t - center) * (value - average), denominator + (t - center) * (t - center)
    end
    local slope = numerator / denominator
    return average - slope * center, slope
end
return M
