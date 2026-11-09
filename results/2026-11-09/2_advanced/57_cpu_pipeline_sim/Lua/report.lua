local M = {}
function M.decimal(p, q)
    local n = (2 * p * 10000 + q) // (2 * q)
    return string.format('%d.%04d', n // 10000, n % 10000)
end
function M.percentage(p, q)
    if q == 0 then return '-' end
    local n = (2 * p * 10000 + q) // (2 * q)
    return string.format('%d.%02d', n // 100, n % 100)
end
function M.fraction(p, q)
    local a, b = p, q
    while b ~= 0 do a, b = b, a % b end
    return (p // a) .. '/' .. (q // a)
end
function M.hex(value) return string.format('%08x', value) end
function M.register(value) return value and 'r' .. value or '-' end
function M.heading(first, last)
    local digits = {}
    for cycle = first, last do digits[#digits + 1] = tostring(cycle % 10) end
    return 'cycle' .. string.rep(' ', 18) .. table.concat(digits)
end
function M.row(number, pc, kind, characters, annotation)
    return string.format('%6s %s %-6s %s%s', number and tostring(number) or '-', M.hex(pc), kind, characters, annotation)
end
function M.join(parts)
    local result = {}
    for i, part in ipairs(parts) do
        if i > 1 then result[#result + 1] = '' end
        for _, line in ipairs(part) do result[#result + 1] = line end
    end
    return result
end
function M.write(name, lines)
    local output = assert(io.open('output/' .. name, 'w'))
    output:write(table.concat(lines, '\n'), '\n')
    output:close()
end
return M
