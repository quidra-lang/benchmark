local M = {}
local function numbers(line)
    local result = {}
    for value in line:gmatch("%d+") do
        result[#result + 1] = tonumber(value)
    end
    return result
end
function M.read()
    local points = {}
    local file = assert(io.open("input/points.csv"))
    file:read()
    for line in file:lines() do
        local values = numbers(line)
        points[#points + 1] = {id = values[1], x = values[2], y = values[3]}
    end
    file:close()
    table.sort(points, function(a, b)
        return a.id < b.id
    end)
    local values = {}
    file = assert(io.open("input/params.txt"))
    for line in file:lines() do
        values[#values + 1] = numbers(line)
    end
    file:close()
    local p = {eps = values[1], min_pts = values[2][1], max_eps = values[3][1], extract = values[4], u = values[5][1], v = values[5][2], min_size = values[6][1], width = values[7][1], height = values[7][2], k_width = values[8][1], k_height = values[8][2], plot_width = values[9][1]}
    return points, p
end
return M
