local E = {}
function E.sign(value) return value > 0 and 1 or -1 end
function E.fixed(value, decimals)
    local result = string.format("%." .. (decimals or 4) .. "f", value)
    if result:sub(1, 1) == "-" and tonumber(result) == 0 then result = result:sub(2) end
    return result
end
function E.ratio(a, b) return b > 0 and E.fixed(a / b) or "-" end
function E.folds(size, count)
    local result = {}
    for fold = 0, count - 1 do
        local training, testing = {}, {}
        for i = 1, size do
            local target = (i - 1) % count == fold and testing or training
            target[#target + 1] = i
        end
        result[#result + 1] = { training, testing }
    end
    return result
end
function E.correct(labels, values)
    local count = 0
    for i, label in ipairs(labels) do if label == E.sign(values[i]) then count = count + 1 end end
    return count
end
function E.binary_counts(labels, values)
    local tp, fp, tn, fn = 0, 0, 0, 0
    for i, label in ipairs(labels) do
        local prediction = E.sign(values[i])
        if label == 1 then if prediction == 1 then tp = tp + 1 else fn = fn + 1 end
        elseif prediction == 1 then fp = fp + 1 else tn = tn + 1 end
    end
    return tp, fp, tn, fn
end
function E.auc(labels, values)
    local positives, negatives, total = {}, {}, 0.0
    for i, label in ipairs(labels) do local target = label == 1 and positives or negatives; target[#target + 1] = i end
    for _, positive in ipairs(positives) do
        for _, negative in ipairs(negatives) do
            if values[positive] > values[negative] then total = total + 1.0 elseif values[positive] == values[negative] then total = total + 0.5 end
        end
    end
    return total / (#positives * #negatives)
end
function E.confusion(classes, predictions)
    local result = { { 0, 0, 0 }, { 0, 0, 0 }, { 0, 0, 0 } }
    for i, actual in ipairs(classes) do local row = result[actual]; row[predictions[i]] = row[predictions[i]] + 1 end
    return result
end
function E.confusion_lines(matrix)
    local lines = {}
    for _, row in ipairs(matrix) do lines[#lines + 1] = table.concat(row, " ") end
    for i = 1, 3 do
        local column, row = 0, 0
        for j = 1, 3 do column, row = column + matrix[j][i], row + matrix[i][j] end
        lines[#lines + 1] = "class " .. i .. " precision " .. E.ratio(matrix[i][i], column) .. " recall " .. E.ratio(matrix[i][i], row)
    end
    return lines
end
function E.write(path, lines)
    local output = assert(io.open(path, "w"))
    for _, line in ipairs(lines) do output:write(line, "\n") end
    output:close()
end
return E
