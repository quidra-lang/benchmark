local C = {}
function C.clamped(image, width, height, x, y)
    x, y = math.min(math.max(x, 0), width - 1), math.min(math.max(y, 0), height - 1)
    return image[y * width + x + 1]
end
function C.box_sum(image, width, height, window)
    local radius = window // 2
    local pw, ph = width + 2 * radius, height + 2 * radius
    local integral = {}
    for y = 0, ph do integral[y] = {}; for x = 0, pw do integral[y][x] = 0 end end
    for y = 0, ph - 1 do
        local row_sum = 0
        for x = 0, pw - 1 do
            row_sum = row_sum + C.clamped(image, width, height, x - radius, y - radius)
            integral[y + 1][x + 1] = integral[y][x + 1] + row_sum
        end
    end
    local result = {}
    for y = 0, height - 1 do
        for x = 0, width - 1 do result[#result + 1] = integral[y + window][x + window] - integral[y][x + window] - integral[y + window][x] + integral[y][x] end
    end
    return result
end
function C.census(image, width, height)
    local result = {}
    for y = 0, height - 1 do
        for x = 0, width - 1 do
            local code, center = 0, image[y * width + x + 1]
            for dy = -2, 2 do
                for dx = -2, 2 do
                    if dx ~= 0 or dy ~= 0 then code = (code << 1) | (C.clamped(image, width, height, x + dx, y + dy) < center and 1 or 0) end
                end
            end
            result[#result + 1] = code
        end
    end
    return result
end
function C.texture(image, width, height, window)
    local gradient = {}
    for y = 0, height - 1 do
        for x = 0, width - 1 do gradient[#gradient + 1] = math.abs(C.clamped(image, width, height, x + 1, y) - C.clamped(image, width, height, x - 1, y)) end
    end
    return C.box_sum(gradient, width, height, window)
end
local function popcount(value)
    local count = 0
    while value > 0 do value, count = value & (value - 1), count + 1 end
    return count
end
function C.volume(left, right, cl, cr, width, height, kind, window, minimum, maximum)
    local result = {}
    for i = 1, #left do result[i] = {} end
    for disparity = minimum, maximum do
        local pixels = {}
        for y = 0, height - 1 do
            for x = 0, width - 1 do
                local p, q = y * width + x + 1, y * width + math.max(x - disparity, 0) + 1
                local value
                if kind == "census" then value = popcount(cl[p] ~ cr[q])
                else local difference = left[p] - right[q]; value = kind == "sad" and math.abs(difference) or difference * difference end
                pixels[#pixels + 1] = value
            end
        end
        for p, value in ipairs(C.box_sum(pixels, width, height, window)) do result[p][disparity - minimum + 1] = value end
    end
    return result
end
return C
