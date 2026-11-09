local distance = require("grid_index").distance
local M = {INF = math.maxinteger}
function M.core_distances(points, neighbors, minimum)
    local result = {}
    for i, row in ipairs(neighbors) do
        result[i] = M.INF
        if #row >= minimum then
            local values = {}
            for _, other in ipairs(row) do
                values[#values + 1] = distance(points[i], points[other])
            end
            table.sort(values)
            result[i] = values[minimum]
        end
    end
    return result
end
function M.order(points, neighbors, core)
    local reach, predecessor, processed, ordering = {}, {}, {}, {}
    for i = 1, #points do
        reach[i] = M.INF
    end
    for start = 1, #points do
        if not processed[start] then
            local seeds = {[start] = true}
            while next(seeds) do
                local current
                for i in pairs(seeds) do
                    if not current or reach[i] < reach[current] or reach[i] == reach[current] and i < current then
                        current = i
                    end
                end
                seeds[current], processed[current] = nil, true
                ordering[#ordering + 1] = current
                if core[current] ~= M.INF then
                    for _, other in ipairs(neighbors[current]) do
                        if not processed[other] then
                            local candidate = math.max(core[current], distance(points[current], points[other]))
                            if candidate < reach[other] then
                                reach[other], predecessor[other], seeds[other] = candidate, current, true
                            end
                        end
                    end
                end
            end
        end
    end
    return ordering, reach, predecessor
end
return M
