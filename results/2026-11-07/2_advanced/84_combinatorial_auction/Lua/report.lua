local Report = {}
local Fraction = {}
Fraction.__index = Fraction

local function gcd(a, b)
    a, b = math.abs(a), math.abs(b)
    while b ~= 0 do a, b = b, a % b end
    return a
end

function Fraction.new(numerator, denominator)
    if type(numerator) == "table" then return numerator end
    denominator = denominator or 1
    if denominator < 0 then numerator, denominator = -numerator, -denominator end
    local divisor = gcd(numerator, denominator)
    return setmetatable({n = numerator // divisor, d = denominator // divisor}, Fraction)
end

function Fraction.__add(a, b)
    a, b = Fraction.new(a), Fraction.new(b)
    local divisor = gcd(a.d, b.d)
    return Fraction.new(a.n * (b.d // divisor) + b.n * (a.d // divisor), a.d * (b.d // divisor))
end

function Fraction.__sub(a, b)
    b = Fraction.new(b)
    return Fraction.new(a) + Fraction.new(-b.n, b.d)
end

function Fraction.__mul(a, b)
    a, b = Fraction.new(a), Fraction.new(b)
    local first, second = gcd(a.n, b.d), gcd(b.n, a.d)
    return Fraction.new((a.n // first) * (b.n // second), (a.d // second) * (b.d // first))
end

function Fraction.__div(a, b)
    b = Fraction.new(b)
    return Fraction.new(a) * Fraction.new(b.d, b.n)
end

function Fraction.__lt(a, b)
    a, b = Fraction.new(a), Fraction.new(b)
    return a.n * b.d < b.n * a.d
end

function Fraction.__le(a, b)
    a, b = Fraction.new(a), Fraction.new(b)
    return a.n * b.d <= b.n * a.d
end

function Fraction.__eq(a, b)
    return a.n == b.n and a.d == b.d
end

function Fraction.__tostring(value)
    if value.d == 1 then return tostring(value.n) end
    return value.n .. "/" .. value.d
end

Report.Fraction = Fraction

function Report.fraction(value)
    return tostring(Fraction.new(value))
end

function Report.bundle(mask, items)
    local names = {}
    for _, item in ipairs(items) do if mask & item.bit ~= 0 then names[#names + 1] = item.name end end
    return #names == 0 and "-" or table.concat(names, "+")
end

function Report.write(reports)
    assert(os.execute("mkdir -p output"))
    for _, report in ipairs(reports) do
        local file = assert(io.open("output/" .. report[1], "wb"))
        for _, line in ipairs(report[2]) do file:write(line, "\n") end
        file:close()
    end
end

return Report
