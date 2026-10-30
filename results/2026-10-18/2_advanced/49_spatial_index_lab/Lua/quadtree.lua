local M = {}
M.names = {"NW", "NE", "SW", "SE"}
local function node(x, y, size)
    return {x = x, y = y, size = size, points = {}, children = {}}
end
function M.destination(current, point)
    local half = current.size // 2
    return 1 + (point.x >= current.x + half and 1 or 0) + (point.y >= current.y + half and 2 or 0)
end
function M.split(current, capacity)
    local half, previous = current.size // 2, current.points
    current.children = {node(current.x, current.y, half), node(current.x + half, current.y, half),
        node(current.x, current.y + half, half), node(current.x + half, current.y + half, half)}
    current.points = {}
    for _, point in ipairs(previous) do
        M.insert(current, point, capacity)
    end
end
function M.insert(root, point, capacity)
    local current = root
    while #current.children > 0 do
        current = current.children[M.destination(current, point)]
    end
    local position = #current.points + 1
    for i, other in ipairs(current.points) do
        if point.id < other.id then
            position = i
            break
        end
    end
    table.insert(current.points, position, point)
    if #current.points > capacity then
        M.split(current, capacity)
    end
end
function M.delete(root, point, capacity)
    local current, ancestors = root, {}
    while #current.children > 0 do
        ancestors[#ancestors + 1] = current
        current = current.children[M.destination(current, point)]
    end
    for i, other in ipairs(current.points) do
        if other.id == point.id then
            table.remove(current.points, i)
            break
        end
    end
    for index = #ancestors, 1, -1 do
        current = ancestors[index]
        local points, merge = {}, true
        for _, child in ipairs(current.children) do
            if #child.children > 0 then
                merge = false
                break
            end
            for _, value in ipairs(child.points) do
                points[#points + 1] = value
            end
        end
        if not merge or #points > capacity then
            break
        end
        table.sort(points, function(a, b) return a.id < b.id end)
        current.points, current.children = points, {}
    end
end
function M.build(points, world, capacity)
    local root = node(0, 0, world)
    for _, point in ipairs(points) do
        M.insert(root, point, capacity)
    end
    return root
end
return M
