local M = {}
function M.hex(value, width)
    return string.format("%0" .. (width or 2) .. "X", value)
end
function M.hex_lines(samples)
    local lines = {}
    for start = 1, #samples, 32 do
        local fields = {}
        for i = start, math.min(start + 31, #samples) do
            fields[#fields + 1] = M.hex(samples[i])
        end
        lines[#lines + 1] = table.concat(fields)
    end
    return lines
end
function M.adler(values)
    local a, b = 1, 0
    for _, value in ipairs(values) do
        a = (a + value) % 65521
        b = (b + a) % 65521
    end
    return M.hex(b * 65536 + a, 8)
end
function M.isqrt(value)
    local low, high = 0, 1
    while high * high <= value do
        high = high * 2
    end
    while low + 1 < high do
        local middle = (low + high) // 2
        if middle * middle <= value then
            low = middle
        else
            high = middle
        end
    end
    return low
end
function M.peak(values, center)
    local peak = 0
    for _, value in ipairs(values) do
        peak = math.max(peak, math.abs(value - center))
    end
    return peak
end
function M.rms(values, center)
    local sum = 0
    for _, value in ipairs(values) do
        sum = sum + (value - center) * (value - center)
    end
    return M.isqrt(sum // #values)
end
function M.crossings(values)
    local count = 0
    for i = 2, #values do
        if (values[i - 1] < 128) ~= (values[i] < 128) then
            count = count + 1
        end
    end
    return count
end
return M
