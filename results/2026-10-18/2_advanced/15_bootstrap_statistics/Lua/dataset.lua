local M = {}

local function lines(path)
    local result = {}
    for line in io.lines(path) do result[#result + 1] = line end
    return result
end

function M.hundredths(text)
    local whole, fraction = text:match("^(%d+)%.?(%d*)$")
    return tonumber(whole) * 100 + tonumber((fraction .. "00"):sub(1, 2))
end

function M.load(directory)
    local groups, by_name = {}, {}
    for index, line in ipairs(lines(directory .. "/samples.csv")) do
        if index > 1 then
            local name, text = line:match("^([^,]+),(.+)$")
            if not by_name[name] then
                local group = {number = #groups + 1, name = name, sample = {}}
                by_name[name], groups[#groups + 1] = group, group
            end
            local sample = by_name[name].sample
            sample[#sample + 1] = M.hundredths(text)
        end
    end
    local before, after, differences = {}, {}, {}
    for index, line in ipairs(lines(directory .. "/paired.csv")) do
        if index > 1 then
            local first, second = line:match("^[^,]+,([^,]+),([^,]+)$")
            local b, a = M.hundredths(first), M.hundredths(second)
            before[#before + 1], after[#after + 1], differences[#differences + 1] = b, a, a - b
        end
    end
    local settings, pairs_list = {}, {}
    for _, line in ipairs(lines(directory .. "/params.txt")) do
        local fields = {}
        for field in line:gmatch("%S+") do fields[#fields + 1] = field end
        local key = fields[1]
        if key == "compare" then
            pairs_list[#pairs_list + 1] = {first = by_name[fields[2]], second = by_name[fields[3]],
                name = fields[2] .. "-" .. fields[3], number = #pairs_list + 1}
        elseif key == "power" then settings.power_sims, settings.power_perms = tonumber(fields[2]), tonumber(fields[3])
        else settings[key] = tonumber(fields[2]) end
    end
    return {groups = groups, before = before, after = after, differences = differences, settings = settings, pairs = pairs_list}
end

return M
