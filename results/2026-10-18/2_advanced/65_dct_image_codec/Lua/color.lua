local C = {}
function C.clamp(value) return math.min(math.max(value, 0), 255) end
function C.to_ycbcr(pixel)
    local r, g, b = pixel[1], pixel[2], pixel[3]
    return { (19595 * r + 38470 * g + 7471 * b + 32768) // 65536,
        (-11059 * r - 21709 * g + 32768 * b + 8421375) // 65536, (32768 * r - 27439 * g - 5329 * b + 8421375) // 65536 }
end
function C.to_rgb(y, cb, cr)
    return { C.clamp(y + (91881 * (cr - 128) + 32768) // 65536), C.clamp(y + (-22554 * (cb - 128) - 46802 * (cr - 128) + 32768) // 65536),
        C.clamp(y + (116130 * (cb - 128) + 32768) // 65536) }
end
function C.split_planes(image)
    local planes = { {}, {}, {} }
    for y, row in ipairs(image) do
        for k = 1, 3 do planes[k][y] = {} end
        for x, pixel in ipairs(row) do for k, value in ipairs(C.to_ycbcr(pixel)) do planes[k][y][x] = value end end
    end
    return planes
end
function C.component_planes(planes, factors, mx, my)
    local width, height, hmax, vmax = #planes[1][1], #planes[1], 1, 1
    for _, factor in ipairs(factors) do hmax, vmax = math.max(hmax, factor[1]), math.max(vmax, factor[2]) end
    local pw, ph, result = 8 * hmax * mx, 8 * vmax * my, {}
    for k, plane in ipairs(planes) do
        local extended = {}
        for y = 0, ph - 1 do
            extended[y + 1] = {}
            for x = 0, pw - 1 do extended[y + 1][x + 1] = plane[math.min(y, height - 1) + 1][math.min(x, width - 1) + 1] end
        end
        local horizontal, vertical = factors[k][1], factors[k][2]
        local fx, fy, component = hmax // horizontal, vmax // vertical, {}
        for y = 0, 8 * vertical * my - 1 do
            component[y + 1] = {}
            for x = 0, 8 * horizontal * mx - 1 do
                local total = 0
                for j = 0, fy - 1 do for i = 0, fx - 1 do total = total + extended[fy * y + j + 1][fx * x + i + 1] end end
                component[y + 1][x + 1] = total // (fx * fy)
            end
        end
        result[k] = component
    end
    return result
end
function C.upsample(planes, factors, width, height)
    local hmax, vmax, result = 1, 1, {}
    for _, factor in ipairs(factors) do hmax, vmax = math.max(hmax, factor[1]), math.max(vmax, factor[2]) end
    for k, plane in ipairs(planes) do
        result[k] = {}
        for y = 0, height - 1 do
            result[k][y + 1] = {}
            for x = 0, width - 1 do result[k][y + 1][x + 1] = plane[y * factors[k][2] // vmax + 1][x * factors[k][1] // hmax + 1] end
        end
    end
    return result
end
function C.combine(planes)
    local image = {}
    for y, row in ipairs(planes[1]) do
        image[y] = {}
        for x, value in ipairs(row) do image[y][x] = C.to_rgb(value, planes[2][y][x], planes[3][y][x]) end
    end
    return image
end
return C
