local M = {direction_names = {"N", "NE", "E", "SE", "S", "SW", "W", "NW"},
    directions = {{0, -1}, {1, -1}, {1, 0}, {1, 1}, {0, 1}, {-1, 1}, {-1, 0}, {-1, -1}}}
local passable = {["."] = true, ["#"] = true, ["+"] = true, ["<"] = true, [">"] = true}

function M.passable(level, x, y) return passable[level.terrain[y + 1][x + 1]] == true end
function M.can_move(level, x, y, dx, dy)
    if not M.passable(level, x + dx, y + dy) then return false end
    return dx == 0 or dy == 0 or level.terrain[y + 1][x + 1] ~= "+" and level.terrain[y + dy + 1][x + dx + 1] ~= "+"
end

function M.line(x0, y0, x1, y1)
    local dx, dy = math.abs(x1 - x0), math.abs(y1 - y0)
    local sx, sy = x1 > x0 and 1 or -1, y1 > y0 and 1 or -1
    local err, x, y, cells = dx - dy, x0, y0, {}
    while x ~= x1 or y ~= y1 do
        local e2 = 2 * err
        if e2 > -dy then err, x = err - dy, x + sx end
        if e2 < dx then err, y = err + dx, y + sy end
        cells[#cells + 1] = {x, y}
    end
    return cells
end

function M.field_of_view(level, px, py, radius)
    local visible = {}
    for y = 1, level.height do
        visible[y] = {}
        for x = 1, level.width do visible[y][x] = false end
    end
    for y = math.max(0, py - radius), math.min(level.height - 1, py + radius) do
        for x = math.max(0, px - radius), math.min(level.width - 1, px + radius) do
            local dx, dy = x - px, y - py
            if dx * dx + dy * dy <= radius * radius then
                local cells, clear = M.line(px, py, x, y), true
                for index = 1, #cells - 1 do
                    local cell = cells[index]
                    if not M.passable(level, cell[1], cell[2]) then clear = false break end
                end
                visible[y + 1][x + 1] = clear
            end
        end
    end
    return visible
end

function M.distances(level, px, py)
    local distance = {}
    for y = 1, level.height do
        distance[y] = {}
        for x = 1, level.width do distance[y][x] = -1 end
    end
    distance[py + 1][px + 1] = 0
    local queue, head = {{px, py}}, 1
    while head <= #queue do
        local point = queue[head]
        head = head + 1
        local x, y = point[1], point[2]
        for _, move in ipairs(M.directions) do
            local dx, dy = move[1], move[2]
            if M.can_move(level, x, y, dx, dy) and distance[y + dy + 1][x + dx + 1] == -1 then
                distance[y + dy + 1][x + dx + 1] = distance[y + 1][x + 1] + 1
                queue[#queue + 1] = {x + dx, y + dy}
            end
        end
    end
    return distance
end

return M
