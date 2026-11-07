local Grid = require("grid_map")
local Report = {}

function Report.cell(cell)
    local x, y = Grid.xy(cell)
    return x .. "," .. y
end

function Report.agent(index)
    return string.char(64 + index)
end

function Report.actions(path)
    local result = {}
    for i = 2, #path do
        local x, y = Grid.xy(path[i])
        local px, py = Grid.xy(path[i - 1])
        result[#result + 1] = x > px and "E" or x < px and "W" or y > py and "S" or y < py and "N" or "."
    end
    return table.concat(result)
end

function Report.conflict(conflict)
    local prefix = string.format("%s t %d %s %s", conflict.kind, conflict.time,
        Report.agent(conflict.a), Report.agent(conflict.b))
    if conflict.kind == "vertex" then return prefix .. " at " .. Report.cell(conflict.cell) end
    return prefix .. " from " .. Report.cell(conflict.source) .. " to " .. Report.cell(conflict.destination)
end

function Report.fraction(numerator, denominator)
    local a, b = numerator, denominator
    while b ~= 0 do a, b = b, a % b end
    return numerator // a .. "/" .. denominator // a
end

function Report.csv(values)
    return table.concat(values, ",")
end

function Report.picture(grid, placements)
    local rows = {}
    for y = 0, grid.height - 1 do
        local row = {}
        for x = 0, grid.width - 1 do
            row[#row + 1] = placements[y * grid.width + x + 1] or grid.rows[y + 1]:sub(x + 1, x + 1)
        end
        rows[#rows + 1] = table.concat(row)
    end
    return rows
end

function Report.save(name, lines)
    local file = assert(io.open("output/" .. name, "wb"))
    for _, line in ipairs(lines) do file:write(line, "\n") end
    file:close()
end

return Report
