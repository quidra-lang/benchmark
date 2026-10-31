local M = {}
function M.neighbors(width, height, x, y)
    local result = {}
    for dy = -1, 1 do
        for dx = -1, 1 do
            local nx, ny = x + dx, y + dy
            if (dx ~= 0 or dy ~= 0) and nx >= 0 and nx < width and ny >= 0 and ny < height then
                result[#result + 1] = {nx, ny}
            end
        end
    end
    return result
end
function M.directions(gx, gy)
    local result = {}
    for y, row in ipairs(gx) do
        result[y] = {}
        for x, horizontal in ipairs(row) do
            local vertical = gy[y][x]
            local ax, ay = math.abs(horizontal), math.abs(vertical)
            result[y][x] = 29 * ay <= 12 * ax and 0 or 29 * ay >= 70 * ax and 90 or horizontal * vertical < 0 and 45 or 135
        end
    end
    return result
end
function M.suppress(magnitude, directions)
    local offsets = {[0] = {-1, 0}, [45] = {1, -1}, [90] = {0, -1}, [135] = {-1, -1}}
    local result, height, width = {}, #magnitude, #magnitude[1]
    for y = 0, height - 1 do
        result[y + 1] = {}
        for x = 0, width - 1 do
            local value = 0
            if x > 0 and x < width - 1 and y > 0 and y < height - 1 then
                local offset = offsets[directions[y + 1][x + 1]]
                local dx, dy = offset[1], offset[2]
                local current = magnitude[y + 1][x + 1]
                if current > magnitude[y + dy + 1][x + dx + 1] and current >= magnitude[y - dy + 1][x - dx + 1] then
                    value = current
                end
            end
            result[y + 1][x + 1] = value
        end
    end
    return result
end
function M.hysteresis(nonmax, low, high)
    local height, width = #nonmax, #nonmax[1]
    local edges, strong, weak, queue = {}, {}, {}, {}
    for y = 0, height - 1 do
        for x = 0, width - 1 do
            local key, value = y * width + x + 1, nonmax[y + 1][x + 1]
            if value >= high then
                strong[key], edges[key], queue[#queue + 1] = true, true, {x, y}
            elseif value >= low then
                weak[key] = true
            end
        end
    end
    local cursor = 1
    while cursor <= #queue do
        local point = queue[cursor]
        cursor = cursor + 1
        for _, next_point in ipairs(M.neighbors(width, height, point[1], point[2])) do
            local key = next_point[2] * width + next_point[1] + 1
            if not edges[key] and (strong[key] or weak[key]) then
                edges[key], queue[#queue + 1] = true, next_point
            end
        end
    end
    return edges, strong, weak
end
function M.components(edges, width, height)
    local visited, result = {}, {}
    for y = 0, height - 1 do
        for x = 0, width - 1 do
            local key = y * width + x + 1
            if edges[key] and not visited[key] then
                local queue, cursor = {{x, y}}, 1
                visited[key] = true
                while cursor <= #queue do
                    local point = queue[cursor]
                    cursor = cursor + 1
                    for _, next_point in ipairs(M.neighbors(width, height, point[1], point[2])) do
                        local next_key = next_point[2] * width + next_point[1] + 1
                        if edges[next_key] and not visited[next_key] then
                            visited[next_key], queue[#queue + 1] = true, next_point
                        end
                    end
                end
                result[#result + 1] = {number = #result + 1, pixels = queue}
            end
        end
    end
    return result
end
return M
