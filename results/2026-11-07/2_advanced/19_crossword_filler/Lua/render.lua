local M = {}

function M.decimal(numerator, denominator, places)
    local scale = 1
    for _ = 1, places do scale = scale * 10 end
    local rounded = (2 * numerator * scale + denominator) // (2 * denominator)
    return (rounded // scale) .. "." .. string.format("%0" .. places .. "d", rounded % scale)
end

function M.grid_lines(grid, letters)
    local lines = {}
    for row = 0, grid.height - 1 do
        lines[#lines + 1] = table.concat(letters, "", row * grid.width + 1, (row + 1) * grid.width)
    end
    return lines
end

function M.number_lines(layout)
    local grid, lines = layout.grid, {}
    for row = 0, grid.height - 1 do
        local marks = {}
        for column = 0, grid.width - 1 do
            local cell = grid:cell(row, column)
            if not grid:is_open(row, column) then marks[#marks + 1] = "##"
            elseif layout.numbers[cell] then marks[#marks + 1] = string.format("%2d", layout.numbers[cell])
            else marks[#marks + 1] = " ." end
        end
        lines[#lines + 1] = table.concat(marks, " ")
    end
    return lines
end

function M.list_line(slot, clue, entry, score, theme)
    return slot.number .. ". " .. clue .. " (" .. slot.length .. ") " .. entry .. " " .. score .. (theme and " theme" or "")
end

return M
