local M = {}
function M.real(value)
    local rounded = math.floor(math.abs(value) * 10000 + 0.5)
    local sign = value < 0 and rounded ~= 0 and "-" or ""
    return sign .. string.format("%d.%04d", rounded // 10000, rounded % 10000)
end
function M.write(name, rows)
    local output = assert(io.open("output/" .. name, "w"))
    output:write(table.concat(rows, "\n"), "\n")
    output:close()
end
function M.csv(name, header, rows)
    local lines = {header}
    for _, row in ipairs(rows) do lines[#lines + 1] = table.concat(row, ",") end
    M.write(name, lines)
end
function M.shades(grid, fs, length, band_db, maximum)
    local levels, result = " .:-=+*#%@", {}
    for k = length // 2, 0, -1 do
        local pixels = {}
        for t, row in ipairs(grid) do
            local d = 20 * math.log(row[k + 1] / maximum, 10)
            local level = math.max(0, 9 - math.floor(-d / band_db))
            pixels[t] = levels:sub(level + 1, level + 1)
        end
        result[#result + 1] = string.format("%9s |%s|", M.real(k * fs / length), table.concat(pixels))
    end
    return result
end
return M
