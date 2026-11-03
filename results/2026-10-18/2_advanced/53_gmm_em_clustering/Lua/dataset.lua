local M = {}
local function words(line)
    local result = {}
    for word in line:gmatch("%S+") do result[#result + 1] = word end
    return result
end
function M.read()
    local points, initial, settings = {}, {}, {}
    local input = assert(io.open("input/points.csv", "r"))
    input:read("l")
    for line in input:lines() do
        local id, x, y = line:match("([^,]+),([^,]+),([^,]+)")
        points[#points + 1] = {id = id, x = tonumber(x), y = tonumber(y)}
    end
    input:close()
    input = assert(io.open("input/init.txt", "r"))
    local current
    for line in input:lines() do
        local fields = words(line)
        if fields[1] == "K" then
            current = {weights = {}, means = {}, covariances = {}}
            initial[tonumber(fields[2])] = current
        elseif fields[1] == "W" then
            for j = 2, #fields do current.weights[#current.weights + 1] = tonumber(fields[j]) end
        elseif fields[1] == "C" then
            current.means[#current.means + 1] = {tonumber(fields[3]), tonumber(fields[4])}
            current.covariances[#current.covariances + 1] = {tonumber(fields[5]), tonumber(fields[6]), tonumber(fields[7])}
        end
    end
    input:close()
    input = assert(io.open("input/params.txt", "r"))
    for line in input:lines() do
        local fields = words(line)
        local key = table.remove(fields, 1)
        if key ~= "TYPES" then
            for j, value in ipairs(fields) do fields[j] = tonumber(value) end
        end
        settings[key] = fields
    end
    input:close()
    return points, initial, settings
end
return M
