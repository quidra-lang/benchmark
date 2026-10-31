local M = {}
function M.copy(values)
    local result = {}
    for index, value in ipairs(values) do
        result[index] = type(value) == "table" and M.copy(value) or value
    end
    return result
end
function M.identity(size)
    local result = {}
    for i = 1, size do
        result[i] = {}
        for j = 1, size do
            result[i][j] = i == j and 1.0 or 0.0
        end
    end
    return result
end
function M.column(values, column)
    local result = {}
    for index, row in ipairs(values) do
        result[index] = row[column]
    end
    return result
end
function M.dot(first, second)
    local result = 0.0
    for index, value in ipairs(first) do
        result = result + value * second[index]
    end
    return result
end
function M.product(values, vector)
    local result = {}
    for index, row in ipairs(values) do
        result[index] = M.dot(row, vector)
    end
    return result
end
function M.length(vector)
    return math.sqrt(M.dot(vector, vector))
end
function M.normalize(vector)
    local length, result = M.length(vector), {}
    for index, value in ipairs(vector) do
        result[index] = value / length
    end
    return result
end
function M.orient(vector)
    local largest = 1
    for index = 2, #vector do
        if math.abs(vector[index]) > math.abs(vector[largest]) then
            largest = index
        end
    end
    local result = M.copy(vector)
    if vector[largest] < 0.0 then
        for index, value in ipairs(result) do
            result[index] = -value
        end
    end
    return result
end
function M.maximum_difference(first, second)
    local result = 0.0
    for index, value in ipairs(first) do
        result = math.max(result, math.abs(value - second[index]))
    end
    return result
end
function M.deflate(values, eigenvalue, vector)
    local result = M.copy(values)
    for i = 1, #values do
        for j = 1, #values do
            result[i][j] = values[i][j] - eigenvalue * vector[i] * vector[j]
        end
    end
    return result
end
function M.inverse_determinant(values)
    local size, work = #values, {}
    for i = 1, size do
        work[i] = M.copy(values[i])
        for j = 1, size do
            work[i][size + j] = i == j and 1.0 or 0.0
        end
    end
    local determinant = 1.0
    for k = 1, size do
        local pivot = work[k][k]
        determinant = determinant * pivot
        for h = 1, 2 * size do
            work[k][h] = work[k][h] / pivot
        end
        for i = 1, size do
            if i ~= k then
                local factor = work[i][k]
                for h = 1, 2 * size do
                    work[i][h] = work[i][h] - factor * work[k][h]
                end
            end
        end
    end
    local inverse = {}
    for i = 1, size do
        inverse[i] = {}
        for j = 1, size do
            inverse[i][j] = work[i][size + j]
        end
    end
    return inverse, determinant
end
return M
