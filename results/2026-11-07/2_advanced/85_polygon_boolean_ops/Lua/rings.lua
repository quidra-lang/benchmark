local Rational = require("rational")
local Intersections = require("intersections")
local Rings = {}

function Rings.inside(ring, point)
    local parity = false
    for i, first in ipairs(ring) do
        local second = ring[i % #ring + 1]
        if Rational.y_less(point, first) ~= Rational.y_less(point, second) then
            local line = ring.lines[i]
            local cross = Rational.line_cross(line.a, line.b, point)
            if Rational.y_less(second, first) then cross = -cross end
            if cross > 0 then parity = not parity end
        end
    end
    return parity
end

function Rings.interior(sequence, point)
    local parity = false
    for _, ring in ipairs(sequence) do if Rings.inside(ring, point) then parity = not parity end end
    return parity
end

function Rings.boundary(ring, point)
    for i, first in ipairs(ring) do
        if Intersections.on_segment(point, first, ring[i % #ring + 1], ring.lines[i]) then return true end
    end
    return false
end

function Rings.rotate(ring)
    local first, result = 1, {lines = {}}
    for i = 2, #ring do if Rational.less(ring[i], ring[first]) then first = i end end
    for offset = 0, #ring - 1 do
        local index = (first + offset - 1) % #ring + 1
        result[#result + 1], result.lines[#result.lines + 1] = ring[index], ring.lines[index]
    end
    return result
end

function Rings.ccw(ring)
    return Rational.cross(ring[#ring], ring[1], ring[2]) > 0
end

function Rings.reverse(ring)
    local result = {lines = {}}
    for i = 1, #ring do
        local index = i == 1 and 1 or #ring - i + 2
        local line = ring.lines[(index - 2) % #ring + 1]
        result[i], result.lines[i] = ring[index], {a = line.b, b = line.a}
    end
    return result
end

function Rings.normalize(ring, outer)
    local result = Rings.rotate(ring)
    return Rings.ccw(result) == outer and result or Rings.reverse(result)
end

function Rings.assemble(result_rings)
    local rotated, depths, oriented, outer_indices = {}, {}, {}, {}
    for i, ring in ipairs(result_rings) do rotated[i] = Rings.rotate(ring) end
    for i, ring in ipairs(rotated) do
        local depth = 0
        for j, other in ipairs(rotated) do if i ~= j and Rings.inside(other, ring[1]) then depth = depth + 1 end end
        depths[i] = depth
        oriented[i] = Rings.ccw(ring) == (depth % 2 == 0) and ring or Rings.reverse(ring)
        if depth % 2 == 0 then outer_indices[#outer_indices + 1] = i end
    end
    table.sort(outer_indices, function(a, b) return Rational.less(oriented[a][1], oriented[b][1]) end)
    local result = {}
    for _, index in ipairs(outer_indices) do
        local outer, holes = oriented[index], {}
        for i, ring in ipairs(oriented) do
            if depths[i] == depths[index] + 1 and Rings.inside(outer, ring[1]) then holes[#holes + 1] = ring end
        end
        table.sort(holes, function(a, b) return Rational.less(a[1], b[1]) end)
        local polygon = {outer}
        for _, hole in ipairs(holes) do polygon[#polygon + 1] = hole end
        result[#result + 1] = polygon
    end
    return result
end

function Rings.area(ring)
    local total = 0.0
    for i, first in ipairs(ring) do
        local x1, y1 = Rational.real(first)
        local x2, y2 = Rational.real(ring[i % #ring + 1])
        total = total + (x1 * y2 - x2 * y1)
    end
    return total / 2.0
end

function Rings.perimeter(ring)
    local total = 0.0
    for i, first in ipairs(ring) do
        local x1, y1 = Rational.real(first)
        local x2, y2 = Rational.real(ring[i % #ring + 1])
        local dx, dy = x2 - x1, y2 - y1
        total = total + math.sqrt(dx * dx + dy * dy)
    end
    return total
end

return Rings
