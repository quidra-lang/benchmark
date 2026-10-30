local M = {}
function M.seird(population, sigma, fatality, beta, gamma)
    return function(state, multiplier)
        local s, e, i = state[1], state[2], state[3]
        local flow, progression, removal = beta * multiplier * s * i / population, sigma * e, gamma * i
        return { -flow, flow - progression, progression - removal, (1 - fatality) * gamma * i, fatality * gamma * i, progression }
    end
end
function M.sir(population, beta, gamma)
    return function(state, multiplier)
        local flow, removal = beta * multiplier * state[1] * state[2] / population, gamma * state[2]
        return { -flow, flow - removal, removal, flow }
    end
end
function M.age_seird(populations, fatalities, sigma, beta, gamma, contacts)
    return function(state, multiplier)
        local result = {}
        for group in ipairs(populations) do
            local start, pressure = 6 * (group - 1) + 1, 0.0
            for other, population in ipairs(populations) do pressure = pressure + contacts[group][other] * state[6 * (other - 1) + 3] / population end
            local force = beta * multiplier * pressure
            local s, e, i = state[start], state[start + 1], state[start + 2]
            local flow, progression, removal = force * s, sigma * e, gamma * i
            local values = { -flow, flow - progression, progression - removal, (1 - fatalities[group]) * gamma * i, fatalities[group] * gamma * i, progression }
            for _, value in ipairs(values) do result[#result + 1] = value end
        end
        return result
    end
end
function M.generation(sigma, gamma)
    return function(state)
        local progression, removal = sigma * state[1], gamma * state[2]
        return { -progression, progression - removal, removal }
    end
end
return M
