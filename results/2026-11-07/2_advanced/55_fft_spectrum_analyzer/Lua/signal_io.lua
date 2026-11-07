local M = {}
function M.read()
    local input = assert(io.open("input/signal.csv", "r"))
    local fs, count = input:read("l"):match("(%d+),(%d+)")
    local first, second = {}, {}
    for line in input:lines() do
        local x, y = line:match("([^,]+),([^,]+)")
        first[#first + 1], second[#second + 1] = tonumber(x), tonumber(y)
    end
    input:close()
    local params = {}
    input = assert(io.open("input/params.txt", "r"))
    for line in input:lines() do
        local fields = {}
        for field in line:gmatch("%S+") do fields[#fields + 1] = tonumber(field) or field end
        local key = table.remove(fields, 1)
        params[key] = fields
    end
    input:close()
    return tonumber(fs), first, second, params
end
return M
