local filters = require("filters")
local M = {}
function M.detect(gx, gy, window, threshold)
    local height, width, half = #gx, #gx[1], window // 2
    local response = {}
    for y = 0, height - 1 do
        response[y + 1] = {}
        for x = 0, width - 1 do
            local xx, yy, xy = 0, 0, 0
            for dy = -half, half do
                for dx = -half, half do
                    local horizontal, vertical = filters.clamped(gx, x + dx, y + dy), filters.clamped(gy, x + dx, y + dy)
                    xx, yy, xy = xx + horizontal * horizontal, yy + vertical * vertical, xy + horizontal * vertical
                end
            end
            response[y + 1][x + 1] = xx * yy - xy * xy - (xx + yy) * (xx + yy) // 25
        end
    end
    local candidates = {}
    for y = 0, height - 1 do
        for x = 0, width - 1 do
            local value, peak = response[y + 1][x + 1], true
            if value >= threshold then
                for dy = -1, 1 do
                    for dx = -1, 1 do
                        local nx, ny = x + dx, y + dy
                        if (dx ~= 0 or dy ~= 0) and nx >= 0 and nx < width and ny >= 0 and ny < height then
                            local other = response[ny + 1][nx + 1]
                            if other > value or other == value and (ny < y or ny == y and nx < x) then
                                peak = false
                            end
                        end
                    end
                end
                if peak then
                    candidates[#candidates + 1] = {x = x, y = y, response = value}
                end
            end
        end
    end
    table.sort(candidates, function(a, b)
        return a.response > b.response or a.response == b.response and (a.y < b.y or a.y == b.y and a.x < b.x)
    end)
    return candidates
end
return M
