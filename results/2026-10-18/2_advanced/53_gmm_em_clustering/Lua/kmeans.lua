local M = {}
function M.distance2(a, b)
    local dx, dy = a[1] - b[1], a[2] - b[2]
    return dx * dx + dy * dy
end
function M.distance(a, b)
    return math.sqrt(M.distance2(a, b))
end
local function assign(points, centers)
    local result = {}
    for i, point in ipairs(points) do
        local best, distance = 1, math.huge
        for k, center in ipairs(centers) do
            local candidate = M.distance2({point.x, point.y}, center)
            if candidate < distance then best, distance = k, candidate end
        end
        result[i] = best
    end
    return result
end
function M.run(points, initial, maximum)
    local centers = {}
    for k, center in ipairs(initial) do centers[k] = {table.unpack(center)} end
    local assigned = assign(points, centers)
    local iterations = 0
    for t = 1, maximum do
        local updated = {}
        for k, center in ipairs(centers) do
            local sx, sy, count = 0.0, 0.0, 0
            for i, point in ipairs(points) do
                if assigned[i] == k then sx, sy, count = sx + point.x, sy + point.y, count + 1 end
            end
            updated[k] = center
            if count > 0 then updated[k] = {sx / count, sy / count} end
        end
        centers = updated
        local next_assignment = assign(points, centers)
        local same = true
        for i, value in ipairs(assigned) do if value ~= next_assignment[i] then same = false end end
        assigned, iterations = next_assignment, t
        if same then break end
    end
    local inertia, sizes = 0.0, {}
    for k = 1, #centers do sizes[k] = 0 end
    for i, point in ipairs(points) do
        sizes[assigned[i]] = sizes[assigned[i]] + 1
        inertia = inertia + M.distance2({point.x, point.y}, centers[assigned[i]])
    end
    return {centers = centers, assignment = assigned, iterations = iterations, inertia = inertia, sizes = sizes}
end
return M
