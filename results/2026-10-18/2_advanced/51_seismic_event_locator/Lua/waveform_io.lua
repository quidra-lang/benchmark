local M = {}
local function read_lines(path)
    local result = {}
    for line in io.lines(path) do
        result[#result + 1] = line
    end
    return result
end
function M.read()
    local stations = {}
    local rows = read_lines("input/stations.csv")
    for index = 2, #rows do
        local code, x, y, elevation = rows[index]:match("([^,]+),([^,]+),([^,]+),([^,]+)")
        stations[#stations + 1] = {code = code, x = tonumber(x), y = tonumber(y), elevation = tonumber(elevation)}
    end
    local waveforms, cursor = read_lines("input/waveforms.txt"), 1
    for _, station in ipairs(stations) do
        local _, start, count = waveforms[cursor]:match("STATION ([^ ]+) ([^ ]+) ([^ ]+)")
        station.start, count = tonumber(start), tonumber(count)
        station.samples = {}
        cursor = cursor + 1
        while #station.samples < count do
            for value in waveforms[cursor]:gmatch("[^ ]+") do
                station.samples[#station.samples + 1] = tonumber(value)
            end
            cursor = cursor + 1
        end
    end
    local params = {}
    for _, line in ipairs(read_lines("input/params.txt")) do
        local name, tail = line:match("([^ ]+) (.+)")
        local values = {}
        for value in tail:gmatch("[^ ]+") do
            values[#values + 1] = tonumber(value)
        end
        params[name] = #values == 1 and values[1] or values
    end
    return stations, params
end
return M
