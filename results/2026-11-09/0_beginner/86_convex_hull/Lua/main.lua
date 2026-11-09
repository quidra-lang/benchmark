local function cross(o, a, b)
    return (a[1] - o[1]) * (b[2] - o[2]) - (a[2] - o[2]) * (b[1] - o[1])
end

local function chain(points)
    local result = {}
    for _, point in ipairs(points) do
        while #result >= 2 and cross(result[#result - 1], result[#result], point) <= 0 do
            table.remove(result)
        end
        result[#result + 1] = point
    end
    return result
end

local points = {
    {3, 2}, {-6, 1}, {8, 4}, {0, 0}, {-3, 7}, {4, -3}, {1, -5}, {-2, 1}, {5, 6}, {-6, -2}, {2, -2},
    {7, -1}, {-3, 4}, {2, 8}, {-6, 3},
}
table.sort(points, function(a, b) return a[1] < b[1] or (a[1] == b[1] and a[2] < b[2]) end)
local reversed = {}
for i = #points, 1, -1 do reversed[#reversed + 1] = points[i] end
local lower, upper = chain(points), chain(reversed)
table.remove(lower)
table.remove(upper)
local hull = lower
table.move(upper, 1, #upper, #hull + 1, hull)
io.write(string.format("hull: %d points\n", #hull))
local twice_area = 0
for i, point in ipairs(hull) do
    local following = hull[i % #hull + 1]
    io.write(string.format("(%d, %d)\n", point[1], point[2]))
    twice_area = twice_area + point[1] * following[2] - following[1] * point[2]
end
io.write(string.format("area: %.1f\n", twice_area / 2))
