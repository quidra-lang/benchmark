local M = {}
function M.output(stump, values)
    local bin = 1
    for _, threshold in ipairs(stump.thresholds) do
        if values[stump.feature] > threshold then
            bin = bin + 1
        end
    end
    return stump.values[bin]
end
function M.prepare(rows)
    local result = {}
    for j = 1, #rows[1].values do
        local order = {}
        for i = 1, #rows do
            order[i] = i
        end
        table.sort(order, function(a, b)
            if rows[a].values[j] ~= rows[b].values[j] then
                return rows[a].values[j] < rows[b].values[j]
            end
            return a < b
        end)
        local distinct, batches = {}, {}
        for _, i in ipairs(order) do
            local value = rows[i].values[j]
            if #distinct == 0 or value ~= distinct[#distinct] then
                distinct[#distinct + 1] = value
                batches[#batches + 1] = {}
            end
            local batch = batches[#batches]
            batch[#batch + 1] = i
        end
        local thresholds = {distinct[1] - 1.0}
        for i = 1, #distinct - 1 do
            thresholds[#thresholds + 1] = (distinct[i] + distinct[i + 1]) / 2.0
        end
        result[j] = {order = order, distinct = distinct, batches = batches, thresholds = thresholds}
    end
    return result
end
function M.choose(candidates)
    local minimum = candidates[1].error
    for i = 2, #candidates do
        minimum = math.min(minimum, candidates[i].error)
    end
    for _, candidate in ipairs(candidates) do
        if candidate.error <= minimum + 0.000000001 then
            return candidate
        end
    end
end
function M.discrete(rows, weights, prepared)
    local positive, negative = 0.0, 0.0
    for i, row in ipairs(rows) do
        if row.label == 1 then
            positive = positive + weights[i]
        else
            negative = negative + weights[i]
        end
    end
    local candidates = {}
    for j, feature in ipairs(prepared) do
        local left_positive, left_negative = 0.0, 0.0
        for k, threshold in ipairs(feature.thresholds) do
            if k > 1 then
                for _, i in ipairs(feature.batches[k - 1]) do
                    if rows[i].label == 1 then
                        left_positive = left_positive + weights[i]
                    else
                        left_negative = left_negative + weights[i]
                    end
                end
            end
            candidates[#candidates + 1] = {feature = j, threshold = threshold, polarity = 1,
                error = left_positive + (negative - left_negative)}
            candidates[#candidates + 1] = {feature = j, threshold = threshold, polarity = -1,
                error = left_negative + (positive - left_positive)}
        end
    end
    return M.choose(candidates)
end
function M.regression(rows, targets, weights, prepared)
    local total_weight, total_target, total_square = 0.0, 0.0, 0.0
    for i = 1, #rows do
        total_weight = total_weight + weights[i]
        total_target = total_target + weights[i] * targets[i]
        total_square = total_square + weights[i] * targets[i] * targets[i]
    end
    local candidates = {}
    for j, feature in ipairs(prepared) do
        local left_weight, left_target = 0.0, 0.0
        for k, threshold in ipairs(feature.thresholds) do
            if k > 1 then
                for _, i in ipairs(feature.batches[k - 1]) do
                    left_weight = left_weight + weights[i]
                    left_target = left_target + weights[i] * targets[i]
                end
            end
            local right_weight, right_target = total_weight - left_weight, total_target - left_target
            local left, gain = 0.0, right_target * right_target / right_weight
            if k > 1 then
                left = left_target / left_weight
                gain = left_target * left_target / left_weight + right_target * right_target / right_weight
            end
            local right = right_target / right_weight
            candidates[#candidates + 1] = {feature = j, error = total_square - gain,
                stump = {feature = j, thresholds = {threshold}, values = {left, right}}}
        end
    end
    return M.choose(candidates)
end
local function largest(values)
    local result = 1
    for i = 2, #values do
        if values[i] > values[result] then
            result = i
        end
    end
    return result
end
function M.multiclass(rows, weights, prepared, classes)
    local total, class_weights = 0.0, {}
    for class = 1, classes do
        class_weights[class] = 0.0
    end
    for i, row in ipairs(rows) do
        total = total + weights[i]
        class_weights[row.label] = class_weights[row.label] + weights[i]
    end
    local candidates = {}
    for j, feature in ipairs(prepared) do
        local left = {}
        for class = 1, classes do
            left[class] = 0.0
        end
        for k, threshold in ipairs(feature.thresholds) do
            if k > 1 then
                for _, i in ipairs(feature.batches[k - 1]) do
                    local class = rows[i].label
                    left[class] = left[class] + weights[i]
                end
            end
            local right = {}
            for class = 1, classes do
                right[class] = class_weights[class] - left[class]
            end
            local a, b = largest(left), largest(right)
            candidates[#candidates + 1] = {feature = j, error = total - (left[a] + right[b]),
                stump = {feature = j, thresholds = {threshold}, values = {a, b}}}
        end
    end
    return M.choose(candidates)
end
function M.cuts(rows, prepared, bins)
    local result = {}
    for j, feature in ipairs(prepared) do
        local cuts = {}
        for b = 1, bins - 1 do
            local rank = b * #rows // bins
            cuts[#cuts + 1] = (rows[feature.order[rank]].values[j] + rows[feature.order[rank + 1]].values[j]) / 2.0
        end
        result[j] = cuts
    end
    return result
end
function M.real_candidates(rows, weights, cuts, bins)
    local result = {}
    for j, thresholds in ipairs(cuts) do
        local positive, negative = {}, {}
        for bin = 1, bins do
            positive[bin], negative[bin] = 0.0, 0.0
        end
        for i, row in ipairs(rows) do
            local bin = 1
            for _, cut in ipairs(thresholds) do
                if row.values[j] > cut then
                    bin = bin + 1
                end
            end
            if row.label == 1 then
                positive[bin] = positive[bin] + weights[i]
            else
                negative[bin] = negative[bin] + weights[i]
            end
        end
        local sum = 0.0
        for bin = 1, bins do
            sum = sum + math.sqrt(positive[bin] * negative[bin])
        end
        result[j] = {feature = j, positive = positive, negative = negative, error = 2.0 * sum}
    end
    return result
end
return M
