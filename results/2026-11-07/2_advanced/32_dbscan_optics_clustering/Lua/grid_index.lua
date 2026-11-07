local M = {}
function M.distance(a, b)
    local dx, dy = a.x - b.x, a.y - b.y
    return dx * dx + dy * dy
end
local Grid = {}
Grid.__index = Grid
local function key(x, y)
    return x .. "," .. y
end
function M.new(points, radius)
    local self = setmetatable({points = points, radius = radius, cells = {}, ordered_cells = {}}, Grid)
    for i, point in ipairs(points) do
        local x, y = point.x // radius, point.y // radius
        local name = key(x, y)
        if not self.cells[name] then
            local cell = {x = x, y = y, members = {}}
            self.cells[name] = cell
            self.ordered_cells[#self.ordered_cells + 1] = cell
        end
        local members = self.cells[name].members
        members[#members + 1] = i
    end
    return self
end
function Grid:neighborhood(i)
    local point = self.points[i]
    local x, y = point.x // self.radius, point.y // self.radius
    local result, candidates = {}, 0
    for gy = y - 1, y + 1 do
        for gx = x - 1, x + 1 do
            local cell = self.cells[key(gx, gy)]
            if cell then
                for _, other in ipairs(cell.members) do
                    candidates = candidates + 1
                    if M.distance(point, self.points[other]) <= self.radius * self.radius then
                        result[#result + 1] = other
                    end
                end
            end
        end
    end
    return result, candidates
end
function Grid:busiest()
    local best
    for _, cell in ipairs(self.ordered_cells) do
        if not best or #cell.members > #best.members or #cell.members == #best.members and (cell.y < best.y or cell.y == best.y and cell.x < best.x) then
            best = cell
        end
    end
    return best
end
function M.brute_counts(points, radius)
    local result = {}
    for i, point in ipairs(points) do
        local count = 0
        for _, other in ipairs(points) do
            if M.distance(point, other) <= radius * radius then
                count = count + 1
            end
        end
        result[i] = count
    end
    return result
end
return M
