local resampling = require("resampling")
local M = {}

function M.position_choices(total, size)
    local choice, first, finished = {}, true, false
    for index = 1, size do choice[index] = index end
    return function()
        if finished then return nil end
        if first then first = false
        else
            local index = size
            while index > 0 and choice[index] == total - size + index do index = index - 1 end
            if index == 0 then finished = true; return nil end
            choice[index] = choice[index] + 1
            for next_index = index + 1, size do choice[next_index] = choice[next_index - 1] + 1 end
        end
        local result = {}
        for index, value in ipairs(choice) do result[index] = value end
        return result
    end
end

function M.reduced_fraction(a, b)
    local x, y = math.abs(a), b
    while y ~= 0 do x, y = y, x % y end
    return a // x, b // x
end

function M.contrast(x, y)
    return #y * resampling.sum(x) - #x * resampling.sum(y)
end

function M.value_counts(values)
    local ordered, result = resampling.sorted(values), {}
    for _, value in ipairs(ordered) do
        if #result > 0 and result[#result][1] == value then result[#result][2] = result[#result][2] + 1
        else result[#result + 1] = {value, 1} end
    end
    return result
end

function M.doubled_ranks(values)
    local ranks, smaller, result = {}, 0, {}
    for _, item in ipairs(M.value_counts(values)) do
        ranks[item[1]] = 2 * smaller + item[2] + 1
        smaller = smaller + item[2]
    end
    for _, value in ipairs(values) do result[#result + 1] = ranks[value] end
    return result
end

function M.split_list(values, sizes)
    local result, offset = {}, 0
    for _, size in ipairs(sizes) do
        local part = {}
        for index = 1, size do part[index] = values[offset + index] end
        result[#result + 1], offset = part, offset + size
    end
    return result
end

function M.anova(samples)
    local count, total, means = 0, 0, {}
    for _, sample in ipairs(samples) do count, total = count + #sample, total + resampling.sum(sample) end
    local grand = total / (100 * count)
    local between, within = 0.0, 0.0
    for _, sample in ipairs(samples) do
        local center = resampling.mean(sample)
        means[#means + 1] = center
        local difference = center - grand
        between = between + #sample * (difference * difference)
        local squares = 0.0
        for _, value in ipairs(sample) do
            local e = value / 100 - center
            squares = squares + e * e
        end
        within = within + squares
    end
    return {count = count, means = means, ssb = between, ssw = within,
        f = between / (#samples - 1) / (within / (count - #samples))}
end

function M.kruskal(rank_groups, correction)
    local total, count = 0.0, 0
    for _, ranks in ipairs(rank_groups) do
        local rank = resampling.sum(ranks)
        total, count = total + rank * rank / (4 * #ranks), count + #ranks
    end
    return (12 * total / (count * (count + 1)) - 3 * (count + 1)) / correction
end

return M
