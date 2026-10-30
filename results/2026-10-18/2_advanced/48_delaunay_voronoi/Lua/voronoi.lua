local predicates = require("predicates")
local M = {}
function M.radius2(a, b, c)
    local first, second, third = predicates.d2(a, b) + 0.0, predicates.d2(b, c) + 0.0, predicates.d2(c, a) + 0.0
    local area = predicates.orient(a, b, c) + 0.0
    return ((first * second) * third) / ((4.0 * area) * area)
end
function M.position(center, points, hull)
    local x, y, d = table.unpack(center)
    local on = false
    for i, u in ipairs(hull) do
        local v = hull[i % #hull + 1]
        local p, q = points[u], points[v]
        local sigma = (q[1] - p[1]) * (y - p[2] * d) - (q[2] - p[2]) * (x - p[1] * d)
        if sigma < 0 then
            return "outside"
        elseif sigma == 0 then
            on = true
        end
    end
    return on and "on" or "inside"
end
function M.neighbors(site, adjacent, directed, following)
    local first = following[site] or math.min(table.unpack(adjacent))
    local result = {first}
    while #result < #adjacent do
        result[#result + 1] = directed[site][result[#result]]
    end
    return result
end
function M.outward(points, u, v)
    return predicates.direction(points[v][2] - points[u][2], points[u][1] - points[v][1])
end
function M.bounded_area(site, centers)
    local relative = {}
    for i, center in ipairs(centers) do
        relative[i] = {center[1] / center[3] - site[1], center[2] / center[3] - site[2]}
    end
    local total = 0.0
    for i, p in ipairs(relative) do
        local q = relative[i % #relative + 1]
        total = total + (p[1] * q[2] - q[1] * p[2])
    end
    return total / 2.0
end
function M.clipped_area(points, site, neighbors)
    local polygon = {{0.0, 0.0}, {1000.0, 0.0}, {1000.0, 1000.0}, {0.0, 1000.0}}
    local xs, ys = table.unpack(points[site])
    for _, neighbor in ipairs(neighbors) do
        local xt, yt = table.unpack(points[neighbor])
        local c1, c2, c3 = 2 * (xt - xs), 2 * (yt - ys), xt * xt + yt * yt - xs * xs - ys * ys
        local clipped = {}
        for i, p in ipairs(polygon) do
            local q = polygon[i % #polygon + 1]
            local fp, fq = c1 * p[1] + c2 * p[2] - c3, c1 * q[1] + c2 * q[2] - c3
            if fp <= 0.0 then
                clipped[#clipped + 1] = p
            end
            if fp < 0.0 and fq > 0.0 or fq < 0.0 and fp > 0.0 then
                local fraction = fp / (fp - fq)
                clipped[#clipped + 1] = {p[1] + (q[1] - p[1]) * fraction, p[2] + (q[2] - p[2]) * fraction}
            end
        end
        polygon = clipped
    end
    local total = 0.0
    for i, p in ipairs(polygon) do
        local q = polygon[i % #polygon + 1]
        total = total + (p[1] * q[2] - q[1] * p[2])
    end
    return total / 2.0
end
return M
