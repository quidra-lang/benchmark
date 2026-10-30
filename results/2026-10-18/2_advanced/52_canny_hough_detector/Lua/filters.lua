local M = {}
function M.clamped(image, x, y)
    x, y = math.min(math.max(x, 0), #image[1] - 1), math.min(math.max(y, 0), #image - 1)
    return image[y + 1][x + 1]
end
function M.smoothing(image, size, kernel, divisor)
    local result, half = {}, size // 2
    for y = 0, #image - 1 do
        local row = {}
        for x = 0, #image[1] - 1 do
            local total = 0
            for j = 0, size - 1 do
                for i = 0, size - 1 do
                    total = total + kernel[j * size + i + 1] * M.clamped(image, x + i - half, y + j - half)
                end
            end
            row[#row + 1] = total // divisor
        end
        result[#result + 1] = row
    end
    return result
end
function M.gradient(image)
    local gx, gy, magnitude = {}, {}, {}
    for y = 0, #image - 1 do
        gx[y + 1], gy[y + 1], magnitude[y + 1] = {}, {}, {}
        for x = 0, #image[1] - 1 do
            local q = {}
            for dy = -1, 1 do
                for dx = -1, 1 do
                    q[#q + 1] = M.clamped(image, x + dx, y + dy)
                end
            end
            local horizontal = (q[3] + 2 * q[6] + q[9]) - (q[1] + 2 * q[4] + q[7])
            local vertical = (q[7] + 2 * q[8] + q[9]) - (q[1] + 2 * q[2] + q[3])
            gx[y + 1][x + 1], gy[y + 1][x + 1] = horizontal, vertical
            magnitude[y + 1][x + 1] = math.abs(horizontal) + math.abs(vertical)
        end
    end
    return gx, gy, magnitude
end
return M
