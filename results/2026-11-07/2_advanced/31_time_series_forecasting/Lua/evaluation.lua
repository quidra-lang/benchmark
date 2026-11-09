local decomposition = require("decomposition")
local M = {}
function M.seasonal_scale(values, season)
    local total = 0.0
    for t = season + 1, #values do
        total = total + math.abs(values[t] - values[t - season])
    end
    return total / (#values - season)
end
function M.accuracy(actual, predicted, scale)
    local total, absolute, squared, percentage, symmetric = 0.0, 0.0, 0.0, 0.0, 0.0
    for i, observed in ipairs(actual) do
        local error, forecast = observed - predicted[i], predicted[i]
        total, absolute, squared = total + error, absolute + math.abs(error), squared + error * error
        percentage = percentage + math.abs(error) / observed
        symmetric = symmetric + 2.0 * math.abs(error) / (math.abs(observed) + math.abs(forecast))
    end
    local mae = absolute / #actual
    return {me = total / #actual, mae = mae, rmse = math.sqrt(squared / #actual), mape = 100.0 * percentage / #actual, smape = 100.0 * symmetric / #actual, mase = mae / scale}
end
function M.winkler(actual, low, high, multiplier)
    if actual < low then
        return high - low + multiplier * (low - actual)
    end
    if actual > high then
        return high - low + multiplier * (actual - high)
    end
    return high - low
end
function M.rank_models(names, measures)
    local indices = {}
    for i = 1, #names do
        indices[i] = i
    end
    table.sort(indices, function(a, b)
        return measures[names[a]].rmse < measures[names[b]].rmse or measures[names[a]].rmse == measures[names[b]].rmse and a < b
    end)
    local order = {}
    for i, index in ipairs(indices) do
        order[i] = names[index]
    end
    return order
end
return M
