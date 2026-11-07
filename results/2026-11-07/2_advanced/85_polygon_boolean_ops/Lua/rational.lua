local Rational = {}

function Rational.gcd(a, b)
    a, b = math.abs(a), math.abs(b)
    while b ~= 0 do a, b = b, a % b end
    return a
end

function Rational.point(x, y, d)
    d = d or 1
    if d < 0 then x, y, d = -x, -y, -d end
    local divisor = Rational.gcd(Rational.gcd(x, y), d)
    return {x = x // divisor, y = y // divisor, d = d // divisor}
end

function Rational.equal(a, b)
    return a.x == b.x and a.y == b.y and a.d == b.d
end

function Rational.key(point)
    return point.x .. ":" .. point.y .. ":" .. point.d
end

function Rational.x_less(a, b)
    return a.x * b.d < b.x * a.d
end

function Rational.y_less(a, b)
    return a.y * b.d < b.y * a.d
end

function Rational.less(a, b)
    local first, second = a.y * b.d, b.y * a.d
    return first == second and Rational.x_less(a, b) or first < second
end

function Rational.fraction(n, d)
    local divisor = Rational.gcd(n, d)
    n, d = n // divisor, d // divisor
    return d == 1 and tostring(n) or n .. "/" .. d
end

function Rational.text(point)
    return "(" .. Rational.fraction(point.x, point.d) .. "," .. Rational.fraction(point.y, point.d) .. ")"
end

function Rational.segment(a, b)
    return Rational.text(a) .. "-" .. Rational.text(b)
end

function Rational.real(point)
    return (point.x + 0.0) / (point.d + 0.0), (point.y + 0.0) / (point.d + 0.0)
end

function Rational.snapped(point)
    return Rational.point((2 * point.x + point.d) // (2 * point.d), (2 * point.y + point.d) // (2 * point.d))
end

function Rational.line_cross(a, b, point)
    return (b.x - a.x) * (point.y - a.y * point.d) - (b.y - a.y) * (point.x - a.x * point.d)
end

local base = 65536

local function digits(value)
    local result = {}
    while value > 0 do result[#result + 1], value = value % base, value // base end
    return result
end

local function multiply(first, second)
    local result = {}
    for i = 1, #first + #second + 1 do result[i] = 0 end
    for i, a in ipairs(first) do
        for j, b in ipairs(second) do result[i + j - 1] = result[i + j - 1] + a * b end
    end
    for i = 1, #result - 1 do
        local carry = result[i] // base
        result[i], result[i + 1] = result[i] % base, result[i + 1] + carry
    end
    while #result > 0 and result[#result] == 0 do result[#result] = nil end
    return result
end

local function add_product(total, a, b, c)
    local product = multiply(multiply(digits(a), digits(b)), digits(c))
    local carry = 0
    for i = 1, math.max(#total, #product) do
        local value = (total[i] or 0) + (product[i] or 0) + carry
        total[i], carry = value % base, value // base
    end
    if carry > 0 then total[#total + 1] = carry end
end

local function signed_product(positive, negative, sign, a, b, c)
    if a < 0 then a, sign = -a, -sign end
    if b < 0 then b, sign = -b, -sign end
    if c < 0 then c, sign = -c, -sign end
    add_product(sign > 0 and positive or negative, a, b, c)
end

function Rational.cross(a, b, c)
    if a.d == 1 and b.d == 1 then return Rational.line_cross(a, b, c) end
    local positive, negative = {}, {}
    signed_product(positive, negative, 1, b.x, c.y, a.d)
    signed_product(positive, negative, 1, c.x, a.y, b.d)
    signed_product(positive, negative, 1, a.x, b.y, c.d)
    signed_product(positive, negative, -1, b.y, c.x, a.d)
    signed_product(positive, negative, -1, c.y, a.x, b.d)
    signed_product(positive, negative, -1, a.y, b.x, c.d)
    for i = math.max(#positive, #negative), 1, -1 do
        local first, second = positive[i] or 0, negative[i] or 0
        if first ~= second then return first < second and -1 or 1 end
    end
    return 0
end

function Rational.ring(points)
    points.lines = {}
    for i, point in ipairs(points) do points.lines[i] = {a = point, b = points[i % #points + 1]} end
    return points
end

return Rational
