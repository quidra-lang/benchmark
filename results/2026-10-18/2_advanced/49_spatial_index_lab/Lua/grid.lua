local M = {}
local Grid = {}
Grid.__index = Grid
function M.build(points, world, cell_size)
    local side, cells = world // cell_size, {}
    for row = 0, side - 1 do
        for column = 0, side - 1 do
            local x, y = column * cell_size, row * cell_size
            cells[#cells + 1] = {column = column, row = row, box = {x, y, x + cell_size - 1, y + cell_size - 1}, points = {}}
        end
    end
    local result = setmetatable({world = world, cell_size = cell_size, side = side, cells = cells}, Grid)
    for _, point in ipairs(points) do
        result:insert(point)
    end
    return result
end
function Grid:position(point)
    return point.x // self.cell_size, point.y // self.cell_size
end
function Grid:cell(point)
    local column, row = self:position(point)
    return self.cells[row * self.side + column + 1]
end
function Grid:insert(point)
    local values = self:cell(point).points
    local position = #values + 1
    for i, other in ipairs(values) do
        if point.id < other.id then
            position = i
            break
        end
    end
    table.insert(values, position, point)
end
function Grid:delete(point)
    local values = self:cell(point).points
    for i, other in ipairs(values) do
        if point.id == other.id then
            table.remove(values, i)
            return
        end
    end
end
return M
