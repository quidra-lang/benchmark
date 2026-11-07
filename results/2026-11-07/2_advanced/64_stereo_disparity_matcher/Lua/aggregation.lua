local A = { directions = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 }, { 1, 1 }, { -1, -1 }, { -1, 1 }, { 1, -1 } } }
function A.path_costs(base, left, width, height, direction, p1, p2, gamma)
    local rx, ry, result, disparities = direction[1], direction[2], {}, #base[1]
    local yfirst, ylast, ystep = 0, height - 1, 1
    local xfirst, xlast, xstep = 0, width - 1, 1
    if ry < 0 then yfirst, ylast, ystep = height - 1, 0, -1 end
    if rx < 0 then xfirst, xlast, xstep = width - 1, 0, -1 end
    for y = yfirst, ylast, ystep do
        for x = xfirst, xlast, xstep do
            local p, qx, qy = y * width + x + 1, x - rx, y - ry
            local values = {}
            if qx < 0 or qx >= width or qy < 0 or qy >= height then for d, value in ipairs(base[p]) do values[d] = value end
            else
                local q = qy * width + qx + 1
                local previous = result[q]
                local minimum = math.min(table.unpack(previous))
                local penalty = math.max(p1, p2 * gamma // (gamma + math.abs(left[p] - left[q])))
                for d = 1, disparities do
                    local best = math.min(previous[d], minimum + penalty)
                    if d > 1 then best = math.min(best, previous[d - 1] + p1) end
                    if d < disparities then best = math.min(best, previous[d + 1] + p1) end
                    values[d] = base[p][d] + best - minimum
                end
            end
            result[p] = values
        end
    end
    return result
end
function A.cumulative(base, left, width, height, paths, p1, p2, gamma, visit)
    local total = {}
    for p = 1, #base do total[p] = {}; for d = 1, #base[1] do total[p][d] = 0 end end
    for i = 1, paths do
        local costs = A.path_costs(base, left, width, height, A.directions[i], p1, p2, gamma)
        for p, row in ipairs(costs) do for d, value in ipairs(row) do total[p][d] = total[p][d] + value end end
        visit(i, total)
    end
    return total
end
return A
