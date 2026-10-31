local vector = require("vector3")
local M = {}
function M.read()
    local result = {materials = {}, objects = {}, lights = {}}
    local input = assert(io.open("input/scene.txt", "r"))
    for line in input:lines() do
        if line ~= "" and line:sub(1, 1) ~= "#" then
            local fields = {}
            for word in line:gmatch("%S+") do fields[#fields + 1] = word end
            local kind = fields[1]
            if kind == "material" then
                local values = {}
                for j = 3, #fields do values[#values + 1] = tonumber(fields[j]) end
                result.materials[fields[2]] = {name = fields[2], color = {values[1], values[2], values[3]},
                    kd = values[4], ks = values[5], n = values[6], kr = values[7], kt = values[8], ior = values[9]}
            elseif kind == "checker" then
                result.materials[fields[2]].checker = {{tonumber(fields[3]), tonumber(fields[4]), tonumber(fields[5])}, tonumber(fields[6])}
            elseif kind == "sphere" or kind == "plane" or kind == "box" then
                local values = {}
                for j = 4, #fields do values[#values + 1] = tonumber(fields[j]) end
                local object = {number = #result.objects + 1, kind = kind, label = fields[2], material = result.materials[fields[3]]}
                if kind == "sphere" then object.center, object.radius = {values[1], values[2], values[3]}, values[4]
                elseif kind == "plane" then object.point, object.normal = {values[1], values[2], values[3]}, vector.norm({values[4], values[5], values[6]})
                else object.low, object.high = {values[1], values[2], values[3]}, {values[4], values[5], values[6]} end
                result.objects[#result.objects + 1] = object
            else
                local values = {}
                for j = 2, #fields do values[#values + 1] = tonumber(fields[j]) end
                if kind == "point" or kind == "spot" or kind == "sun" or kind == "area" then
                    local light = {number = #result.lights + 1, kind = kind, intensity = values[#values], samples = 1}
                    if kind == "sun" then light.direction = vector.norm(vector.neg({values[1], values[2], values[3]}))
                    else
                        light.position = {values[1], values[2], values[3]}
                        if kind == "spot" then light.direction, light.outer, light.inner = vector.norm({values[4], values[5], values[6]}), values[7], values[8]
                        elseif kind == "area" then
                            light.u, light.v, light.divisions = {values[4], values[5], values[6]}, {values[7], values[8], values[9]}, values[10]
                            light.samples = light.divisions * light.divisions
                        end
                    end
                    result.lights[#result.lights + 1] = light
                elseif kind == "ambient" then result.ambient = values[1]
                else result[kind] = values end
            end
        end
    end
    input:close()
    return result
end
return M
