local R = {}
function R.fmt(value, places)
    local text = string.format("%." .. (places or 4) .. "f", value)
    return text:sub(1, 1) == "-" and tonumber(text) == 0 and text:sub(2) or text
end
function R.curve_plot(observed, fitted)
    local days, maximum = #observed, math.max(table.unpack(observed))
    local width, grid = #tostring(maximum), {}
    for row = 1, 20 do grid[row] = {}; for column = 1, 70 do grid[row][column] = "." end end
    for column = 0, 69 do
        local day = column * (days - 1) // 69 + 1
        local actual, model = math.min(19, 20 * observed[day] // maximum) + 1, math.min(19, math.floor(20 * fitted[day] / maximum)) + 1
        grid[actual][column + 1] = "o"
        grid[model][column + 1] = actual == model and "#" or "*"
    end
    local lines = { "plot observed o fitted * both # days 1 " .. days .. " max " .. maximum }
    for row = 19, 0, -1 do lines[#lines + 1] = string.format("%" .. width .. "d |%s", maximum * row // 20, table.concat(grid[row + 1])) end
    local ticks, labels = {}, {}
    for column = 0, 69 do ticks[column + 1], labels[column + 1] = column % 10 == 0 and "+" or "-", " " end
    lines[#lines + 1] = string.rep(" ", width + 1) .. "+" .. table.concat(ticks)
    for column = 0, 60, 10 do
        local label = tostring(1 + column * (days - 1) // 69)
        for i = 1, #label do labels[column + i] = label:sub(i, i) end
    end
    lines[#lines + 1] = (string.rep(" ", width + 2) .. table.concat(labels)):gsub(" +$", "")
    return lines
end
return R
