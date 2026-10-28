local M = {}
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
function M.fit(matrix, response, weights, tolerance)
    local n, p = #matrix, #matrix[1]
    local roots, weighted, work, transformed = {}, {}, {}, {}
    for i = 1, n do
        roots[i], weighted[i], work[i] = math.sqrt(weights[i]), {}, {}
        for j = 1, p do
            weighted[i][j] = roots[i] * matrix[i][j]
            work[i][j] = weighted[i][j]
        end
        transformed[i] = roots[i] * response[i]
    end
    local lengths = {}
    for j = 1, p do
        local sum = 0.0
        for i = 1, n do
            sum = sum + weighted[i][j] * weighted[i][j]
        end
        lengths[j] = math.sqrt(sum)
    end
    local triangular, accepted, aliases = M.matrix(p, p), {}, {}
    for j = 1, p do
        local k, sum = #accepted + 1, 0.0
        for i = k, n do
            sum = sum + work[i][j] * work[i][j]
        end
        local eta = math.sqrt(sum)
        if eta <= tolerance * lengths[j] then
            aliases[#aliases + 1] = j
        else
            accepted[#accepted + 1] = j
            local alpha = work[k][j] >= 0.0 and -eta or eta
            local vector, squared = {}, 0.0
            for i = k, n do
                vector[i] = i == k and work[i][j] - alpha or work[i][j]
                squared = squared + vector[i] * vector[i]
            end
            for l = 1, k - 1 do
                triangular[l][k] = work[l][j]
            end
            triangular[k][k] = alpha
            for l = j + 1, p do
                local dot = 0.0
                for i = k, n do
                    dot = dot + vector[i] * work[i][l]
                end
                local delta = 2.0 * dot / squared
                for i = k, n do
                    work[i][l] = work[i][l] - delta * vector[i]
                end
            end
            local dot = 0.0
            for i = k, n do
                dot = dot + vector[i] * transformed[i]
            end
            local delta = 2.0 * dot / squared
            for i = k, n do
                transformed[i] = transformed[i] - delta * vector[i]
            end
        end
    end
    local rank, effects, beta = #accepted, {}, {}
    for k = 1, rank do
        effects[k] = transformed[k]
    end
    for k = rank, 1, -1 do
        local tail = 0.0
        for l = k + 1, rank do
            tail = tail + triangular[k][l] * beta[accepted[l]]
        end
        beta[accepted[k]] = (effects[k] - tail) / triangular[k][k]
    end
    local inverse = M.matrix(rank, rank)
    for m = 1, rank do
        for l = rank, 1, -1 do
            local tail = 0.0
            for q = l + 1, rank do
                tail = tail + triangular[l][q] * inverse[q][m]
            end
            inverse[l][m] = ((l == m and 1.0 or 0.0) - tail) / triangular[l][l]
        end
    end
    local variance = {}
    for k = 1, rank do
        local sum = 0.0
        for m = 1, rank do
            sum = sum + inverse[k][m] * inverse[k][m]
        end
        variance[k] = sum
    end
    local u, g, leverage, fitted, residual, weighted_residual, rss = {}, {}, {}, {}, {}, {}, 0.0
    for i = 1, n do
        u[i], g[i] = {}, {}
        local h = 0.0
        for k = 1, rank do
            local sum = 0.0
            for m = 1, rank do
                sum = sum + weighted[i][accepted[m]] * inverse[m][k]
            end
            u[i][k] = sum
            h = h + sum * sum
        end
        leverage[i] = h
        for k = 1, rank do
            local sum = 0.0
            for m = 1, rank do
                sum = sum + inverse[k][m] * u[i][m]
            end
            g[i][k] = sum
        end
        local value = 0.0
        for k = 1, rank do
            value = value + matrix[i][accepted[k]] * beta[accepted[k]]
        end
        fitted[i], residual[i] = value, response[i] - value
        weighted_residual[i] = roots[i] * residual[i]
        rss = rss + weighted_residual[i] * weighted_residual[i]
    end
    return {matrix = matrix, response = response, weights = weights, n = n, p = p, rank = rank,
        accepted = accepted, aliases = aliases, triangular = triangular, effects = effects, beta = beta,
        inverse = inverse, variance = variance, u = u, g = g, leverage = leverage,
        fitted = fitted, residual = residual, weighted_residual = weighted_residual, rss = rss}
end
return M
