local M = {}
function M.fixed(value, places)
    local text = string.format("%." .. places .. "f", value)
    if text:sub(1, 1) == "-" and tonumber(text) == 0 then
        text = text:sub(2)
    end
    return text
end
function M.ratio(numerator, denominator)
    if denominator == 0 then
        return "-"
    end
    local rounded = (20000 * numerator + denominator) // (2 * denominator)
    return string.format("%d.%04d", rounded // 10000, rounded % 10000)
end
function M.fraction(numerator, denominator)
    local a, b = numerator, denominator
    while b ~= 0 do
        a, b = b, a % b
    end
    return numerator // a .. "/" .. denominator // a .. " " .. M.ratio(numerator, denominator)
end
function M.confusion(predictions, targets)
    local matrix = {tp = 0, fp = 0, tn = 0, fn = 0}
    for i, prediction in ipairs(predictions) do
        if prediction == 1 and targets[i] == 1 then
            matrix.tp = matrix.tp + 1
        elseif prediction == 1 then
            matrix.fp = matrix.fp + 1
        elseif targets[i] == 0 then
            matrix.tn = matrix.tn + 1
        else
            matrix.fn = matrix.fn + 1
        end
    end
    return matrix
end
function M.auc(scores, targets)
    local order, positives = {}, 0
    for i, target in ipairs(targets) do
        order[i], positives = i, positives + target
    end
    table.sort(order, function(a, b)
        return scores[a] < scores[b] or scores[a] == scores[b] and a < b
    end)
    local rank_sum, start = 0, 1
    while start <= #order do
        local finish = start
        while finish + 1 <= #order and scores[order[finish + 1]] == scores[order[start]] do
            finish = finish + 1
        end
        for position = start, finish do
            if targets[order[position]] == 1 then
                rank_sum = rank_sum + start + finish
            end
        end
        start = finish + 1
    end
    return rank_sum - positives * (positives + 1), 2 * positives * (#targets - positives)
end
function M.roc_points(probabilities, targets)
    local order, points, tp, fp = {}, {}, 0, 0
    for i = 1, #probabilities do
        order[i] = i
    end
    table.sort(order, function(a, b)
        return probabilities[a] > probabilities[b] or probabilities[a] == probabilities[b] and a < b
    end)
    for position, i in ipairs(order) do
        if targets[i] == 1 then
            tp = tp + 1
        else
            fp = fp + 1
        end
        if position == #order or probabilities[order[position + 1]] ~= probabilities[i] then
            points[#points + 1] = {threshold = probabilities[i], tp = tp, fp = fp}
        end
    end
    return points
end
return M
