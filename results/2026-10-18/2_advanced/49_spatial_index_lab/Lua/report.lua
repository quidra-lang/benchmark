local M = {}
function M.fraction(numerator, denominator)
    local first, second = numerator, denominator
    while second ~= 0 do
        first, second = second, first % second
    end
    return numerator // first .. "/" .. denominator // first
end
function M.ids(values)
    return #values == 0 and "-" or table.concat(values, " ")
end
function M.distances(values)
    local fields = {}
    for _, value in ipairs(values) do
        fields[#fields + 1] = value[1] .. ":" .. value[2]
    end
    return #fields == 0 and "-" or table.concat(fields, " ")
end
function M.write(name, lines)
    local file = assert(io.open("output/" .. name, "w"))
    for _, line in ipairs(lines) do
        file:write(line, "\n")
    end
    file:close()
end
return M
