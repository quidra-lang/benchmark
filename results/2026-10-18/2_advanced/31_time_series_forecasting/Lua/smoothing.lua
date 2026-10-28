local decomposition = require("decomposition")
local M = {}
function M.recurse(name, values, season, parameters)
    local alpha, beta, phi, gamma = parameters.alpha, parameters.beta or 0.0, parameters.phi or 1.0, parameters.gamma or 0.0
    local seasonal = name == "hw_add" or name == "hw_mult"
    local level, slope, components = values[1], 0.0, {}
    if seasonal then
        local first, second = {}, {}
        for i = 1, season do
            first[i], second[i] = values[i], values[season + i]
        end
        level = decomposition.total(first) / season
        slope = (decomposition.total(second) / season - level) / season
        for j = 1, season do
            components[j] = name == "hw_add" and values[j] - level or values[j] / level
        end
    elseif name ~= "ses" then
        slope = (values[season + 1] - values[1]) / season
    end
    local states, errors = {}, {}
    for t, observed in ipairs(values) do
        states[t] = {level = level, slope = slope, components = {table.unpack(components)}}
        local predicted, next_level, next_slope
        if name == "ses" then
            predicted, next_level, next_slope = level, alpha * observed + (1.0 - alpha) * level, slope
        elseif seasonal then
            local position, base = (t - 1) % season + 1, level + slope
            local previous = components[position]
            if name == "hw_add" then
                predicted, next_level = base + previous, alpha * (observed - previous) + (1.0 - alpha) * base
                components[position] = gamma * (observed - base) + (1.0 - gamma) * previous
            else
                predicted, next_level = base * previous, alpha * (observed / previous) + (1.0 - alpha) * base
                components[position] = gamma * (observed / base) + (1.0 - gamma) * previous
            end
            next_slope = beta * (next_level - level) + (1.0 - beta) * slope
        else
            predicted = level + phi * slope
            next_level = alpha * observed + (1.0 - alpha) * predicted
            next_slope = beta * (next_level - level) + (1.0 - beta) * phi * slope
        end
        errors[t], level, slope = observed - predicted, next_level, next_slope
    end
    states[#values + 1] = {level = level, slope = slope, components = {table.unpack(components)}}
    return errors, states
end
function M.forecast(name, state, parameters, origin, steps, season)
    local result = {}
    if name == "ses" then
        for i = 1, steps do
            result[i] = state.level
        end
        return result
    end
    if name == "holt" or name == "damped" then
        local phi, power, accumulated = parameters.phi or 1.0, parameters.phi or 1.0, 0.0
        for i = 1, steps do
            accumulated = accumulated + power
            result[i] = state.level + accumulated * state.slope
            power = power * phi
        end
    else
        for step = 1, steps do
            local component, base = state.components[(origin + step - 1) % season + 1], state.level + step * state.slope
            result[step] = name == "hw_add" and base + component or base * component
        end
    end
    return result
end
return M
