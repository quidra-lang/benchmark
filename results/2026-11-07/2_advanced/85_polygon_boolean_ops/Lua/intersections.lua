local Rational = require("rational")
local Intersections = {}

local function between(value, first, second, less)
    if less(second, first) then first, second = second, first end
    return not less(value, first) and not less(second, value)
end

function Intersections.on_segment(point, first, second, line)
    local cross = line and Rational.line_cross(line.a, line.b, point) or Rational.cross(first, second, point)
    return cross == 0 and between(point, first, second, Rational.x_less) and between(point, first, second, Rational.y_less)
end

local function opposite(a, b)
    return (a < 0 and b > 0) or (a > 0 and b < 0)
end

function Intersections.touch(a, b, c, d)
    return (opposite(Rational.cross(a, b, c), Rational.cross(a, b, d))
        and opposite(Rational.cross(c, d, a), Rational.cross(c, d, b)))
        or Intersections.on_segment(c, a, b) or Intersections.on_segment(d, a, b)
        or Intersections.on_segment(a, c, d) or Intersections.on_segment(b, c, d)
end

function Intersections.overlap(a, b, c, d)
    if Rational.cross(a, b, c) ~= 0 or Rational.cross(a, b, d) ~= 0 then return false end
    local less = a.x * b.d ~= b.x * a.d and Rational.x_less or Rational.y_less
    if less(b, a) then a, b = b, a end
    if less(d, c) then c, d = d, c end
    local low, high = less(a, c) and c or a, less(b, d) and b or d
    return less(low, high)
end

local function positions(a, b, c, d)
    local rx, ry, sx, sy = b.x - a.x, b.y - a.y, d.x - c.x, d.y - c.y
    local denominator = rx * sy - ry * sx
    if denominator == 0 then return nil end
    local gx, gy = c.x - a.x, c.y - a.y
    local t, u = gx * sy - gy * sx, gx * ry - gy * rx
    if denominator < 0 then denominator, t, u = -denominator, -t, -u end
    return t, u, denominator, rx, ry
end

function Intersections.crossing(a, b, c, d)
    local t, u, denominator, rx, ry = positions(a, b, c, d)
    if not t or t <= 0 or t >= denominator or u <= 0 or u >= denominator then return nil end
    return {t = t, u = u, d = denominator, point = Rational.point(a.x * denominator + t * rx, a.y * denominator + t * ry, denominator)}
end

function Intersections.line_intersection(first, second)
    local t, _, denominator, rx, ry = positions(first.a, first.b, second.a, second.b)
    return Rational.point(first.a.x * denominator + t * rx, first.a.y * denominator + t * ry, denominator)
end

return Intersections
