local fixed = require("fixed_point")
local vector = require("vector3")
local M = {}
function M.base_color(material, point)
    if material.checker then
        local color, size = table.unpack(material.checker)
        local parity = point[1] // size + point[2] // size + point[3] // size
        if parity % 2 ~= 0 then return color end
    end
    return material.color
end
function M.phong(material, normal, light, view, ndl, intensity, factor)
    local effective = fixed.mul(intensity, factor)
    local diffuse = fixed.mul(fixed.mul(material.kd, ndl), effective)
    local reflected = vector.sub(vector.scale(normal, 2 * ndl), light)
    local rv, specular = vector.dot(reflected, view), 0
    if rv > 0 then
        local power = 4096
        for _ = 1, material.n do power = fixed.mul(power, rv) end
        specular = fixed.mul(fixed.mul(material.ks, power), effective)
    end
    return diffuse, specular
end
function M.reflected(direction, normal)
    return vector.norm(vector.sub(direction, vector.scale(normal, 2 * vector.dot(direction, normal))))
end
function M.refraction(material, direction, normal, front)
    local wr, wt = material.kr, material.kt
    if wt == 0 then return wr, wt, nil, false end
    local eta = front and (4096 * 4096) // material.ior or material.ior
    local cosine = -vector.dot(direction, normal)
    local discriminant = 4096 * 4096 - (fixed.mul(eta, eta) * (4096 * 4096 - cosine * cosine)) // 4096
    if discriminant < 0 then return wr + wt, 0, nil, true end
    local transmitted = vector.norm(vector.add(vector.scale(direction, eta), vector.scale(normal, fixed.mul(eta, cosine) - fixed.isqrt(discriminant))))
    local r0 = ((material.ior - 4096) * 4096) // (material.ior + 4096)
    local reflectance, x, power = fixed.mul(r0, r0), 4096 - math.min(cosine, 4096), 4096
    for _ = 1, 5 do power = fixed.mul(power, x) end
    local fresnel = reflectance + fixed.mul(4096 - reflectance, power)
    local transfer = fixed.mul(material.kt, fresnel)
    return wr + transfer, wt - transfer, transmitted, false
end
function M.mix(colors, weights)
    local result = {0, 0, 0}
    for i, color in ipairs(colors) do
        for axis = 1, 3 do result[axis] = result[axis] + (color[axis] * weights[i]) // 4096 end
    end
    return result
end
return M
