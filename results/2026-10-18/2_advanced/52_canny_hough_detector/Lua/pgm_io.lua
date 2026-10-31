local M = {}
local function lines(path)
    local result = {}
    for line in io.lines(path) do
        result[#result + 1] = line
    end
    return result
end
local function integers(line)
    local result = {}
    for value in line:gmatch("[^ ]+") do
        result[#result + 1] = assert(math.tointeger(tonumber(value)))
    end
    return result
end
function M.read()
    local rows, image = lines("input/image.pgm"), {}
    for index = 4, #rows do
        image[#image + 1] = integers(rows[index])
    end
    local trig = {}
    for _, line in ipairs(lines("input/trig.txt")) do
        local values = integers(line)
        trig[values[1]] = {values[2], values[3]}
    end
    local params = {}
    for _, line in ipairs(lines("input/params.txt")) do
        local name, tail = line:match("([^ ]+) (.+)")
        local values = integers(tail)
        params[name] = name == "gauss_kernel" and values or values[1]
    end
    return image, trig, params
end
function M.write_lines(name, rows)
    local output = assert(io.open("output/" .. name, "w"))
    output:write(table.concat(rows, "\n"), "\n")
    output:close()
end
function M.write_pgm(name, image)
    local rows = {"P2", #image[1] .. " " .. #image, "255"}
    for _, row in ipairs(image) do
        local values = {}
        for _, value in ipairs(row) do
            values[#values + 1] = tostring(value)
        end
        rows[#rows + 1] = table.concat(values, " ")
    end
    M.write_lines(name, rows)
end
return M
