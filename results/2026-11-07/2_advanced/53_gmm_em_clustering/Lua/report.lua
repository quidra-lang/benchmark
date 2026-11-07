local M = {levels = " .:-=+*#%@"}
function M.scaled(value, places)
    local scale = math.tointeger(10 ^ (places or 4))
    local magnitude = math.floor(math.abs(value) * scale + 0.5)
    return value < 0 and -magnitude or magnitude
end
function M.dec(value, places)
    places = places or 4
    local scale = math.tointeger(10 ^ places)
    local rounded = M.scaled(value, places)
    local sign = rounded < 0 and "-" or ""
    rounded = math.abs(rounded)
    return sign .. string.format("%d.%0" .. places .. "d", rounded // scale, rounded % scale)
end
function M.optional(value)
    return value == nil and "-" or M.dec(value)
end
function M.integers(values)
    local result = {}
    for i, value in ipairs(values) do result[i] = tostring(value) end
    return table.concat(result, " ")
end
function M.values(values)
    local result = {}
    for i, value in ipairs(values) do result[i] = M.dec(value) end
    return table.concat(result, " ")
end
function M.framed(grid)
    local border = "+" .. string.rep("-", #grid[1]) .. "+"
    local result = {border}
    for _, row in ipairs(grid) do result[#result + 1] = "|" .. table.concat(row) .. "|" end
    result[#result + 1] = border
    return result
end
function M.write(name, rows)
    local output = assert(io.open("output/" .. name, "w"))
    output:write(table.concat(rows, "\n"), "\n")
    output:close()
end
function M.blocks(name, blocks)
    local rows = {}
    for i, block in ipairs(blocks) do
        if i > 1 then rows[#rows + 1] = "" end
        for _, line in ipairs(block) do rows[#rows + 1] = line end
    end
    M.write(name, rows)
end
return M
