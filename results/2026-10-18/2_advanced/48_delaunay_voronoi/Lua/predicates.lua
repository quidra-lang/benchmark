local M = {}
function M.orient(p, q, r)
    return (q[1] - p[1]) * (r[2] - p[2]) - (q[2] - p[2]) * (r[1] - p[1])
end
function M.d2(p, q)
    local x, y = p[1] - q[1], p[2] - q[2]
    return x * x + y * y
end
function M.dot(o, p, q)
    return (p[1] - o[1]) * (q[1] - o[1]) + (p[2] - o[2]) * (q[2] - o[2])
end
function M.incircle(a, b, c, d)
    local ax, ay, bx, by = a[1] - d[1], a[2] - d[2], b[1] - d[1], b[2] - d[2]
    local cx, cy = c[1] - d[1], c[2] - d[2]
    local aa, bb, cc = ax * ax + ay * ay, bx * bx + by * by, cx * cx + cy * cy
    return ax * (by * cc - bb * cy) - ay * (bx * cc - bb * cx) + aa * (bx * cy - by * cx)
end
function M.center(a, b, c)
    local bx, by, cx, cy = b[1] - a[1], b[2] - a[2], c[1] - a[1], c[2] - a[2]
    local bb, cc = bx * bx + by * by, cx * cx + cy * cy
    local d = 2 * (bx * cy - by * cx)
    return {a[1] * d + cy * bb - by * cc, a[2] * d + bx * cc - cx * bb, d}
end
function M.gcd(first, second)
    first, second = math.abs(first), math.abs(second)
    while second ~= 0 do
        first, second = second, first % second
    end
    return first
end
function M.fraction(numerator, denominator)
    local common = M.gcd(numerator, denominator)
    numerator, denominator = numerator // common, denominator // common
    if denominator == 1 then
        return tostring(numerator)
    end
    return numerator .. "/" .. denominator
end
function M.direction(x, y)
    local common = M.gcd(x, y)
    return {x // common, y // common}
end
return M
