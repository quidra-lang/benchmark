local M = {}

function M.real(value)
    local text = string.format("%.4f", value)
    return text == "-0.0000" and "0.0000" or text
end

function M.reals(values)
    local fields = {}
    for i, value in ipairs(values) do fields[i] = M.real(value) end
    return table.concat(fields, " ")
end

function M.key(value) return tonumber(M.real(value)) end

function M.amount(cents)
    local absolute = math.abs(cents)
    return (cents < 0 and "-" or "") .. string.format("%d.%02d", absolute // 100, absolute % 100)
end

function M.write(name, lines)
    local handle = assert(io.open("output/" .. name, "w"))
    handle:write(table.concat(lines, "\n"), "\n")
    handle:close()
end

return M
