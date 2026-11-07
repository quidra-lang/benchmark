local M = {}

function M.sum(values)
    local total = 0
    for _, value in ipairs(values) do total = total + value end
    return total
end

function M.float_sum(values)
    local total = 0.0
    for _, value in ipairs(values) do total = total + value end
    return total
end

function M.sorted(values)
    local result = {}
    for _, value in ipairs(values) do result[#result + 1] = value end
    table.sort(result)
    return result
end

function M.mean(values)
    return M.sum(values) / (100 * #values)
end

function M.doubled_median(values)
    local ordered = M.sorted(values)
    return ordered[(#ordered + 1) // 2] + ordered[(#ordered + 2) // 2]
end

function M.median(values)
    return M.doubled_median(values) / 200
end

function M.trimmed_mean(values)
    local ordered, total = M.sorted(values), 0
    local trim = #values // 10
    for index = trim + 1, #values - trim do total = total + ordered[index] end
    return total / (100 * (#values - 2 * trim))
end

function M.moments(values)
    local center = M.mean(values)
    local second, third, fourth = 0.0, 0.0, 0.0
    for _, value in ipairs(values) do
        local e = value / 100 - center
        second = second + e * e
        third = third + e * e * e
        fourth = fourth + e * e * e * e
    end
    return {sd = math.sqrt(second / (#values - 1)), m2 = second / #values, m3 = third / #values, m4 = fourth / #values}
end

function M.sd(values)
    return M.moments(values).sd
end

function M.mad(values)
    local center, deviations = M.doubled_median(values), {}
    for _, value in ipairs(values) do deviations[#deviations + 1] = math.abs(2 * value - center) end
    return M.doubled_median(deviations) / 400
end

function M.quantile_numerator(values, percent)
    local ordered = M.sorted(values)
    local position = (#values - 1) * percent
    local index = position // 100 + 1
    local fraction = position % 100
    local value = 100 * ordered[index]
    if fraction ~= 0 then value = value + fraction * (ordered[index + 1] - ordered[index]) end
    return value
end

function M.winsorized(values)
    local ordered, result = M.sorted(values), {}
    local trim = #values // 10
    local low, high = ordered[trim + 1], ordered[#values - trim]
    for _, value in ipairs(values) do result[#result + 1] = math.min(math.max(value, low), high) end
    return result
end

function M.mean_difference(x, y)
    return (#y * M.sum(x) - #x * M.sum(y)) / (100 * #x * #y)
end

function M.median_ratio(x, y)
    return M.doubled_median(x) / M.doubled_median(y)
end

function M.hodges_lehmann(x, y)
    local differences = {}
    for _, first in ipairs(x) do
        for _, second in ipairs(y) do differences[#differences + 1] = first - second end
    end
    return M.doubled_median(differences) / 200
end

function M.pooled_sd(x, y)
    local sx, sy = M.sd(x), M.sd(y)
    return math.sqrt(((#x - 1) * sx * sx + (#y - 1) * sy * sy) / (#x + #y - 2))
end

function M.cohen_d(x, y)
    return M.mean_difference(x, y) / M.pooled_sd(x, y)
end

function M.correlation(x, y)
    local mx, my = M.mean(x), M.mean(y)
    local products, first, second = 0.0, 0.0, 0.0
    for index = 1, #x do
        local e, f = x[index] / 100 - mx, y[index] / 100 - my
        products, first, second = products + e * f, first + e * e, second + f * f
    end
    return products / math.sqrt(first * second)
end

function M.statistics(sample)
    return {M.mean(sample), M.median(sample), M.trimmed_mean(sample), M.sd(sample)}
end

function M.pair_statistics(x, y)
    return {M.mean_difference(x, y), M.median_ratio(x, y), M.hodges_lehmann(x, y), M.cohen_d(x, y)}
end

function M.resample_indices(generator, size)
    local indices = {}
    for _ = 1, size do indices[#indices + 1] = generator:below(size) + 1 end
    return indices
end

function M.ordinary_indices(generator, size, count)
    local result = {}
    for _ = 1, count do result[#result + 1] = M.resample_indices(generator, size) end
    return result
end

function M.balanced_indices(generator, size, count)
    local sequence, result = {}, {}
    for _ = 1, count do
        for index = 1, size do sequence[#sequence + 1] = index end
    end
    generator:shuffle(sequence)
    for replicate = 1, count do
        local indices = {}
        for index = 1, size do indices[index] = sequence[(replicate - 1) * size + index] end
        result[#result + 1] = indices
    end
    return result
end

function M.without(values, omitted)
    local result = {}
    for index, value in ipairs(values) do if index ~= omitted then result[#result + 1] = value end end
    return result
end

function M.mean_and_se(values)
    local average = M.float_sum(values) / #values
    local squares = 0.0
    for _, value in ipairs(values) do
        local e = value - average
        squares = squares + e * e
    end
    return average, math.sqrt(squares / (#values - 1))
end

function M.phi(x)
    if x < 0 then return 1 - M.phi(-x) end
    local eta = 1 / (1 + 0.2316419 * x)
    local psi = eta * (0.319381530 + eta * (-0.356563782 + eta * (1.781477937 + eta * (-1.821255978 + eta * 1.330274429))))
    return 1 - 0.3989422804014327 * math.exp(-(x * x) / 2) * psi
end

function M.phi_inverse(p)
    if p > 0.5 then return -M.phi_inverse(1 - p) end
    local eta = math.sqrt(-2 * math.log(p))
    return -(eta - (2.515517 + eta * (0.802853 + eta * 0.010328)) / (1 + eta * (1.432788 + eta * (0.189269 + eta * 0.001308))))
end

return M
