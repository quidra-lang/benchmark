local zeros = require('assembly').zeros
local M = {}
function M.axial_forces(geometry, properties, displacement, temperature, removed)
    local result = zeros(#geometry)
    for number, shape in ipairs(geometry) do
        if number ~= removed then
            local ix, iy, jx, jy = table.unpack(shape.dofs)
            local extension = (displacement[jx] - displacement[ix]) * shape.cosine + (displacement[jy] - displacement[iy]) * shape.sine
            result[number] = properties[number].stiffness * extension - temperature[number]
        end
    end
    return result
end
function M.reactions(matrix, displacement, force, restrained)
    local result = zeros(#force)
    for _, row in ipairs(restrained) do
        local value = 0.0
        for column = 1, #force do value = value + matrix[row][column] * displacement[column] end
        result[row] = value - force[row]
    end
    return result
end
function M.superpose(combination, results)
    local result = {name = combination.name}
    for _, key in ipairs({'displacement', 'forces', 'reactions', 'external'}) do
        local vector, first = {}, combination.terms[1]
        for i, value in ipairs(results[first[1]][key]) do vector[i] = first[2] * value end
        for term = 2, #combination.terms do
            local name, factor = table.unpack(combination.terms[term])
            for i, value in ipairs(results[name][key]) do vector[i] = vector[i] + factor * value end
        end
        result[key] = vector
    end
    return result
end
function M.equilibrium_residual(result, geometry)
    local residual = {}
    for i = 1, #result.external do residual[i] = result.external[i] + result.reactions[i] end
    for number, shape in ipairs(geometry) do
        local direction = {shape.cosine, shape.sine, -shape.cosine, -shape.sine}
        for i, degree in ipairs(shape.dofs) do residual[degree] = residual[degree] + result.forces[number] * direction[i] end
    end
    local maximum = 0.0
    for _, value in ipairs(residual) do maximum = math.max(maximum, math.abs(value)) end
    return maximum
end
return M
