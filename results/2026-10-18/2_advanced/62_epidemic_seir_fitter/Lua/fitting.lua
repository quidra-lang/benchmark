local F = {}
function F.golden(objective, a, b, iterations)
    local phi = 0.6180339887498949
    local c, d = b - phi * (b - a), a + phi * (b - a)
    local fc, fd = objective(c), objective(d)
    local records = { { a, b, c, d, fc, fd } }
    for _ = 1, iterations do
        if fc < fd then b, d, fd = d, c, fc; c = b - phi * (b - a); fc = objective(c)
        else a, c, fc = c, d, fd; d = a + phi * (b - a); fd = objective(d) end
        records[#records + 1] = { a, b, c, d, fc, fd }
    end
    if fc < fd then return c, fc, records end
    return d, fd, records
end
function F.nelder_mead(objective, beta, gamma, delta_beta, delta_gamma, alpha, chi, psi, omega, iterations)
    local vertices = {
        { number = 0, beta = beta, gamma = gamma }, { number = 1, beta = beta + delta_beta, gamma = gamma }, { number = 2, beta = beta, gamma = gamma + delta_gamma }
    }
    local initial, records, serial = {}, {}, 3
    for i, vertex in ipairs(vertices) do vertex.value = objective(vertex.beta, vertex.gamma); initial[i] = vertex end
    local function order(a, b) return a.value < b.value or a.value == b.value and a.number < b.number end
    local function toward(a, b, factor) return { beta = a.beta + factor * (b.beta - a.beta), gamma = a.gamma + factor * (b.gamma - a.gamma) } end
    for _ = 1, iterations do
        table.sort(vertices, order)
        local first, second, third = vertices[1], vertices[2], vertices[3]
        local centroid = { beta = (first.beta + second.beta) / 2, gamma = (first.gamma + second.gamma) / 2 }
        local reflected = { beta = centroid.beta + alpha * (centroid.beta - third.beta), gamma = centroid.gamma + alpha * (centroid.gamma - third.gamma) }
        local fr = objective(reflected.beta, reflected.gamma)
        local accepted, value, operation
        if fr < first.value then
            local expanded = toward(centroid, reflected, chi)
            local fe = objective(expanded.beta, expanded.gamma)
            if fe < fr then accepted, value, operation = expanded, fe, "expand" else accepted, value, operation = reflected, fr, "reflect" end
        elseif fr < second.value then accepted, value, operation = reflected, fr, "reflect"
        elseif fr < third.value then
            local contracted = toward(centroid, reflected, psi)
            local fc = objective(contracted.beta, contracted.gamma)
            if fc <= fr then accepted, value, operation = contracted, fc, "contract_out" end
        else
            local contracted = toward(centroid, third, psi)
            local fc = objective(contracted.beta, contracted.gamma)
            if fc < third.value then accepted, value, operation = contracted, fc, "contract_in" end
        end
        if accepted then
            accepted.number, accepted.value = serial, value
            serial, vertices = serial + 1, { first, second, accepted }
        else
            operation, vertices = "shrink", { first }
            for _, vertex in ipairs({ second, third }) do
                local point = toward(first, vertex, omega)
                point.number, point.value = serial, objective(point.beta, point.gamma)
                vertices[#vertices + 1], serial = point, serial + 1
            end
        end
        table.sort(vertices, order)
        records[#records + 1] = { operation, vertices[1] }
    end
    return initial, records, vertices
end
return F
