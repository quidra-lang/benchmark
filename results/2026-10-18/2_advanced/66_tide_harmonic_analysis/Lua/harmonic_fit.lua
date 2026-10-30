local M = {PI = 3.141592653589793}
function M.angle(speed, time)
    local degrees = speed * time
    return (degrees - 360 * math.floor(degrees / 360)) * M.PI / 180
end
function M.fit(values, times, selected)
    local p = 2 * #selected + 1
    local a, y = {}, {}
    for i = 1, p do a[i] = {}; y[i] = 0.0; for j = 1, p do a[i][j] = 0.0 end end
    for _, t in ipairs(times) do
        local v = {1.0}
        for _, c in ipairs(selected) do
            local theta = M.angle(c.speed, t)
            v[#v + 1] = math.cos(theta); v[#v + 1] = math.sin(theta)
        end
        for i = 1, p do
            y[i] = y[i] + v[i] * values[t]
            for j = 1, p do a[i][j] = a[i][j] + v[i] * v[j] end
        end
    end
    for i = 1, p do
        a[i][p + 1] = y[i]
        for j = 1, p do a[i][p + 1 + j] = i == j and 1.0 or 0.0 end
    end
    for j = 1, p do
        local pivot = j
        for i = j + 1, p do if math.abs(a[i][j]) > math.abs(a[pivot][j]) then pivot = i end end
        a[j], a[pivot] = a[pivot], a[j]
        for i = j + 1, p do
            local factor = a[i][j] / a[j][j]
            for k = j, 2 * p + 1 do a[i][k] = a[i][k] - factor * a[j][k] end
        end
    end
    local solutions, inverse = {}, {}
    for col = p + 1, 2 * p + 1 do
        local x = {}
        for i = p, 1, -1 do
            local value = a[i][col]
            for j = i + 1, p do value = value - a[i][j] * x[j] end
            x[i] = value / a[i][i]
        end
        solutions[#solutions + 1] = x
    end
    for i = 1, p do inverse[i] = {}; for j = 1, p do inverse[i][j] = solutions[j + 1][i] end end
    local coeff, constants = solutions[1], {}
    for i, c in ipairs(selected) do
        local aa, bb = coeff[2 * i], coeff[2 * i + 1]
        local phase = math.atan(bb, aa) * 180 / M.PI
        if phase < 0 then phase = phase + 360 end
        constants[c.name] = {speed = c.speed, a = aa, b = bb, amplitude = math.sqrt(aa * aa + bb * bb),
            phase = phase, ia = 2 * i, ib = 2 * i + 1}
    end
    return {selected = selected, coefficients = coeff, inverse = inverse, mean_level = coeff[1], constants = constants, unknowns = p}
end
return M
