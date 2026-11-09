local report = require("report")
local M = {}
local function sum(values)
    local result = 0
    for _, value in ipairs(values) do
        result = result + value
    end
    return result
end
local function squares(values)
    local result = 0
    for _, value in ipairs(values) do
        result = result + value * value
    end
    return result
end
function M.root(p, q)
    local value, low, high = 40000 * p // q, 0, 1
    while high * high <= value do
        high = high * 2
    end
    while high - low > 1 do
        local middle = (low + high) // 2
        if middle * middle <= value then
            low = middle
        else
            high = middle
        end
    end
    return (low + 1) // 2
end
function M.statistics(rr, nn, pairs)
    local result = {rr_count = #rr, e = #nn, k = #pairs, nn50 = 0, histogram = {}, histogram_max = 0}
    if #rr > 0 then
        result.mean_rr = report.rdiv(100 * sum(rr), #rr)
        result.mean_hr = report.rdiv(6000000 * #rr, sum(rr))
        result.shortest, result.longest = 1, 1
        for index = 2, #rr do
            if rr[index] < rr[result.shortest] then
                result.shortest = index
            end
            if rr[index] > rr[result.longest] then
                result.longest = index
            end
        end
    end
    if #nn > 0 then
        result.mean_nn = report.rdiv(100 * sum(nn), #nn)
    end
    if #nn >= 2 then
        result.sdnn = M.root(#nn * squares(nn) - sum(nn) * sum(nn), #nn * (#nn - 1))
    end
    local differences, totals = {}, {}
    for index, pair in ipairs(pairs) do
        differences[index], totals[index] = pair[2] - pair[1], pair[1] + pair[2]
        if math.abs(differences[index]) > 50 then
            result.nn50 = result.nn50 + 1
        end
    end
    if #pairs > 0 then
        result.rmssd = M.root(squares(differences), #pairs)
        result.pnn50 = report.rdiv(10000 * result.nn50, #pairs)
    end
    if #pairs >= 2 then
        local numerator = #pairs * squares(differences) - sum(differences) * sum(differences)
        result.sdsd = M.root(numerator, #pairs * (#pairs - 1))
        result.sd1 = M.root(numerator, 2 * #pairs * (#pairs - 1))
        result.sd2 = M.root(#pairs * squares(totals) - sum(totals) * sum(totals), 2 * #pairs * (#pairs - 1))
    end
    for _, value in ipairs(nn) do
        local bucket = 16 * value // 125
        result.histogram[bucket] = (result.histogram[bucket] or 0) + 1
        result.histogram_max = math.max(result.histogram_max, result.histogram[bucket])
    end
    if #nn > 0 then
        result.triangular_index = report.rdiv(100 * #nn, result.histogram_max)
    end
    return result
end
function M.ranges(indices)
    local result = {}
    for _, index in ipairs(indices) do
        local last = result[#result]
        if last and index == last[2] + 1 then
            last[2] = index
        else
            result[#result + 1] = {index, index}
        end
    end
    return result
end
return M
