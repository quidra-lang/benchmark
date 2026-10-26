local M = {}
function M.cell_center(cell) return {100 * cell[1], 100 * cell[2]} end
function M.key(cell) return cell[1] .. "," .. cell[2] end
function M.same(first, second) return first[1] == second[1] and first[2] == second[2] end
local GridMap = {}
GridMap.__index = GridMap
function GridMap.new(width, height, rows)
    local self = setmetatable({width = width, height = height, rows = rows, spawns = {}}, GridMap)
    for y = 0, height - 1 do
        for x = 0, width - 1 do
            local terrain = rows[y + 1]:sub(x + 1, x + 1)
            if terrain:match("^[1-9]$") then self.spawns[tonumber(terrain)] = {x, y}
            elseif terrain == "E" then self.exit = {x, y} end
        end
    end
    return self
end
function GridMap:inside(cell) return cell[1] >= 0 and cell[1] < self.width and cell[2] >= 0 and cell[2] < self.height end
function GridMap:terrain(cell) return self.rows[cell[2] + 1]:sub(cell[1] + 1, cell[1] + 1) end
function GridMap:is_rock(cell) return self:terrain(cell) == "#" end
function GridMap:is_water(cell) return self:terrain(cell) == "~" end
function GridMap:buildable(cell) return self:terrain(cell) == "." end
function M.read_map(path)
    local file = assert(io.open(path, "r"))
    local width, height = file:read("l"):match("^(%d+) (%d+)$")
    local rows = {}
    for y = 1, tonumber(height) do rows[y] = file:read("l") end
    file:close()
    return GridMap.new(tonumber(width), tonumber(height), rows)
end
M.GridMap = GridMap
return M
