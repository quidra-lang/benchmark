local M = {}
local function numeric_fields(line, pattern)
    local result = {}
    for value in line:gmatch(pattern) do
        result[#result + 1] = tonumber(value)
    end
    return result
end
local function csv(path, rectangle)
    local result, first = {}, true
    for line in io.lines(path) do
        if first then
            first = false
        else
            local values = numeric_fields(line, "[^,]+")
            if rectangle then
                result[#result + 1] = {id = values[1], box = {values[2], values[3], values[4], values[5]}}
            else
                result[#result + 1] = {id = values[1], x = values[2], y = values[3], box = {values[2], values[3], values[2], values[3]}}
            end
        end
    end
    return result
end
function M.read()
    local points, rectangles = csv("input/points.csv", false), csv("input/rects.csv", true)
    local settings = {}
    for line in io.lines("input/params.txt") do
        local key, tail = line:match("^(%S+) (.+)$")
        settings[key] = numeric_fields(tail, "%d+")
    end
    local commands = {}
    for line in io.lines("input/queries.txt") do
        local name = line:match("^%S+")
        commands[#commands + 1] = {name = name, values = numeric_fields(line:sub(#name + 1), "%d+")}
    end
    return {points = points, rectangles = rectangles, commands = commands,
        params = {world = settings.WORLD[1], bucket = settings.BUCKET[1], maximum = settings.RTREE[1],
            minimum = settings.RTREE[2], cell_size = settings.GRID[1]}}
end
return M
