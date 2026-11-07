local grid_map = require("grid_map")
local M = {DIRECTIONS = {{0, -1}, {1, 0}, {0, 1}, {-1, 0}}}
function M.neighbor(cell, direction)
    local delta = M.DIRECTIONS[direction]
    return {cell[1] + delta[1], cell[2] + delta[2]}
end
local DistanceField = {}
DistanceField.__index = DistanceField
function DistanceField.new(grid, towers)
    local self = setmetatable({grid = grid, exit = grid.exit, dist = {}}, DistanceField)
    for y = 1, grid.height do self.dist[y] = {} for x = 1, grid.width do self.dist[y][x] = -1 end end
    self.dist[grid.exit[2] + 1][grid.exit[1] + 1] = 0
    local queue, first = {grid.exit}, 1
    while first <= #queue do
        local cell = queue[first]
        first = first + 1
        for direction = 1, 4 do
            local following = M.neighbor(cell, direction)
            if grid:inside(following) and not grid:is_rock(following) and not towers[grid_map.key(following)] and self:at(following) == -1 then
                self.dist[following[2] + 1][following[1] + 1] = self:at(cell) + 1
                queue[#queue + 1] = following
            end
        end
    end
    return self
end
function DistanceField:at(cell) return self.dist[cell[2] + 1][cell[1] + 1] end
function DistanceField:direction(cell)
    local best, best_distance
    for direction = 1, 4 do
        local following = M.neighbor(cell, direction)
        if self.grid:inside(following) then
            local distance = self:at(following)
            if distance >= 0 and (best == nil or distance < best_distance) then best, best_distance = direction, distance end
        end
    end
    return best
end
function DistanceField:next_cell(cell) return M.neighbor(cell, self:direction(cell)) end
function DistanceField:path(start)
    local cells = {start}
    while not grid_map.same(cells[#cells], self.exit) do cells[#cells + 1] = self:next_cell(cells[#cells]) end
    return cells
end
M.DistanceField = DistanceField
return M
