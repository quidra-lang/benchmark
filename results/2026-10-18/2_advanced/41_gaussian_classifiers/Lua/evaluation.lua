local M = {}
function M.fraction(a, b)
    if b == 0 then
        return nil
    end
    local first, second = math.abs(a), b
    while second ~= 0 do
        first, second = second, first % second
    end
    return {a // first, b // first}
end
function M.sum_fractions(values)
    local result = {0, 1}
    for _, value in ipairs(values) do
        result = M.fraction(result[1] * value[2] + value[1] * result[2], result[2] * value[2])
    end
    return result
end
function M.measures(actual, predicted, count)
    local matrix, support, columns, recall, precision, f1 = {}, {}, {}, {}, {}, {}
    for a = 1, count do
        matrix[a], support[a], columns[a] = {}, 0, 0
        for b = 1, count do
            matrix[a][b] = 0
        end
    end
    for index, label in ipairs(actual) do
        matrix[label][predicted[index]] = matrix[label][predicted[index]] + 1
    end
    local correct, expected, macro = 0, 0, 0.0
    for a = 1, count do
        for b = 1, count do
            support[a], columns[b] = support[a] + matrix[a][b], columns[b] + matrix[a][b]
        end
        correct = correct + matrix[a][a]
    end
    for k = 1, count do
        recall[k], precision[k], f1[k] = M.fraction(matrix[k][k], support[k]), M.fraction(matrix[k][k], columns[k]), M.fraction(2 * matrix[k][k], support[k] + columns[k])
        expected = expected + support[k] * columns[k]
        macro = macro + 2 * matrix[k][k] / (support[k] + columns[k])
    end
    local total = M.sum_fractions(recall)
    return {matrix = matrix, support = support, correct = correct, accuracy = M.fraction(correct, #actual), balanced_accuracy = M.fraction(total[1], total[2] * count),
        kappa = M.fraction(#actual * correct - expected, #actual * #actual - expected), recall = recall, precision = precision, f1 = f1, macro_f1 = macro / count}
end
function M.mcnemar(actual, first, second)
    local b01, b10 = 0, 0
    for index, label in ipairs(actual) do
        if first[index] == label and second[index] ~= label then
            b01 = b01 + 1
        elseif first[index] ~= label and second[index] == label then
            b10 = b10 + 1
        end
    end
    local chi = 0.0
    if b01 ~= b10 then
        local difference = math.abs(b01 - b10) - 1
        chi = difference * difference / (b01 + b10)
    end
    return b01, b10, chi, chi > 3.841
end
function M.generator(seed)
    return function()
        seed = 48271 * seed % 2147483647
        return seed
    end
end
return M
