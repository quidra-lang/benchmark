local Q = {}
Q.__index = Q
local function gcd(a, b)
    a, b = math.abs(a), math.abs(b)
    while b ~= 0 do a, b = b, a % b end
    return a
end
function Q.new(n, d)
    if getmetatable(n) == Q then return n end
    d = d or 1
    assert(d ~= 0)
    if d < 0 then n, d = -n, -d end
    local divisor = gcd(n, d)
    return setmetatable({ n = n // divisor, d = d // divisor }, Q)
end
function Q.__add(a, b)
    a, b = Q.new(a), Q.new(b)
    return Q.new(a.n * b.d + b.n * a.d, a.d * b.d)
end
function Q.__sub(a, b)
    a, b = Q.new(a), Q.new(b)
    return Q.new(a.n * b.d - b.n * a.d, a.d * b.d)
end
function Q.__mul(a, b)
    a, b = Q.new(a), Q.new(b)
    return Q.new(a.n * b.n, a.d * b.d)
end
function Q.__div(a, b)
    a, b = Q.new(a), Q.new(b)
    return Q.new(a.n * b.d, a.d * b.n)
end
function Q.__unm(a) return Q.new(-a.n, a.d) end
function Q.__eq(a, b) return a.n == b.n and a.d == b.d end
function Q.__lt(a, b)
    a, b = Q.new(a), Q.new(b)
    return a.n * b.d < b.n * a.d
end
function Q.__le(a, b)
    a, b = Q.new(a), Q.new(b)
    return a.n * b.d <= b.n * a.d
end
function Q.__tostring(a)
    if a.d == 1 then return tostring(a.n) end
    return a.n .. "/" .. a.d
end
function Q.__concat(a, b) return tostring(a) .. tostring(b) end
function Q.floor(a) return a.n // a.d end
function Q.ceil(a) return -((-a.n) // a.d) end
function Q.abs(a) return Q.new(math.abs(a.n), a.d) end
function Q.approximate(a)
    local scaled = (2 * math.abs(a.n) * 1000000 + a.d) // (2 * a.d)
    return (a.n < 0 and scaled > 0 and "-" or "") .. string.format("%d.%06d", scaled // 1000000, scaled % 1000000)
end
function Q.endpoint(a, lower)
    if not a then return lower and "-inf" or "inf" end
    return tostring(a)
end
function Q.read(word, signed)
    if not word then return false end
    local sign = 1
    if signed and word:sub(1, 1) == "-" then sign, word = -1, word:sub(2) end
    local a, b = word:match("^([0-9]+)/([0-9]+)$")
    if a then
        if tonumber(b) == 0 then return false end
        return Q.new(sign * tonumber(a), tonumber(b))
    end
    a, b = word:match("^([0-9]+)%.([0-9]+)$")
    if a then
        local denominator = 1
        for _ = 1, #b do denominator = denominator * 10 end
        return Q.new(sign * tonumber(a .. b), denominator)
    end
    if word:match("^[0-9]+$") then return Q.new(sign * tonumber(word)) end
    return false
end
Q.zero, Q.one = Q.new(0), Q.new(1)
return Q
