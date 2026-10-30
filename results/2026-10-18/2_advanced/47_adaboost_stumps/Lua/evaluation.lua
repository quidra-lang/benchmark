local M = {}
function M.real(value, digits)
    if value == nil then
        return "-"
    end
    local result = string.format("%." .. (digits or 4) .. "f", value)
    if tonumber(result) == 0 then
        result = result:gsub("^-", "")
    end
    return result
end
function M.ratio(first, second)
    return second ~= 0 and M.real(first / second) or "-"
end
function M.sign(value)
    return value > 0.0 and 1 or -1
end
function M.auc(labels, scores)
    local positives, negatives, wins, ties = 0, 0, 0, 0
    for i, label in ipairs(labels) do
        if label == 1 then
            positives = positives + 1
            for j, other in ipairs(labels) do
                if other == -1 then
                    if scores[i] > scores[j] then
                        wins = wins + 1
                    elseif scores[i] == scores[j] then
                        ties = ties + 1
                    end
                end
            end
        else
            negatives = negatives + 1
        end
    end
    return 2 * wins + ties, 2 * positives * negatives
end
function M.confusion(actual, predicted, classes)
    local result = {}
    for class = 1, classes do
        result[class] = {}
        for other = 1, classes do
            result[class][other] = 0
        end
    end
    for i, class in ipairs(actual) do
        result[class][predicted[i]] = result[class][predicted[i]] + 1
    end
    return result
end
function M.count_margin(values, threshold)
    local result = 0
    for _, value in ipairs(values) do
        result = result + (value <= threshold and 1 or 0)
    end
    return result
end
function M.save(name, lines)
    local file = assert(io.open("output/" .. name, "w"))
    for _, line in ipairs(lines) do
        file:write(line, "\n")
    end
    file:close()
end
return M
