local M = {}
function M.sum(values)
    local result = values[1] or 0.0
    for i = 2, #values do result = result + values[i] end
    return result
end
function M.flow(system, field, point, first, last)
    local terms = {}
    for direction = first, last do
        local face = system.faces[point][direction]
        if face.neighbor > 0 then terms[#terms + 1] = face.g * (field[face.neighbor] - field[point])
        elseif face.theta then terms[#terms + 1] = face.g * (face.theta - field[point]) end
    end
    return M.sum(terms)
end
function M.thomas(lower, diagonal, upper, rhs)
    local up, rp = {upper[1] / diagonal[1]}, {rhs[1] / diagonal[1]}
    for i = 2, #diagonal do
        local pivot = diagonal[i] - lower[i] * up[i - 1]
        up[i], rp[i] = upper[i] / pivot, (rhs[i] - lower[i] * rp[i - 1]) / pivot
    end
    local result = {}
    result[#diagonal] = rp[#diagonal]
    for i = #diagonal - 1, 1, -1 do result[i] = rp[i] - up[i] * result[i + 1] end
    return result
end
function M.sweep(system, tau, rhs, horizontal)
    local plate = system.mesh
    local line_count = horizontal and plate.height or plate.width
    local length = horizontal and plate.width or plate.height
    local first, second = horizontal and 1 or 3, horizontal and 2 or 4
    local field = {}
    for line = 0, line_count - 1 do
        local cells, lower, diagonal, upper, values = {}, {}, {}, {}, {}
        for i = 0, length - 1 do
            local point = horizontal and line * plate.width + i + 1 or i * plate.width + line + 1
            cells[i + 1] = point
            local a, b = system.faces[point][first], system.faces[point][second]
            lower[i + 1] = a.neighbor > 0 and -a.g or 0.0
            diagonal[i + 1] = system.capacity[point] / tau + a.g + b.g
            upper[i + 1] = b.neighbor > 0 and -b.g or 0.0
            local value = rhs[point]
            if a.theta then value = value + a.g * a.theta end
            if b.theta then value = value + b.g * b.theta end
            values[i + 1] = value
        end
        local solved = M.thomas(lower, diagonal, upper, values)
        for i, point in ipairs(cells) do field[point] = solved[i] end
    end
    return field
end
function M.advance(method, system, field, source, dt)
    local rhs = {}
    if method == 'ftcs' then
        for p = 1, system.mesh.count do rhs[p] = field[p] + dt * (M.flow(system, field, p, 1, 4) + source[p]) / system.capacity[p] end
        return rhs, nil
    end
    local tau = method == 'crank_nicolson' and dt / 2 or dt
    local vertical = {}
    for p = 1, system.mesh.count do
        vertical[p] = M.flow(system, field, p, 3, 4)
        rhs[p] = system.capacity[p] / tau * field[p] + vertical[p] + source[p]
    end
    local intermediate = M.sweep(system, tau, rhs, true)
    for p = 1, system.mesh.count do
        if method == 'backward_euler' then rhs[p] = system.capacity[p] / dt * intermediate[p] - vertical[p]
        else rhs[p] = system.capacity[p] / tau * intermediate[p] + M.flow(system, intermediate, p, 1, 2) + source[p] end
    end
    return M.sweep(system, tau, rhs, false), intermediate
end
return M
