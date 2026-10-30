local M = {}
function M.real(value, places)
    local result = string.format('%.' .. places .. 'f', value)
    if result:sub(1, 1) == '-' and tonumber(result) == 0 then return result:sub(2) end
    return result
end
function M.time(milliseconds) return string.format('%d.%03d', milliseconds // 1000, milliseconds % 1000) end
function M.temperatures(plate, field)
    local result = {}
    for row = 0, plate.height - 1 do
        local values = {}
        for column = 0, plate.width - 1 do values[#values + 1] = M.real(field[row * plate.width + column + 1], 2) end
        result[#result + 1] = table.concat(values, ' ')
    end
    return result
end
function M.isotherms(plate, field, bands)
    local hottest, counts, characters = 1, {}, {}
    for i = 1, #bands + 1 do counts[i] = 0 end
    for p, temperature in ipairs(field) do if temperature > field[hottest] then hottest = p end end
    for p, temperature in ipairs(field) do
        local digit = 0
        for _, band in ipairs(bands) do if temperature >= band then digit = digit + 1 end end
        counts[digit + 1] = counts[digit + 1] + 1
        characters[p] = p == hottest and '*' or tostring(digit)
    end
    local rows = {}
    for row = 0, plate.height - 1 do rows[#rows + 1] = table.concat(characters, '', row * plate.width + 1, (row + 1) * plate.width) end
    return counts, rows
end
function M.write(name, lines)
    local output = assert(io.open('output/' .. name, 'w'))
    output:write(table.concat(lines, '\n'), '\n')
    output:close()
end
return M
