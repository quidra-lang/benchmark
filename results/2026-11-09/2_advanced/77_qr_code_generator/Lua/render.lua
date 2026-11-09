local render = {}
function render.symbol_lines(symbol)
    local lines = {}
    for _, row in ipairs(symbol) do
        local characters = {}; for _, value in ipairs(row) do characters[#characters + 1] = value == 1 and '#' or '.' end
        lines[#lines + 1] = table.concat(characters)
    end
    return lines
end
function render.pbm_text(symbol, quiet_zone, scale)
    local width = (#symbol + 2 * quiet_zone) * scale
    local margin, empty, lines = string.rep('0', quiet_zone * scale), string.rep('0', width), {'P1', width .. ' ' .. width}
    for _ = 1, quiet_zone * scale do lines[#lines + 1] = empty end
    for _, row in ipairs(symbol) do
        local pixels = {}; for _, value in ipairs(row) do pixels[#pixels + 1] = string.rep(tostring(value), scale) end
        local text = margin .. table.concat(pixels) .. margin
        for _ = 1, scale do lines[#lines + 1] = text end
    end
    for _ = 1, quiet_zone * scale do lines[#lines + 1] = empty end
    return table.concat(lines, '\n') .. '\n'
end
return render
