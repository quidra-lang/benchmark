local M = {}
local Fraction = {}
Fraction.__index = Fraction
local function gcd(a, b)
    a = math.abs(a)
    while b ~= 0 do a, b = b, a % b end
    return a
end
function M.rational(n, d)
    d = d or 1
    if d < 0 then n, d = -n, -d end
    local g = gcd(n, d)
    return setmetatable({n = n // g, d = d // g}, Fraction)
end
local function as_fraction(x) return type(x) == 'number' and M.rational(x) or x end
function Fraction.__add(a, b)
    a, b = as_fraction(a), as_fraction(b)
    local g = gcd(a.d, b.d)
    return M.rational(a.n * (b.d // g) + b.n * (a.d // g), (a.d // g) * b.d)
end
function Fraction.__unm(a) return M.rational(-a.n, a.d) end
function Fraction.__sub(a, b) return as_fraction(a) + -as_fraction(b) end
function Fraction.__mul(a, b)
    a, b = as_fraction(a), as_fraction(b)
    local g, h = gcd(a.n, b.d), gcd(b.n, a.d)
    return M.rational((a.n // g) * (b.n // h), (a.d // h) * (b.d // g))
end
function Fraction.__div(a, b)
    a, b = as_fraction(a), as_fraction(b)
    return a * M.rational(b.d, b.n)
end
function Fraction.__lt(a, b)
    a, b = as_fraction(a), as_fraction(b)
    return a.n * b.d < b.n * a.d
end
function Fraction.__le(a, b)
    a, b = as_fraction(a), as_fraction(b)
    return a.n * b.d <= b.n * a.d
end
function M.fraction(value)
    value = as_fraction(value)
    local sign = value.n < 0 and '-' or ''
    local scaled = 10000 * math.abs(value.n) // value.d
    return sign .. math.abs(value.n) .. '/' .. value.d .. '=' .. (scaled > 0 and sign or '') .. string.format('%d.%04d', scaled // 10000, scaled % 10000)
end
function M.percentage(a, b)
    local scaled = 10000 * a // b
    return string.format('%d.%02d%%', scaled // 100, scaled % 100)
end
function M.names(a) return #a == 0 and '-' or table.concat(a, ',') end
function M.write(outputs)
    for name, lines in pairs(outputs) do
        local file = assert(io.open('output/' .. name, 'w'))
        file:write(table.concat(lines, '\n'), '\n'); file:close()
    end
end
return M
