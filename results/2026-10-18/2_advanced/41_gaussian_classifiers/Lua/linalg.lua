local M = {}
function M.zeros(size)
    local result = {}
    for i = 1, size do
        result[i] = {}
        for j = 1, size do
            result[i][j] = 0.0
        end
    end
    return result
end
function M.dot(first, second)
    local result = 0.0
    for index = 1, #first do
        result = result + first[index] * second[index]
    end
    return result
end
function M.cholesky(matrix)
    local lower = M.zeros(#matrix)
    for i = 1, #matrix do
        for j = 1, i do
            local subtotal = 0.0
            for k = 1, j - 1 do
                subtotal = subtotal + lower[i][k] * lower[j][k]
            end
            local remainder = matrix[i][j] - subtotal
            lower[i][j] = i == j and math.sqrt(remainder) or remainder / lower[j][j]
        end
    end
    return lower
end
function M.forward(lower, right)
    local result = {}
    for i = 1, #lower do
        local subtotal = 0.0
        for k = 1, i - 1 do
            subtotal = subtotal + lower[i][k] * result[k]
        end
        result[i] = (right[i] - subtotal) / lower[i][i]
    end
    return result
end
function M.backward(lower, right)
    local result = {}
    for i = #lower, 1, -1 do
        local subtotal = 0.0
        for k = i + 1, #lower do
            subtotal = subtotal + lower[k][i] * result[k]
        end
        result[i] = (right[i] - subtotal) / lower[i][i]
    end
    return result
end
function M.log_determinant(lower)
    local total = 0.0
    for index = 1, #lower do
        total = total + math.log(lower[index][index])
    end
    return 2 * total
end
function M.quadratic(lower, difference)
    local transformed = M.forward(lower, difference)
    return M.dot(transformed, transformed)
end
function M.jacobi(matrix)
    local size, current, vectors, sweeps = #matrix, {}, M.zeros(#matrix), 0
    for index, row in ipairs(matrix) do
        current[index], vectors[index][index] = {table.unpack(row)}, 1.0
    end
    while true do
        local off = 0.0
        for a = 1, size - 1 do
            for b = a + 1, size do
                off = off + current[a][b] * current[a][b]
            end
        end
        if math.sqrt(off) < 0.000000000001 or sweeps == 50 then
            break
        end
        for a = 1, size - 1 do
            for b = a + 1, size do
                if current[a][b] ~= 0 then
                    local theta = (current[b][b] - current[a][a]) / (2 * current[a][b])
                    local tangent = (theta >= 0 and 1 or -1) / (math.abs(theta) + math.sqrt(theta * theta + 1))
                    local cosine = 1 / math.sqrt(tangent * tangent + 1)
                    local sine = tangent * cosine
                    for k = 1, size do
                        if k ~= a and k ~= b then
                            local x, y = current[k][a], current[k][b]
                            current[k][a], current[a][k] = cosine * x - sine * y, cosine * x - sine * y
                            current[k][b], current[b][k] = sine * x + cosine * y, sine * x + cosine * y
                        end
                    end
                    local value = current[a][b]
                    current[a][a], current[b][b] = current[a][a] - tangent * value, current[b][b] + tangent * value
                    current[a][b], current[b][a] = 0.0, 0.0
                    for k = 1, size do
                        local x, y = vectors[k][a], vectors[k][b]
                        vectors[k][a], vectors[k][b] = cosine * x - sine * y, sine * x + cosine * y
                    end
                end
            end
        end
        sweeps = sweeps + 1
    end
    local values = {}
    for index = 1, size do
        values[index] = current[index][index]
    end
    return values, vectors, sweeps
end
return M
