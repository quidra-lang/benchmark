local M = {}
function M.generator(seed)
    return {state = seed}
end
function M.draw(weights, generator)
    local total = 0.0
    for _, weight in ipairs(weights) do total = total + weight end
    generator.state = (48271 * generator.state) % 2147483647
    local threshold = (generator.state / 2147483647) * total
    local cumulative = 0.0
    for i, weight in ipairs(weights) do
        cumulative = cumulative + weight
        if threshold < cumulative then return i end
    end
    return #weights
end
function M.synthetic(model, length, generator)
    local states, observations = {}, {}
    for t = 1, length do
        local weights = t == 1 and model.initial or model.transition[states[t - 1]]
        local state = M.draw(weights, generator)
        states[t], observations[t] = state, M.draw(model.emission[state], generator)
    end
    return states, observations
end
function M.posterior_path(model, forward, generator)
    local path = {}
    path[#forward] = M.draw(forward[#forward], generator)
    for t = #forward - 1, 1, -1 do
        local weights = {}
        for i = 1, #model.states do weights[i] = forward[t][i] * model.transition[i][path[t + 1]] end
        path[t] = M.draw(weights, generator)
    end
    return path
end
return M
