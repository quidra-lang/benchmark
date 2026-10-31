local M = {}

function M.coefficients(method, a, b, k)
    if method == "single" then return 0.5, 0.5, 0.0, -0.5 end
    if method == "complete" then return 0.5, 0.5, 0.0, 0.5 end
    if method == "average" then return a / (a + b), b / (a + b), 0.0, 0.0 end
    if method == "weighted" then return 0.5, 0.5, 0.0, 0.0 end
    if method == "centroid" then return a / (a + b), b / (a + b), -(a * b) / ((a + b) * (a + b)), 0.0 end
    if method == "median" then return 0.5, 0.5, -0.25, 0.0 end
    local total = a + b + k
    return (a + k) / total, (b + k) / total, -k / total, 0.0
end

function M.agglomerate(delta, method)
    local n, values, sizes, active, merges = #delta, {}, {}, {}, {}
    local squared = method == "centroid" or method == "median" or method == "ward"
    for i = 1, 2 * n - 1 do
        values[i], sizes[i] = {}, 0
        if i <= n then active[#active + 1], sizes[i] = i, 1 end
    end
    for i = 1, n do
        for j = 1, n do values[i][j] = squared and delta[i][j] * delta[i][j] or delta[i][j] end
    end
    for step = 1, n - 1 do
        local a, b = active[1], active[2]
        for position, first in ipairs(active) do
            for other = position + 1, #active do
                local second = active[other]
                if values[first][second] < values[a][b] then a, b = first, second end
            end
        end
        local node = n + step
        sizes[node] = sizes[a] + sizes[b]
        merges[step] = {a = a - 1, b = b - 1, height = squared and math.sqrt(values[a][b]) or values[a][b], size = sizes[node]}
        for _, k in ipairs(active) do
            if k ~= a and k ~= b then
                local aa, ab, beta, gamma = M.coefficients(method, sizes[a], sizes[b], sizes[k])
                local value = aa * values[a][k] + ab * values[b][k] + beta * values[a][b] + gamma * math.abs(values[a][k] - values[b][k])
                values[node][k], values[k][node] = value, value
            end
        end
        local remaining = {}
        for _, k in ipairs(active) do if k ~= a and k ~= b then remaining[#remaining + 1] = k end end
        remaining[#remaining + 1], active = node, remaining
    end
    return merges
end

function M.mst(delta)
    local n, inside, key, parent, edges = #delta, {}, {}, {}, {}
    for i = 1, n do inside[i], key[i], parent[i] = i == 1, delta[1][i], 1 end
    for _ = 1, n - 1 do
        local chosen
        for i = 1, n do if not inside[i] and (not chosen or key[i] < key[chosen]) then chosen = i end end
        inside[chosen] = true
        edges[#edges + 1] = {parent = parent[chosen], child = chosen, weight = key[chosen]}
        for i = 1, n do
            if not inside[i] and delta[chosen][i] < key[i] then key[i], parent[i] = delta[chosen][i], chosen end
        end
    end
    return edges
end

return M
