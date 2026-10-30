local E = {}
function E.real(value, places)
    local text = string.format("%." .. places .. "f", value)
    return text:sub(1, 1) == "-" and tonumber(text) == 0 and text:sub(2) or text
end
function E.ratio(a, b)
    if b == 0 then return "-" end
    local q = (20000 * a + b) // (2 * b)
    return string.format("%d.%04d", q // 10000, q % 10000)
end
function E.best_two(scores)
    local order = {}
    for i = 1, #scores do order[i] = i end
    table.sort(order, function(a, b) return scores[a] > scores[b] or scores[a] == scores[b] and a < b end)
    return order[1] - 1, order[2] - 1
end
function E.confusion(outcomes, classes)
    local result = {}
    for i = 1, classes do result[i] = {}; for j = 1, classes do result[i][j] = 0 end end
    for _, outcome in ipairs(outcomes) do local row = result[outcome.label + 1]; row[outcome.predicted + 1] = row[outcome.predicted + 1] + 1 end
    return result
end
function E.class_measures(matrix, class)
    local support, predicted = 0, 0
    for i = 1, #matrix do support, predicted = support + matrix[class + 1][i], predicted + matrix[i][class + 1] end
    local true_count = matrix[class + 1][class + 1]
    return support, predicted, E.ratio(true_count, predicted), E.ratio(true_count, support), E.ratio(2 * true_count, support + predicted)
end
function E.level_maps(levels, width, height)
    local result = {}
    for row = 0, height - 1 do
        local parts = {}
        for class, values in ipairs(levels) do parts[class] = table.concat(values, "", row * width + 1, (row + 1) * width) end
        result[#result + 1] = table.concat(parts, " ")
    end
    return result
end
function E.image(pixels, width)
    local lines = {}
    for i = 1, #pixels, width do lines[#lines + 1] = pixels:sub(i, i + width - 1):gsub("0", "."):gsub("1", "#") end
    return lines
end
return E
