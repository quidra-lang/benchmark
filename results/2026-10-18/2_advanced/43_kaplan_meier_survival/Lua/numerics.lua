local M = {Z = 1.959963984540054}
function M.zeros(count)
    local result = {}
    for index = 1, count do
        result[index] = 0.0
    end
    return result
end
function M.matrix(rows, columns)
    local result = {}
    for row = 1, rows do
        result[row] = M.zeros(columns)
    end
    return result
end
function M.copy(values)
    local result = {}
    for index, value in ipairs(values) do
        result[index] = value
    end
    return result
end
function M.solve(matrix, vector)
    local size, a, b = #vector, {}, M.copy(vector)
    for row = 1, size do
        a[row] = M.copy(matrix[row])
    end
    for k = 1, size do
        for i = k + 1, size do
            local factor = a[i][k] / a[k][k]
            for j = k, size do
                a[i][j] = a[i][j] - factor * a[k][j]
            end
            b[i] = b[i] - factor * b[k]
        end
    end
    local solution = M.zeros(size)
    for i = size, 1, -1 do
        local value = b[i]
        for j = i + 1, size do
            value = value - a[i][j] * solution[j]
        end
        solution[i] = value / a[i][i]
    end
    return solution
end
function M.inverse(matrix)
    local size = #matrix
    local result = M.matrix(size, size)
    for column = 1, size do
        local unit = M.zeros(size)
        unit[column] = 1.0
        local solution = M.solve(matrix, unit)
        for row = 1, size do
            result[row][column] = solution[row]
        end
    end
    return result
end
function M.log_gamma(a)
    local coefficients = {76.18009172947146, -86.50532032941677, 24.01409824083091,
        -1.231739572450155, 0.001208650973866179, -0.000005395239384953}
    local xi = a + 5.5
    xi = xi - (a + 0.5) * math.log(xi)
    local sigma, y = 1.000000000190015, a
    for _, coefficient in ipairs(coefficients) do
        y = y + 1.0
        sigma = sigma + coefficient / y
    end
    return -xi + math.log(2.5066282746310005 * sigma / a)
end
function M.gamma_q(a, x)
    if x == 0.0 then
        return 1.0
    end
    local prefactor = math.exp(-x + a * math.log(x) - M.log_gamma(a))
    if x < a + 1.0 then
        local alpha, term = a, 1.0 / a
        local sigma = term
        for _ = 1, 1000 do
            alpha = alpha + 1.0
            term = term * (x / alpha)
            sigma = sigma + term
            if math.abs(term) < math.abs(sigma) * 1e-15 then
                break
            end
        end
        return 1.0 - sigma * prefactor
    end
    local epsilon = 1e-300
    local b, c = x + 1.0 - a, 1.0 / epsilon
    local d = 1.0 / b
    local h = d
    for i = 1, 1000 do
        local an = -i * (i - a)
        b = b + 2.0
        d = an * d + b
        if math.abs(d) < epsilon then
            d = epsilon
        end
        c = b + an / c
        if math.abs(c) < epsilon then
            c = epsilon
        end
        d = 1.0 / d
        local delta = d * c
        h = h * delta
        if math.abs(delta - 1.0) < 1e-15 then
            break
        end
    end
    return prefactor * h
end
function M.p(statistic, degrees)
    return M.gamma_q(degrees / 2.0, statistic / 2.0)
end
return M
