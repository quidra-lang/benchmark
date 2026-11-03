local M = {}
function M.zeros(size)
    local result = {}
    for i = 1, size do result[i] = 0.0 end
    return result
end
function M.member_geometry(nodes, members, node_dofs)
    local result = {}
    for i, member in ipairs(members) do
        local a, b = nodes[member.start], nodes[member.finish]
        local dx, dy = b.x - a.x, b.y - a.y
        local length = math.sqrt(dx * dx + dy * dy)
        result[i] = {length = length, cosine = dx / length, sine = dy / length,
            dofs = {node_dofs[member.start][1], node_dofs[member.start][2], node_dofs[member.finish][1], node_dofs[member.finish][2]}}
    end
    return result
end
function M.member_properties(model, choices, geometry)
    local result = {}
    for i, member in ipairs(model.members) do
        local section, material = model.sections[choices[i]], model.materials[member.material]
        result[i] = {area = section.area, inertia = section.inertia, young = material.young, yield_stress = material.yield_stress,
            density = material.density, expansion = material.expansion, stiffness = material.young * section.area / geometry[i].length}
    end
    return result
end
function M.member_weight(properties, geometry) return properties.density * 9.81 * properties.area * geometry.length / 1000000000 end
function M.member_stiffness(properties, geometry)
    local k, c, s = properties.stiffness, geometry.cosine, geometry.sine
    local xx, xy, yy = k * (c * c), k * (c * s), k * (s * s)
    return {{xx, xy, -xx, -xy}, {xy, yy, -xy, -yy}, {-xx, -xy, xx, xy}, {-xy, -yy, xy, yy}}
end
function M.assemble(geometry, properties, degrees, removed)
    local matrix = {}
    for i = 1, degrees do matrix[i] = M.zeros(degrees) end
    for number, shape in ipairs(geometry) do
        if number ~= removed then
            local stiffness = M.member_stiffness(properties[number], shape)
            for i, row in ipairs(shape.dofs) do for j, column in ipairs(shape.dofs) do matrix[row][column] = matrix[row][column] + stiffness[i][j] end end
        end
    end
    return matrix
end
function M.load_vectors(case, geometry, properties, node_dofs, degrees, removed)
    local external, thermal, temperature, settlement = M.zeros(degrees), M.zeros(degrees), M.zeros(#geometry), false
    for _, load in ipairs(case.lines) do
        if load[1] == 'FORCE' then
            local dofs = node_dofs[load[2]]
            external[dofs[1]], external[dofs[2]] = external[dofs[1]] + load[3] * 1000, external[dofs[2]] + load[4] * 1000
        elseif load[1] == 'TEMPERATURE' then
            local number = load[2]
            if number ~= removed then
                local p, shape = properties[number], geometry[number]
                local force = p.young * p.area * p.expansion * load[3]
                temperature[number] = force
                local direction = {-shape.cosine, -shape.sine, shape.cosine, shape.sine}
                for i, degree in ipairs(shape.dofs) do thermal[degree] = thermal[degree] + force * direction[i] end
            end
        elseif load[1] == 'SELFWEIGHT' then
            for number, shape in ipairs(geometry) do
                if number ~= removed then
                    local weight = M.member_weight(properties[number], shape)
                    external[shape.dofs[2]] = external[shape.dofs[2]] - weight / 2
                    external[shape.dofs[4]] = external[shape.dofs[4]] - weight / 2
                end
            end
        else settlement = true end
    end
    local total = {}
    for i = 1, degrees do total[i] = external[i] + thermal[i] end
    return {external = external, total = total, temperature = temperature, settlement = settlement}
end
return M
