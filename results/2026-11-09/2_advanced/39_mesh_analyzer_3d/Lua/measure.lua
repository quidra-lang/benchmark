local M = {}
function M.subtract(a, b)
    return {a[1] - b[1], a[2] - b[2], a[3] - b[3]}
end
function M.dot(a, b)
    return a[1] * b[1] + a[2] * b[2] + a[3] * b[3]
end
function M.cross(a, b)
    return {a[2] * b[3] - a[3] * b[2], a[3] * b[1] - a[1] * b[3], a[1] * b[2] - a[2] * b[1]}
end
function M.normal(face, points)
    local v = face.vertices
    return M.cross(M.subtract(points[v[2]], points[v[1]]), M.subtract(points[v[3]], points[v[1]]))
end
function M.determinant(face, points)
    local v = face.vertices
    return M.dot(points[v[1]], M.cross(points[v[2]], points[v[3]]))
end
function M.area(ids, faces, points)
    local total = 0.0
    for _, id in ipairs(ids) do
        local normal = M.normal(faces[id], points)
        total = total + math.sqrt(M.dot(normal, normal))
    end
    return total / 2
end
function M.length2(edge, points)
    local delta = M.subtract(points[edge.a], points[edge.b])
    return M.dot(delta, delta)
end
function M.angle(face, points)
    local v = face.vertices
    local a, b, c = points[v[1]], points[v[2]], points[v[3]]
    local smallest = math.min(M.dot(M.subtract(b, a), M.subtract(c, a)),
        M.dot(M.subtract(c, b), M.subtract(a, b)), M.dot(M.subtract(a, c), M.subtract(b, c)))
    return smallest < 0 and "obtuse" or smallest == 0 and "right" or "acute"
end
function M.volume6(ids, faces, points)
    local total = 0
    for _, id in ipairs(ids) do
        total = total + M.determinant(faces[id], points)
    end
    return total
end
function M.fraction(numerator, denominator)
    if denominator < 0 then
        numerator, denominator = -numerator, -denominator
    end
    local a, b = math.abs(numerator), denominator
    while b ~= 0 do
        a, b = b, a % b
    end
    numerator, denominator = numerator // a, denominator // a
    return denominator == 1 and tostring(numerator) or numerator .. "/" .. denominator
end
function M.real(value)
    local result = string.format("%.3f", value)
    return result == "-0.000" and "0.000" or result
end
function M.centroid(ids, faces, points, volume)
    local result = {}
    for axis = 1, 3 do
        local total = 0
        for _, id in ipairs(ids) do
            local face = faces[id]
            local v = face.vertices
            total = total + M.determinant(face, points) * (points[v[1]][axis] + points[v[2]][axis] + points[v[3]][axis])
        end
        result[axis] = M.fraction(total, 4 * volume)
    end
    return result
end
function M.bbox(vertices, points)
    local low, high = {}, {}
    for axis = 1, 3 do
        low[axis], high[axis] = points[vertices[1]][axis], points[vertices[1]][axis]
        for _, v in ipairs(vertices) do
            low[axis], high[axis] = math.min(low[axis], points[v][axis]), math.max(high[axis], points[v][axis])
        end
    end
    return {low[1], low[2], low[3], high[1], high[2], high[3]}
end
function M.winding(ids, faces, points, sample)
    local total = 0.0
    for _, id in ipairs(ids) do
        local v = faces[id].vertices
        local a, b, c = M.subtract(points[v[1]], sample), M.subtract(points[v[2]], sample), M.subtract(points[v[3]], sample)
        local la, lb, lc = math.sqrt(M.dot(a, a)), math.sqrt(M.dot(b, b)), math.sqrt(M.dot(c, c))
        local numerator = M.dot(a, M.cross(b, c))
        local denominator = la * lb * lc + M.dot(a, b) * lc + M.dot(b, c) * la + M.dot(c, a) * lb
        total = total + 2 * math.atan(numerator, denominator)
    end
    return math.floor(total / (4 * 3.141592653589793) + 0.5)
end
return M
