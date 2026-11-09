local M = {}
local Fraction = {}
Fraction.__index = Fraction
local function gcd(a, b)
    a = math.abs(a)
    while b ~= 0 do a, b = b, a % b end
    return a
end

function Fraction.new(numerator, denominator)
    denominator = denominator or 1
    if denominator < 0 then numerator, denominator = -numerator, -denominator end
    local divisor = gcd(numerator, denominator)
    return setmetatable({n = numerator // divisor, d = denominator // divisor}, Fraction)
end
local function rational(value) return getmetatable(value) == Fraction and value or Fraction.new(value) end
function Fraction.__add(a, b)
    a, b = rational(a), rational(b)
    local common = gcd(a.d, b.d)
    return Fraction.new(a.n * (b.d // common) + b.n * (a.d // common), a.d // common * b.d)
end
function Fraction.__unm(a) return Fraction.new(-a.n, a.d) end
function Fraction.__sub(a, b) return rational(a) + -rational(b) end
function Fraction.__mul(a, b)
    a, b = rational(a), rational(b)
    local first, second = gcd(a.n, b.d), gcd(b.n, a.d)
    return Fraction.new((a.n // first) * (b.n // second), (a.d // second) * (b.d // first))
end
function Fraction.__div(a, b)
    a, b = rational(a), rational(b)
    return a * Fraction.new(b.d, b.n)
end
function Fraction:real() return self.n / self.d end
function M.compare(a, b)
    if getmetatable(a) == Fraction or getmetatable(b) == Fraction then
        a, b = rational(a), rational(b)
        local first, second = a.n * b.d, b.n * a.d
        return first == second and 0 or first < second and -1 or 1
    end
    return a == b and 0 or a < b and -1 or 1
end
function Fraction.__lt(a, b) return M.compare(a, b) < 0 end
function Fraction.__le(a, b) return M.compare(a, b) <= 0 end
function Fraction.__eq(a, b) return a.n == b.n and a.d == b.d end

function M.fixed(value, places)
    places = places or 4
    if getmetatable(value) == Fraction then
        local magnitude = math.abs(value.n)
        local whole, remainder = magnitude // value.d, magnitude % value.d
        local scale, fraction = 1, 0
        for _ = 1, places do
            remainder = remainder * 10
            fraction = fraction * 10 + remainder // value.d
            remainder = remainder % value.d
            scale = scale * 10
        end
        if 2 * remainder >= value.d then fraction = fraction + 1 end
        if fraction == scale then whole, fraction = whole + 1, 0 end
        local sign = value.n < 0 and (whole > 0 or fraction > 0) and "-" or ""
        return sign .. whole .. "." .. string.format("%0" .. places .. "d", fraction)
    end
    if math.type(value) == "integer" then return value .. "." .. string.rep("0", places) end
    local text = string.format("%." .. places .. "f", value)
    if text:sub(1, 1) == "-" and tonumber(text) == 0 then text = text:sub(2) end
    return text
end
function M.fraction_text(value) return value.n .. "/" .. value.d end
function M.fraction_with_real(value) return M.fraction_text(value) .. " " .. M.fixed(value) end
function M.decimal_value(value, places)
    local scale = 1
    for _ = 1, places do scale = scale * 10 end
    local rounded = math.floor(math.abs(value) * scale + 0.5)
    return value < 0 and -rounded or rounded
end
function M.write_lines(path, lines)
    local file = assert(io.open(path, "w"))
    for _, line in ipairs(lines) do file:write(line, "\n") end
    file:close()
end

M.Fraction = Fraction
return M
