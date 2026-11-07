local N = require("network")
local O = {}
function O.initialize(count)
    return { momentum = N.zeros(count), first = N.zeros(count), second = N.zeros(count), power1 = 1.0, power2 = 1.0 }
end
function O.rate(run, epoch, step, gamma)
    local rate = run.rate
    for _ = 1, (epoch - 1) // step do rate = rate * gamma end
    return rate
end
function O.update(theta, gradient, state, run, rate)
    if run.optimizer == "SGD" then
        for i, value in ipairs(gradient) do theta[i] = theta[i] - rate * value end
    elseif run.optimizer == "MOMENTUM" then
        local mu = run.extra[1]
        for i, value in ipairs(gradient) do
            state.momentum[i] = mu * state.momentum[i] + value
            theta[i] = theta[i] - rate * state.momentum[i]
        end
    else
        local beta1, beta2, epsilon = table.unpack(run.extra)
        state.power1, state.power2 = state.power1 * beta1, state.power2 * beta2
        for i, value in ipairs(gradient) do
            state.first[i], state.second[i] = beta1 * state.first[i] + (1 - beta1) * value, beta2 * state.second[i] + (1 - beta2) * value * value
            local first, second = state.first[i] / (1 - state.power1), state.second[i] / (1 - state.power2)
            theta[i] = theta[i] - rate * first / (math.sqrt(second) + epsilon)
        end
    end
end
return O
