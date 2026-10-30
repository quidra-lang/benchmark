local M = {}
function M.decimal(value, digits)
    digits = digits or 3
    local scale = 10 ^ digits
    local rounded = math.floor(math.abs(value) * scale + 0.5)
    local integer, fraction = rounded // math.tointeger(scale), rounded % math.tointeger(scale)
    local prefix = value < 0 and rounded ~= 0 and '-' or ''
    return prefix .. integer .. '.' .. string.format('%0' .. digits .. 'd', fraction)
end
function M.signed(number) return number > 0 and '+' .. number or tostring(number) end
function M.chart(rows)
    local border = '+' .. string.rep('-', #rows[1]) .. '+'
    local result = {border}
    for _, row in ipairs(rows) do result[#result + 1] = '|' .. row .. '|' end
    result[#result + 1] = border
    return result
end
function M.write_lines(name, lines)
    local file = assert(io.open('output/' .. name, 'wb'))
    if #lines > 0 then file:write(table.concat(lines, '\n'), '\n') end
    file:close()
end
return M
