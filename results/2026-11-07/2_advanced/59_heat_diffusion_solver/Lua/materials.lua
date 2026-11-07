local M = {}
function M.number(text) return tonumber(text) + 0.0 end
function M.read()
    local input = assert(io.open('input/materials.txt', 'r'))
    local result = {}
    for line in input:lines() do
        local code, name, k, rho, cp = line:match('(%S+) (%S+) (%S+) (%S+) (%S+)')
        result[#result + 1] = {code = code, name = name, k = M.number(k), rho = M.number(rho), cp = M.number(cp)}
    end
    input:close()
    return result
end
function M.capacity(material, dx, thickness) return material.rho * material.cp * dx * dx * thickness end
function M.interior(first, second, thickness) return 2 * first * second / (first + second) * thickness end
function M.fixed(k, thickness) return 2 * k * thickness end
function M.convective(k, h, dx, thickness) return 1 / (1 / (h * dx * thickness) + 1 / (2 * k * thickness)) end
return M
