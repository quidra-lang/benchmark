local predicates = require("predicates")
local Mesh = {}
Mesh.__index = Mesh
local M = {}
function M.canonical(a, b, c)
    if b < a and b < c then
        return {b, c, a}
    elseif c < a and c < b then
        return {c, a, b}
    end
    return {a, b, c}
end
function M.less(first, second)
    for i = 1, #first do
        if first[i] ~= second[i] then
            return first[i] < second[i]
        end
    end
    return false
end
function M.new(points)
    local directed = {}
    for i = 1, #points do
        directed[i] = {}
    end
    local initial = predicates.orient(points[1], points[2], points[3]) > 0 and {1, 2, 3} or {1, 3, 2}
    local mesh = setmetatable({points = points, directed = directed, initial = initial}, Mesh)
    mesh:add(table.unpack(initial))
    return mesh
end
function Mesh:add(a, b, c)
    self.directed[a][b], self.directed[b][c], self.directed[c][a] = c, a, b
end
function Mesh:remove(a, b, c)
    self.directed[a][b], self.directed[b][c], self.directed[c][a] = nil, nil, nil
end
function Mesh:triangles()
    local result = {}
    for a, row in ipairs(self.directed) do
        for b, c in pairs(row) do
            if a < b and a < c then
                result[#result + 1] = {a, b, c}
            end
        end
    end
    table.sort(result, M.less)
    return result
end
function Mesh:hull_edges()
    local result = {}
    for u, row in ipairs(self.directed) do
        for v in pairs(row) do
            if not self.directed[v][u] then
                result[#result + 1] = {u, v}
            end
        end
    end
    table.sort(result, M.less)
    return result
end
function Mesh:insert(site)
    local points, containing, check = self.points, nil, {}
    for _, triangle in ipairs(self:triangles()) do
        local a, b, c = table.unpack(triangle)
        if predicates.orient(points[a], points[b], points[site]) > 0 and
            predicates.orient(points[b], points[c], points[site]) > 0 and predicates.orient(points[c], points[a], points[site]) > 0 then
            containing = triangle
            break
        end
    end
    local visible = 0
    if containing then
        local a, b, c = table.unpack(containing)
        self:remove(a, b, c)
        check = {{a, b}, {b, c}, {c, a}}
    else
        for _, edge in ipairs(self:hull_edges()) do
            local u, v = table.unpack(edge)
            if predicates.orient(points[u], points[v], points[site]) < 0 then
                check[#check + 1] = {v, u}
            end
        end
        visible = #check
    end
    local pending, stack = {}, {}
    local function enqueue(a, b)
        local key = a * (#points + 1) + b
        if not pending[key] then
            pending[key] = true
            stack[#stack + 1] = {a, b, key}
        end
    end
    for _, edge in ipairs(check) do
        self:add(edge[1], edge[2], site)
        enqueue(edge[1], edge[2])
    end
    local flips = 0
    while #stack > 0 do
        local a, b, key = table.unpack(table.remove(stack))
        pending[key] = nil
        local q = self.directed[b][a]
        if self.directed[a][b] == site and q and predicates.incircle(points[a], points[b], points[site], points[q]) > 0 then
            self:remove(a, b, site)
            self:remove(b, a, q)
            self:add(a, q, site)
            self:add(q, b, site)
            enqueue(a, q)
            enqueue(q, b)
            flips = flips + 1
        end
    end
    return {kind = containing and "inside" or "outside", containing = containing, visible = visible, flips = flips,
        triangles = #self:triangles(), hull = #self:hull_edges()}
end
function Mesh:walk(query, triangles, edge_triangles)
    local path = {1}
    while true do
        local a, b, c = table.unpack(triangles[path[#path]])
        local crossing
        for _, edge in ipairs({{a, b}, {b, c}, {c, a}}) do
            if predicates.orient(self.points[edge[1]], self.points[edge[2]], query) < 0 then
                crossing = edge
                break
            end
        end
        if not crossing then
            return path
        end
        local following = edge_triangles[crossing[2]][crossing[1]]
        if not following then
            table.sort(crossing)
            return path, crossing
        end
        path[#path + 1] = following
    end
end
return M
