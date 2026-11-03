local M = {}
function M.grid(width, height)
    local result = {}
    for row = 1, height do
        result[row] = {}
        for column = 1, width do
            result[row][column] = " "
        end
    end
    return result
end
function M.frame(grid)
    local border = "+" .. string.rep("-", #grid[1]) .. "+"
    local result = {border}
    for _, row in ipairs(grid) do
        result[#result + 1] = "|" .. table.concat(row) .. "|"
    end
    result[#result + 1] = border
    return result
end
function M.cell(x, y, maximum_x, maximum_y, width, height)
    local column = math.min(math.floor((x + maximum_x) / (2.0 * maximum_x) * width), width - 1)
    local row = math.min(math.floor((maximum_y - y) / (2.0 * maximum_y) * height), height - 1)
    return row + 1, column + 1
end
function M.diagnostic_cell(t2, spe, maximum_x, maximum_y, width, height)
    local column = math.min(math.floor(t2 / maximum_x * width), width - 1)
    local row = height - 1 - math.min(math.floor(spe / maximum_y * height), height - 1)
    return row + 1, column + 1
end
local function sign(value)
    return value < 0 and -1 or value > 0 and 1 or 0
end
function M.shaft(origin_row, origin_column, tip_row, tip_column)
    local dc, dr = tip_column - origin_column, tip_row - origin_row
    local steps = math.max(math.abs(dc), math.abs(dr))
    local character
    if 2 * math.abs(dr) <= math.abs(dc) then
        character = "-"
    elseif 2 * math.abs(dc) <= math.abs(dr) then
        character = "|"
    elseif dc * dr < 0 then
        character = "/"
    else
        character = "\\"
    end
    local cells = {}
    for step = 1, steps - 1 do
        local column = origin_column + sign(dc) * ((2 * step * math.abs(dc) + steps) // (2 * steps))
        local row = origin_row + sign(dr) * ((2 * step * math.abs(dr) + steps) // (2 * steps))
        cells[#cells + 1] = {row = row, column = column, character = character}
    end
    return cells
end
function M.scree(width, length, kaiser, broken)
    local cells = {}
    for position = 1, width do
        cells[position] = position == broken and "o" or position == kaiser and ":" or position <= length and "#" or " "
    end
    return table.concat(cells)
end
return M
