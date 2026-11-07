local M = {}
local Canvas = {}
Canvas.__index = Canvas
function M.new(width, height)
    local rows = {}
    for r = 1, height do
        rows[r] = {}
        for c = 1, width do
            rows[r][c] = " "
        end
    end
    return setmetatable({width = width, height = height, rows = rows}, Canvas)
end
function Canvas:position(point)
    local x, y, d = point[1], point[2], point[3] or 1
    return (2 * x * (self.width - 1) + 1000 * d) // (2000 * d),
        self.height - 1 - (2 * y * (self.height - 1) + 1000 * d) // (2000 * d)
end
function Canvas:mark(point, character)
    local x, y = self:position(point)
    self.rows[y + 1][x + 1] = character
end
function Canvas:line(first, second, character)
    local x, y = self:position(first)
    local end_x, end_y = self:position(second)
    local dx, dy = math.abs(end_x - x), -math.abs(end_y - y)
    local sx, sy = x < end_x and 1 or -1, y < end_y and 1 or -1
    local error = dx + dy
    while true do
        self.rows[y + 1][x + 1] = character
        if x == end_x and y == end_y then
            return
        end
        local twice = 2 * error
        if twice >= dy then
            error, x = error + dy, x + sx
        end
        if twice <= dx then
            error, y = error + dx, y + sy
        end
    end
end
function Canvas:voronoi(points)
    local horizontal, vertical, owners = self.width - 1, self.height - 1, {}
    for r = 0, vertical do
        owners[r + 1] = {}
        for c = 0, horizontal do
            local owner, best
            for site, point in ipairs(points) do
                local dx = (c * 1000 - point[1] * horizontal) * vertical
                local dy = ((vertical - r) * 1000 - point[2] * vertical) * horizontal
                local distance = dx * dx + dy * dy
                if not best or distance < best then
                    owner, best = site, distance
                end
            end
            owners[r + 1][c + 1] = owner
        end
    end
    for r = 1, self.height do
        for c = 1, self.width do
            local owner = owners[r][c]
            if c < self.width and owner ~= owners[r][c + 1] or r < self.height and owner ~= owners[r + 1][c] then
                self.rows[r][c] = "#"
            end
        end
    end
    for _, point in ipairs(points) do
        self:mark(point, "o")
    end
end
function Canvas:framed()
    local border = "+" .. string.rep("-", self.width) .. "+"
    local result = {border}
    for _, row in ipairs(self.rows) do
        result[#result + 1] = "|" .. table.concat(row) .. "|"
    end
    result[#result + 1] = border
    return result
end
return M
