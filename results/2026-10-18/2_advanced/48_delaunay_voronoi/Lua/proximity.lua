local predicates = require("predicates")
local M = {}
local Sets = {}
Sets.__index = Sets
function M.sets(count)
    local parent, sizes = {}, {}
    for i = 1, count do
        parent[i], sizes[i] = i, 1
    end
    return setmetatable({parent = parent, sizes = sizes, count = count}, Sets)
end
function Sets:find(site)
    while self.parent[site] ~= site do
        self.parent[site] = self.parent[self.parent[site]]
        site = self.parent[site]
    end
    return site
end
function Sets:union(first, second)
    first, second = self:find(first), self:find(second)
    if first == second then
        return false
    end
    if self.sizes[first] < self.sizes[second] then
        first, second = second, first
    end
    self.parent[second] = first
    self.sizes[first] = self.sizes[first] + self.sizes[second]
    self.count = self.count - 1
    return true
end
function M.nearest(points, neighbors)
    local result = {}
    for site, adjacent in ipairs(neighbors) do
        local best, distance
        for _, other in ipairs(adjacent) do
            local value = predicates.d2(points[site], points[other])
            if not distance or value < distance or value == distance and other < best then
                best, distance = other, value
            end
        end
        result[site] = best
    end
    return result
end
function M.components(nearest)
    local sets, groups, result = M.sets(#nearest), {}, {}
    for site, other in ipairs(nearest) do
        sets:union(site, other)
    end
    for site = 1, #nearest do
        local root = sets:find(site)
        groups[root] = groups[root] or {}
        groups[root][#groups[root] + 1] = site
    end
    for _, group in pairs(groups) do
        result[#result + 1] = group
    end
    table.sort(result, function(a, b) return a[1] < b[1] end)
    return result
end
function M.kruskal(points, edges)
    local ordered = {table.unpack(edges)}
    table.sort(ordered, function(a, b)
        local first, second = predicates.d2(points[a[1]], points[a[2]]), predicates.d2(points[b[1]], points[b[2]])
        if first ~= second then
            return first < second
        elseif a[1] ~= b[1] then
            return a[1] < b[1]
        end
        return a[2] < b[2]
    end)
    local sets, result = M.sets(#points), {}
    for _, edge in ipairs(ordered) do
        if sets:union(edge[1], edge[2]) then
            result[#result + 1] = edge
            if sets.count == 1 then
                break
            end
        end
    end
    return result
end
function M.gabriel(points, edge, directed)
    local i, j = table.unpack(edge)
    local left, right = directed[i][j], directed[j][i]
    return (not left or predicates.dot(points[left], points[i], points[j]) > 0) and
        (not right or predicates.dot(points[right], points[i], points[j]) > 0)
end
function M.relative(points, edge)
    local i, j = table.unpack(edge)
    local distance = predicates.d2(points[i], points[j])
    for _, point in ipairs(points) do
        if predicates.d2(points[i], point) < distance and predicates.d2(points[j], point) < distance then
            return false
        end
    end
    return true
end
function M.route(points, neighbors, start, target)
    local path, length, current = {start}, 0.0, start
    while current ~= target do
        local following, best
        for _, site in ipairs(neighbors[current]) do
            local value = predicates.d2(points[site], points[target])
            if not best or value < best or value == best and site < following then
                best, following = value, site
            end
        end
        length = length + math.sqrt(predicates.d2(points[current], points[following]))
        path[#path + 1], current = following, following
    end
    return path, length
end
function M.dijkstra(points, neighbors, start)
    local distances, previous, visited = {}, {}, {}
    for site = 1, #points do
        distances[site] = site == start and 0.0 or math.huge
    end
    for _ = 1, #points do
        local current
        for site = 1, #points do
            if not visited[site] and (not current or distances[site] < distances[current]) then
                current = site
            end
        end
        if not current then
            break
        end
        visited[current] = true
        for _, other in ipairs(neighbors[current]) do
            local candidate = distances[current] + math.sqrt(predicates.d2(points[current], points[other]))
            if candidate < distances[other] then
                distances[other], previous[other] = candidate, current
            end
        end
    end
    return distances, previous
end
return M
