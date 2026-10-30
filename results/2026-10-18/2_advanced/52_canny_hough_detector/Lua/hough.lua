local M = {}
function M.rho(point, angle, trig, step)
    local row = trig[angle]
    return (point[1] * row[1] + point[2] * row[2]) // (16384 * step)
end
function M.circle_points(radius)
    local result, seen = {}, {}
    local a, b, error = radius, 0, 1 - radius
    while a >= b do
        local points = {{a, b}, {b, a}, {-b, a}, {-a, b}, {-a, -b}, {-b, -a}, {b, -a}, {a, -b}}
        for _, point in ipairs(points) do
            local key = (point[2] + radius) * (2 * radius + 1) + point[1] + radius + 1
            if not seen[key] then
                seen[key], result[#result + 1] = true, point
            end
        end
        b = b + 1
        if error < 0 then
            error = error + 2 * b + 1
        else
            a = a - 1
            error = error + 2 * (b - a) + 1
        end
    end
    return result
end
function M.circle_votes(edges, width, height, low, high)
    local cells, outlines = {}, {}
    for radius = low, high do
        local votes, offsets = {}, M.circle_points(radius)
        outlines[radius] = offsets
        for _, point in ipairs(edges) do
            for _, offset in ipairs(offsets) do
                local x, y = point[1] + offset[1], point[2] + offset[2]
                if x >= 0 and x < width and y >= 0 and y < height then
                    local key = y * width + x + 1
                    votes[key] = (votes[key] or 0) + 1
                end
            end
        end
        cells[radius] = votes
    end
    return cells, outlines
end
function M.circle_peaks(cells, outlines, width, height, low, high, minimum)
    local candidates, peaks = 0, {}
    for radius = low, high do
        local denominator = #outlines[radius]
        for y = 0, height - 1 do
            for x = 0, width - 1 do
                local votes = cells[radius][y * width + x + 1] or 0
                if 100 * votes >= minimum * denominator then
                    candidates = candidates + 1
                    local peak = true
                    for other_radius = math.max(low, radius - 2), math.min(high, radius + 2) do
                        for yy = math.max(0, y - 2), math.min(height - 1, y + 2) do
                            for xx = math.max(0, x - 2), math.min(width - 1, x + 2) do
                                if other_radius ~= radius or yy ~= y or xx ~= x then
                                    local other = cells[other_radius][yy * width + xx + 1] or 0
                                    local left, right = votes * #outlines[other_radius], other * denominator
                                    local earlier = other_radius < radius or other_radius == radius and (yy < y or yy == y and xx < x)
                                    if left < right or left == right and earlier then
                                        peak = false
                                    end
                                end
                            end
                        end
                    end
                    if peak then
                        peaks[#peaks + 1] = {radius = radius, x = x, y = y, votes = votes, points = denominator}
                    end
                end
            end
        end
    end
    return candidates, peaks
end
function M.line_votes(edges, trig, step)
    local votes = {}
    for angle = 0, 179 do
        votes[angle] = {}
    end
    for _, point in ipairs(edges) do
        for angle = 0, 179 do
            local radial = M.rho(point, angle, trig, step)
            votes[angle][radial] = (votes[angle][radial] or 0) + 1
        end
    end
    return votes
end
function M.line_peaks(votes, threshold)
    local peaks = {}
    for angle = 0, 179 do
        for radial, count in pairs(votes[angle]) do
            if count >= threshold then
                local peak = true
                for other_angle = math.max(0, angle - 2), math.min(179, angle + 2) do
                    for other_radial = radial - 2, radial + 2 do
                        if other_angle ~= angle or other_radial ~= radial then
                            local other = votes[other_angle][other_radial] or 0
                            local earlier = other_angle < angle or other_angle == angle and other_radial < radial
                            if other > count or other == count and earlier then
                                peak = false
                            end
                        end
                    end
                end
                if peak then
                    peaks[#peaks + 1] = {theta = angle, rho = radial, votes = count}
                end
            end
        end
    end
    return peaks
end
return M
