local M = {PI = 3.141592653589793}
function M.buckling(properties, geometry, inertia)
    return M.PI * M.PI * properties.young * (inertia or properties.inertia) / (geometry.length * geometry.length)
end
function M.utilization(force, properties, geometry, section)
    local area, inertia = properties.area, properties.inertia
    if section then area, inertia = section.area, section.inertia end
    return math.max(math.abs(force / area) / properties.yield_stress, math.max(0, -force) / M.buckling(properties, geometry, inertia))
end
function M.slenderness(properties, geometry, section)
    local area, inertia = properties.area, properties.inertia
    if section then area, inertia = section.area, section.inertia end
    return geometry.length / math.sqrt(inertia / area)
end
function M.slenderness_limit(number, combinations, limits)
    for _, result in ipairs(combinations) do if result.forces[number] < 0 then return limits[1] end end
    return limits[2]
end
function M.select_section(members, sections, properties, geometry, combinations, limits)
    for number, section in ipairs(sections) do
        local acceptable = true
        for _, member in ipairs(members) do
            if M.slenderness(properties[member], geometry[member], section) > limits[member] then acceptable = false; break end
            for _, result in ipairs(combinations) do if M.utilization(result.forces[member], properties[member], geometry[member], section) > 1 then acceptable = false; break end end
            if not acceptable then break end
        end
        if acceptable then return number end
    end
    return #sections
end
return M
