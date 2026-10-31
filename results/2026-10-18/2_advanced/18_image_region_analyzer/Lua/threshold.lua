local M = {}

function M.histogram(image)
    local result = {maxval = image.maxval, pixels = image.width * image.height,
        counts = {}, below_counts = {}, below_sums = {}, bins = {}}
    for value = 0, image.maxval do result.counts[value] = 0 end
    for _, row in ipairs(image.pixels) do
        for _, value in ipairs(row) do result.counts[value] = result.counts[value] + 1 end
    end
    local count, total, mode_count = 0, 0, -1
    result.levels = 0
    for value = 0, image.maxval do
        local frequency = result.counts[value]
        count, total = count + frequency, total + value * frequency
        result.below_counts[value], result.below_sums[value] = count, total
        if frequency > 0 then
            if result.minimum == nil then result.minimum = value end
            result.maximum, result.levels = value, result.levels + 1
        end
        if result.median == nil and 2 * count >= result.pixels then result.median = value end
        if frequency > mode_count then result.mode, mode_count = value, frequency end
    end
    result.total, result.bin_width = total, (image.maxval + 8) // 8
    for start = 0, image.maxval, result.bin_width do
        local frequency = 0
        for value = start, math.min(start + result.bin_width - 1, image.maxval) do
            frequency = frequency + result.counts[value]
        end
        result.bins[#result.bins + 1] = frequency
    end
    return result
end

function M.split(histogram, cutoff)
    local below, sum_below = histogram.below_counts[cutoff], histogram.below_sums[cutoff]
    return below, sum_below, histogram.pixels - below, histogram.total - sum_below
end

function M.compare_scores(first, second)
    local first_q, second_q = first.numerator // first.denominator, second.numerator // second.denominator
    if first_q ~= second_q then return first_q > second_q and 1 or -1 end
    local left = (first.numerator % first.denominator) * second.denominator
    local right = (second.numerator % second.denominator) * first.denominator
    if left == right then return 0 end
    return left > right and 1 or -1
end

function M.otsu(histogram)
    local candidates = {}
    for cutoff = 0, histogram.maxval - 1 do
        local below, sum_below, above, sum_above = M.split(histogram, cutoff)
        if histogram.counts[cutoff] > 0 and above > 0 then
            candidates[#candidates + 1] = {cutoff = cutoff, below = below, sum_below = sum_below,
                above = above, sum_above = sum_above,
                numerator = sum_below * sum_below * above + sum_above * sum_above * below,
                denominator = below * above}
        end
    end
    table.sort(candidates, function(first, second)
        local comparison = M.compare_scores(first, second)
        return comparison > 0 or comparison == 0 and first.cutoff < second.cutoff
    end)
    if #candidates == 0 then
        return {cutoff = histogram.minimum, upper = histogram.minimum, candidates = candidates}
    end
    local best, upper = candidates[1].cutoff, nil
    for value = best + 1, histogram.maxval do
        if histogram.counts[value] > 0 then upper = value - 1 break end
    end
    return {cutoff = best, upper = upper, candidates = candidates}
end

function M.isodata(histogram)
    local cutoff, iterations = histogram.total // histogram.pixels, 0
    while true do
        local below, sum_below, above, sum_above = M.split(histogram, cutoff)
        if below == 0 or above == 0 then break end
        local following = (sum_below * above + sum_above * below) // (2 * below * above)
        iterations = iterations + 1
        if following == cutoff then break end
        cutoff = following
        if iterations == 100 then break end
    end
    return cutoff, iterations
end

return M
