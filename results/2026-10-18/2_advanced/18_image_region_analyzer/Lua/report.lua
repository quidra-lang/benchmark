local M = {}

function M.decimal(numerator, denominator, digits)
    local scale = 1
    for _ = 1, digits do scale = scale * 10 end
    local scaled = (2 * scale * math.abs(numerator) + denominator) // (2 * denominator)
    local sign = numerator < 0 and scaled > 0 and "-" or ""
    return sign .. (scaled // scale) .. "." .. string.format("%0" .. digits .. "d", scaled % scale)
end

function M.hull_area_text(doubled)
    return (doubled // 2) .. "." .. (doubled % 2 == 1 and "5" or "0")
end

function M.write_files(directory, files)
    os.execute("mkdir -p " .. directory)
    for _, entry in ipairs(files) do
        local file = assert(io.open(directory .. "/" .. entry[1], "w"))
        for _, line in ipairs(entry[2]) do file:write(line, "\n") end
        file:close()
    end
end

return M
