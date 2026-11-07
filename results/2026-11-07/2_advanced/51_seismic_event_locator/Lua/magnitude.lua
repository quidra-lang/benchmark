local M = {}
function M.log10(value)
    return math.log(value) / 2.302585092994046
end
function M.median(values)
    local ordered = {table.unpack(values)}
    table.sort(ordered)
    local middle = #ordered // 2
    return #ordered % 2 == 1 and ordered[middle + 1] or (ordered[middle] + ordered[middle + 1]) / 2.0
end
function M.per_pick(pick, radius, params)
    local local_coefficients, duration_coefficients = params.local_magnitude, params.duration_magnitude
    local result = {r = radius, md = duration_coefficients[1] + duration_coefficients[2] * M.log10(pick.duration / 100.0) + duration_coefficients[3] * radius}
    if not pick.clipped then
        result.ml = M.log10(pick.amplitude + 0.0) + local_coefficients[1] * M.log10(radius / 100.0) +
            local_coefficients[2] * (radius - 100.0) + local_coefficients[3]
    end
    return result
end
function M.class_number(value)
    local hundredths = math.floor(math.abs(value) * 100.0 + 0.5)
    if value < 0.0 then
        hundredths = -hundredths
    end
    return (hundredths + 5) // 10
end
function M.class_text(value)
    local absolute = math.abs(value)
    return (value < 0 and "-" or "") .. absolute // 10 .. "." .. absolute % 10
end
function M.frequency(values)
    local counts, classes, low, high = {}, {}, nil, nil
    for _, value in ipairs(values) do
        local class = M.class_number(value)
        classes[#classes + 1] = class
        counts[class] = (counts[class] or 0) + 1
        low, high = low and math.min(low, class) or class, high and math.max(high, class) or class
    end
    local completeness, greatest = low, -1
    for class = low, high do
        if (counts[class] or 0) > greatest then
            completeness, greatest = class, counts[class] or 0
        end
    end
    local sum, n = 0, 0
    for _, class in ipairs(classes) do
        if class >= completeness then
            sum, n = sum + class, n + 1
        end
    end
    local mc, mean = completeness / 10.0, sum / (10.0 * n)
    local b = 0.4342944819032518 / (mean - (mc - 0.05))
    return {counts = counts, low = low, high = high, completeness = completeness, n = n,
        b = b, sigma = b / math.sqrt(n + 0.0), a = M.log10(n + 0.0) + b * mc}
end
return M
