local M = {}
function M.fraction(a, b)
    local x, y = math.abs(a), b
    while y ~= 0 do
        x, y = y, x % y
    end
    return (a // x) .. "/" .. (b // x)
end
function M.root(value)
    return string.format("%.3f", math.sqrt(value))
end
function M.ari(a, b)
    local value = string.format("%.4f", a / b)
    if value == "-0.0000" then
        value = "0.0000"
    end
    return M.fraction(a, b) .. " " .. value
end
function M.framed(rows, width)
    local border = "+" .. string.rep("-", width) .. "+"
    local result = {border}
    for _, row in ipairs(rows) do
        result[#result + 1] = "|" .. row .. "|"
    end
    result[#result + 1] = border
    return result
end
function M.write(name, lines)
    local file = assert(io.open("output/" .. name, "w"))
    for _, line in ipairs(lines) do
        file:write(line, "\n")
    end
    file:close()
end
return M
