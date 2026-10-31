local M = {}
function M.cholesky(matrix, free)
    local lower = {}
    for i = 1, #matrix do lower[i] = {}; for j = 1, #matrix do lower[i][j] = 0.0 end end
    for i = 1, #matrix do
        for j = 1, i do
            local value = matrix[i][j]
            for h = 1, j - 1 do value = value - lower[i][h] * lower[j][h] end
            if j < i then lower[i][j] = value / lower[j][j]
            else
                if value <= 0.000000001 * matrix[i][i] then return nil, free[i] end
                lower[i][i] = math.sqrt(value)
            end
        end
    end
    return lower, nil
end
function M.solve(lower, right)
    local intermediate, result = {}, {}
    for i = 1, #right do
        local value = right[i]
        for h = 1, i - 1 do value = value - lower[i][h] * intermediate[h] end
        intermediate[i] = value / lower[i][i]
    end
    for i = #right, 1, -1 do
        local value = intermediate[i]
        for h = i + 1, #right do value = value - lower[h][i] * result[h] end
        result[i] = value / lower[i][i]
    end
    return result
end
return M
