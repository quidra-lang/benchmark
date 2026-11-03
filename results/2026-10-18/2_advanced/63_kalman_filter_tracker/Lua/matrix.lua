local M = {}
function M.total(values) local result = 0.0; for _, value in ipairs(values) do result = result + value end; return result end
function M.zeros(rows, columns)
    local result = {}
    for i = 1, rows do result[i] = {}; for j = 1, columns or rows do result[i][j] = 0.0 end end
    return result
end
function M.diagonal(values)
    local result = M.zeros(#values)
    for i, value in ipairs(values) do result[i][i] = value end
    return result
end
function M.identity(size) local result = M.zeros(size); for i = 1, size do result[i][i] = 1.0 end; return result end
function M.transpose(a)
    local result = M.zeros(#a[1], #a)
    for i, row in ipairs(a) do for j, value in ipairs(row) do result[j][i] = value end end
    return result
end
function M.add(a, b)
    local result = M.zeros(#a, #a[1])
    for i, row in ipairs(a) do for j, value in ipairs(row) do result[i][j] = value + b[i][j] end end
    return result
end
function M.subtract(a, b)
    local result = M.zeros(#a, #a[1])
    for i, row in ipairs(a) do for j, value in ipairs(row) do result[i][j] = value - b[i][j] end end
    return result
end
function M.vector_add(a, b) local result = {}; for i, value in ipairs(a) do result[i] = value + b[i] end; return result end
function M.vector_subtract(a, b) local result = {}; for i, value in ipairs(a) do result[i] = value - b[i] end; return result end
function M.product(a, b)
    local result = M.zeros(#a, #b[1])
    for i, row in ipairs(a) do
        for j = 1, #b[1] do
            local value = 0.0
            for k, item in ipairs(row) do value = value + item * b[k][j] end
            result[i][j] = value
        end
    end
    return result
end
function M.vector(a, b)
    local result = {}
    for i, row in ipairs(a) do local value = 0.0; for j, item in ipairs(row) do value = value + item * b[j] end; result[i] = value end
    return result
end
function M.inverse(a)
    local size, augmented = #a, M.zeros(#a, 2 * #a)
    for i, row in ipairs(a) do for j, value in ipairs(row) do augmented[i][j] = value end; augmented[i][size + i] = 1.0 end
    for column = 1, size do
        local pivot = augmented[column][column]
        for j = 1, 2 * size do augmented[column][j] = augmented[column][j] / pivot end
        for row = 1, size do
            if row ~= column then
                local factor = augmented[row][column]
                for j = 1, 2 * size do augmented[row][j] = augmented[row][j] - factor * augmented[column][j] end
            end
        end
    end
    local result = M.zeros(size)
    for i = 1, size do for j = 1, size do result[i][j] = augmented[i][size + j] end end
    return result
end
function M.determinant2(a) return a[1][1] * a[2][2] - a[1][2] * a[2][1] end
function M.quadratic2(u, a) return u[1] * (a[1][1] * u[1] + a[1][2] * u[2]) + u[2] * (a[2][1] * u[1] + a[2][2] * u[2]) end
return M
