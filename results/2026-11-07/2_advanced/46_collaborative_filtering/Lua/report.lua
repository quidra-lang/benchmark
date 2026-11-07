local M = {}
function M.real(value)
    if value == nil then
        return "-"
    end
    local result = string.format("%.4f", value)
    return result == "-0.0000" and "0.0000" or result
end
function M.save(name, lines)
    local file = assert(io.open("output/" .. name, "w"))
    for _, line in ipairs(lines) do
        file:write(line, "\n")
    end
    file:close()
end
return M
