local M = {}
function M.decimal(value, places)
    local text = string.format('%.' .. places .. 'f', value)
    if text:sub(1, 1) == '-' and tonumber(text) == 0 then return text:sub(2) end
    return text
end
function M.write_lines(name, lines)
    local file = assert(io.open('output/' .. name, 'w'))
    file:write(table.concat(lines, '\n'), '\n'); file:close()
end
function M.plot_lines(grid, labels, label_width, s)
    local rows = (s.plot_top - s.plot_bottom) // s.plot_step + 1
    local lines = {}
    for r = 0, rows - 1 do
        local cells = {}
        for col = 0, s.plot_hours - 1 do cells[#cells + 1] = grid[r][col] end
        lines[#lines + 1] = string.rep(' ', label_width - #labels[r]) .. labels[r] .. ' |' .. table.concat(cells) .. '|'
    end
    local axis = {}
    for col = 0, s.plot_hours - 1 do axis[#axis + 1] = col % 6 == 0 and '+' or '-' end
    lines[#lines + 1] = string.rep(' ', label_width) .. ' +' .. table.concat(axis) .. '+'
    return lines
end
return M
