local decomposition = require("decomposition")
local M = {kinds = {"none", "first", "seasonal", "both"}}
function M.difference(values, season, kind)
    if kind == "none" then
        return {table.unpack(values)}, 0
    end
    local result, offset = {}, kind == "first" and 1 or kind == "seasonal" and season or season + 1
    for t = offset + 1, #values do
        result[#result + 1] = kind == "first" and values[t] - values[t - 1] or kind == "seasonal" and values[t] - values[t - season] or (values[t] - values[t - 1]) - (values[t - season] - values[t - season - 1])
    end
    return result, offset
end
function M.autocorrelation(values, max_lag)
    local mean, centered, variance = decomposition.mean(values), {}, 0.0
    for i, value in ipairs(values) do
        centered[i] = value - mean
        variance = variance + centered[i] * centered[i]
    end
    variance = variance / #values
    local correlations = {1.0}
    for lag = 1, max_lag do
        local numerator = 0.0
        for i = 1, #values - lag do
            numerator = numerator + centered[i] * centered[i + lag]
        end
        correlations[lag + 1] = numerator / #values / variance
    end
    return mean, variance, correlations
end
function M.durbin_levinson(correlations)
    local coefficients, partial, variances = {{}}, {0.0}, {1.0}
    for order = 1, #correlations - 1 do
        local previous, correction = coefficients[#coefficients], 0.0
        for j = 1, order - 1 do
            correction = correction + previous[j] * correlations[order - j + 1]
        end
        local theta = (correlations[order + 1] - correction) / variances[#variances]
        local current = {}
        for j = 1, order - 1 do
            current[j] = previous[j] - theta * previous[order - j]
        end
        current[order] = theta
        coefficients[order + 1], partial[order + 1], variances[order + 1] = current, theta, variances[#variances] * (1.0 - theta * theta)
    end
    return coefficients, partial, variances
end
function M.residuals(values, mean, coefficients)
    local errors = {}
    for i = #coefficients + 1, #values do
        local total = 0.0
        for j, coefficient in ipairs(coefficients) do
            total = total + coefficient * (values[i - j] - mean)
        end
        errors[#errors + 1] = values[i] - mean - total
    end
    return errors
end
function M.forecast(values, differenced, offset, kind, mean, coefficients, origin, steps, season)
    local transformed, extended, result = {table.unpack(differenced, 1, origin - offset)}, {table.unpack(values, 1, origin)}, {}
    for step = 1, steps do
        local total = 0.0
        for j, coefficient in ipairs(coefficients) do
            total = total + coefficient * (transformed[#transformed + 1 - j] - mean)
        end
        local predicted = mean + total
        transformed[#transformed + 1] = predicted
        if kind == "first" then
            predicted = predicted + extended[#extended]
        elseif kind == "seasonal" then
            predicted = predicted + extended[#extended - season + 1]
        elseif kind == "both" then
            predicted = predicted + extended[#extended] + extended[#extended - season + 1] - extended[#extended - season]
        end
        extended[#extended + 1], result[step] = predicted, predicted
    end
    return result
end
function M.ljung_box(errors, lags)
    local _, _, correlations = M.autocorrelation(errors, math.max(table.unpack(lags)))
    local result = {}
    for _, lag in ipairs(lags) do
        local total = 0.0
        for k = 1, lag do
            total = total + correlations[k + 1] * correlations[k + 1] / (#errors - k)
        end
        local q = #errors * (#errors + 2) * total
        local x, term, sum = q / 2.0, 1.0, 1.0
        for i = 1, lag // 2 - 1 do
            term = term * x / i
            sum = sum + term
        end
        result[#result + 1] = {lag = lag, q = q, probability = math.exp(-x) * sum}
    end
    return result
end
return M
