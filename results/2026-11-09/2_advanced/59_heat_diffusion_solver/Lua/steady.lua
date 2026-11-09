local transient = require('transient')
local M = {}
function M.g_value(system, field, point)
    local terms = {}
    for _, face in ipairs(system.faces[point]) do
        if face.neighbor > 0 then terms[#terms + 1] = face.g * field[face.neighbor]
        elseif face.theta then terms[#terms + 1] = face.g * face.theta end
    end
    return transient.sum(terms) + system.source_all[point]
end
function M.iterate(system, initial, tolerance, maximum, method, omega)
    local field, changes = {}, {}
    for p = 1, system.mesh.count do field[p] = initial end
    for _ = 1, maximum do
        local previous, updated = {}, {}
        for p, value in ipairs(field) do previous[p] = value end
        for p = 1, system.mesh.count do
            local target = M.g_value(system, method == 'jacobi' and previous or field, p) / system.diagonal[p]
            if method == 'jacobi' then updated[p] = target
            elseif method == 'gauss_seidel' then field[p] = target
            else field[p] = field[p] + omega * (target - field[p]) end
        end
        if method == 'jacobi' then field = updated end
        local change = 0.0
        for p, value in ipairs(field) do change = math.max(change, math.abs(value - previous[p])) end
        changes[#changes + 1] = change
        if change < tolerance then break end
    end
    return {method = method, field = field, changes = changes, iterations = #changes, converged = changes[#changes] < tolerance, omega = omega}
end
function M.band_solve(system, right_hand_sides)
    local count, width = system.mesh.count, system.mesh.width
    local matrix, vectors = {}, {}
    for p = 1, count do
        matrix[p] = {}
        for offset = -width, width do matrix[p][offset] = 0.0 end
        matrix[p][0] = system.diagonal[p]
        for _, face in ipairs(system.faces[p]) do if face.neighbor > 0 then matrix[p][face.neighbor - p] = -face.g end end
    end
    for i, rhs in ipairs(right_hand_sides) do vectors[i] = {}; for p, value in ipairs(rhs) do vectors[i][p] = value end end
    for column = 1, count do
        local stop = math.min(count, column + width)
        for row = column + 1, stop do
            local factor = matrix[row][column - row] / matrix[column][0]
            matrix[row][column - row] = 0.0
            for following = column + 1, stop do matrix[row][following - row] = matrix[row][following - row] - factor * matrix[column][following - column] end
            for _, values in ipairs(vectors) do values[row] = values[row] - factor * values[column] end
        end
    end
    local solutions = {}
    for _, values in ipairs(vectors) do
        local field = {}
        for row = count, 1, -1 do
            local value = values[row]
            for column = row + 1, math.min(count, row + width) do value = value - matrix[row][column - row] * field[column] end
            field[row] = value / matrix[row][0]
        end
        solutions[#solutions + 1] = field
    end
    return solutions
end
function M.residual(system, field, rhs)
    local maximum = 0.0
    for p, faces in ipairs(system.faces) do
        local value = rhs[p]
        for _, face in ipairs(faces) do if face.neighbor > 0 then value = value + face.g * field[face.neighbor] end end
        value = value - system.diagonal[p] * field[p]
        maximum = math.max(maximum, math.abs(value))
    end
    return maximum
end
return M
