local kmeans = require("kmeans")
local features = require("features")
local M = {}

function M.distances(points)
    local table_ = {}
    for i = 1, #points do table_[i] = {}; for j = 1, #points do table_[i][j] = 0.0 end end
    for i = 1, #points do for j = i + 1, #points do
        local distance = math.sqrt(kmeans.distance(points[i], points[j]))
        table_[i][j], table_[j][i] = distance, distance
    end end
    return table_
end

function M.indices(points, solution, distances)
    local k, silhouettes, spreads, between = solution.k, {}, {}, 0.0
    for i, point in ipairs(points) do
        local own = solution.labels[i]
        if #solution.members[own] == 1 then silhouettes[i] = 0.0
        else
            local totals = {}; for j = 1, k do totals[j] = 0.0 end
            for j = 1, #points do if i ~= j then local label = solution.labels[j]; totals[label] = totals[label] + distances[i][j] end end
            local inner, outer = totals[own] / (#solution.members[own] - 1), nil
            for j = 1, k do if j ~= own then local value = totals[j] / #solution.members[j]; if not outer or value < outer then outer = value end end end
            local largest = math.max(inner, outer)
            silhouettes[i] = largest == 0 and 0.0 or (outer - inner) / largest
        end
    end
    local global = kmeans.mean(points)
    for j, members in ipairs(solution.members) do
        between = between + #members * kmeans.distance(solution.centers[j], global)
        local total = 0.0
        for _, i in ipairs(members) do total = total + math.sqrt(kmeans.distance(points[i], solution.centers[j])) end
        spreads[j] = total / #members
    end
    local db = 0.0
    for j = 1, k do
        local worst
        for e = 1, k do if e ~= j then
            local value = (spreads[j] + spreads[e]) / math.sqrt(kmeans.distance(solution.centers[j], solution.centers[e]))
            if not worst or value > worst then worst = value end
        end end
        db = db + worst
    end
    return {silhouettes = silhouettes, silhouette = features.mean(silhouettes), calinski_harabasz = (between / (k - 1)) / (solution.sse / (#points - k)), davies_bouldin = db / k}
end

function M.elbow(k, first_k, last_k, within, first, last)
    local x, y = (k - first_k) / (last_k - first_k), (within - last) / (first - last)
    return ((1 - x) - y) / math.sqrt(2)
end

function M.hartigan(within, following, n, k) return (within / following - 1) * (n - k - 1) end

local function pair_count(n) return n * (n - 1) // 2 end

function M.ari(first, second)
    local rows, columns, cells = {}, {}, {}
    for i, a in ipairs(first) do
        local b = second[i]
        rows[a], columns[b] = (rows[a] or 0) + 1, (columns[b] or 0) + 1
        cells[a] = cells[a] or {}
        cells[a][b] = (cells[a][b] or 0) + 1
    end
    local sx, sy, sxy = 0, 0, 0
    for _, size in pairs(rows) do sx = sx + pair_count(size) end
    for _, size in pairs(columns) do sy = sy + pair_count(size) end
    for _, row in pairs(cells) do for _, size in pairs(row) do sxy = sxy + pair_count(size) end end
    local z = pair_count(#first)
    local numerator, denominator = 2 * (z * sxy - sx * sy), z * (sx + sy) - 2 * sx * sy
    return denominator == 0 and 1.0 or numerator / denominator
end

return M
