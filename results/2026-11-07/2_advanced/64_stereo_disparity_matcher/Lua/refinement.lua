local R = {}
function R.hundredths(value) return string.format("%d.%02d", value // 100, value % 100) end
function R.two(numerator, denominator)
    denominator = denominator or 1
    return R.hundredths((200 * numerator + denominator) // (2 * denominator))
end
function R.depth_hundredths(disparity, focal, baseline) return (200 * focal * baseline + disparity) // (2 * disparity) end
function R.subpixel(disparity, costs, minimum, maximum, focal, baseline)
    local index, a, b = disparity - minimum + 1, 0, 1
    if disparity > minimum and disparity < maximum and costs[index - 1] > costs[index] and costs[index + 1] >= costs[index] then
        a, b = costs[index - 1] - costs[index + 1], 2 * (costs[index - 1] - 2 * costs[index] + costs[index + 1])
    end
    local rounded = (200 * (disparity * b + a) + b) // (2 * b)
    return R.hundredths(rounded), R.two(100 * focal * baseline, rounded)
end
return R
