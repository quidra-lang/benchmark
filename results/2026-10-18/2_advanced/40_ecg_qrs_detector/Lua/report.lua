local M = {}
function M.rdiv(a, b)
    return (2 * a + b) // (2 * b)
end
function M.two(value)
    local magnitude = math.abs(value)
    return (value < 0 and "-" or "") .. (magnitude // 100) .. "." .. string.format("%02d", magnitude % 100)
end
function M.four(value)
    return (value // 10000) .. "." .. string.format("%04d", value % 10000)
end
function M.fraction(a, b)
    local first, second = a, b
    while second ~= 0 do
        first, second = second, first % second
    end
    return (a // first) .. "/" .. (b // first)
end
function M.ratio(a, b)
    if b == 0 then
        return a .. "/0 none"
    end
    return a .. "/" .. b .. " reduced=" .. M.fraction(a, b) .. " percent=" .. M.two(M.rdiv(10000 * a, b))
end
function M.maybe_two(value)
    return value == nil and "none" or M.two(value)
end
function M.missing(value)
    return value == nil and "-" or tostring(value)
end
return M
