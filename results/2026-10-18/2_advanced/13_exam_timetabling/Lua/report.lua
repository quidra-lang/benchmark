local M = {}

function M.fixed_width_line(label, cells, label_width, cell_width)
    local parts = {string.format("%-" .. label_width .. "s", label)}
    for _, cell in ipairs(cells) do
        parts[#parts + 1] = string.format("%" .. cell_width .. "s", tostring(cell))
    end
    return table.concat(parts)
end

function M.rounded_percent(part, whole)
    return (200 * part + whole) // (2 * whole)
end

function M.write_files(directory, files)
    assert(os.execute('mkdir -p "' .. directory .. '"'))
    for _, entry in ipairs(files) do
        local file = assert(io.open(directory .. "/" .. entry[1], "w"))
        file:write(table.concat(entry[2], "\n"), "\n")
        file:close()
    end
end

return M
