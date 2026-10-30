local M = {}
function M.maximum(values)
    local best = 1
    for i = 2, #values do if values[i] > values[best] then best = i end end
    return best
end
function M.emissions(model, observation, logarithms)
    local result = {}
    for state, row in ipairs(model.emission) do
        local value = observation == -1 and 1.0 or row[observation]
        result[state] = logarithms and math.log(value) or value
    end
    return result
end
function M.forward(model, observations)
    local result = {forward = {}, scales = {}, emissions = {}, loglik = 0.0}
    for t, observation in ipairs(observations) do
        local factors = M.emissions(model, observation, false)
        local row, scale = {}, 0.0
        for j = 1, #model.states do
            local value
            if t == 1 then value = model.initial[j] * factors[j]
            else
                local total = 0.0
                for i = 1, #model.states do total = total + result.forward[t - 1][i] * model.transition[i][j] end
                value = total * factors[j]
            end
            row[j], scale = value, scale + value
        end
        result.scales[t], result.emissions[t] = scale, factors
        for j = 1, #row do row[j] = row[j] / scale end
        result.forward[t] = row
        result.loglik = result.loglik + math.log(scale)
    end
    return result
end
function M.forward_backward(model, observations)
    local result = M.forward(model, observations)
    result.backward, result.posterior = {}, {}
    for t = 1, #observations do result.backward[t] = {} end
    for i = 1, #model.states do result.backward[#observations][i] = 1.0 end
    for t = #observations - 1, 1, -1 do
        for i = 1, #model.states do
            local total = 0.0
            for j = 1, #model.states do
                total = total + model.transition[i][j] * result.emissions[t + 1][j] * result.backward[t + 1][j]
            end
            result.backward[t][i] = total / result.scales[t + 1]
        end
    end
    for t = 1, #observations do
        result.posterior[t] = {}
        for i = 1, #model.states do result.posterior[t][i] = result.forward[t][i] * result.backward[t][i] end
    end
    return result
end
function M.transition_probability(model, result, t, i, j)
    return result.forward[t][i] * model.transition[i][j] * result.emissions[t + 1][j]
        * result.backward[t + 1][j] / result.scales[t + 1]
end
function M.viterbi(model, observations)
    local scores, predecessors, log_transition = {}, {{}}, {}
    for i, row in ipairs(model.transition) do
        log_transition[i] = {}
        for j, value in ipairs(row) do log_transition[i][j] = math.log(value) end
    end
    local factors = M.emissions(model, observations[1], true)
    for j = 1, #model.states do scores[j] = math.log(model.initial[j]) + factors[j] end
    for t = 2, #observations do
        local next_scores, previous_states = {}, {}
        factors = M.emissions(model, observations[t], true)
        for j = 1, #model.states do
            local candidates = {}
            for i = 1, #model.states do candidates[i] = scores[i] + log_transition[i][j] end
            local previous = M.maximum(candidates)
            previous_states[j], next_scores[j] = previous, candidates[previous] + factors[j]
        end
        scores, predecessors[t] = next_scores, previous_states
    end
    local path = {}
    path[#observations] = M.maximum(scores)
    local logprob = scores[path[#observations]]
    for t = #observations, 2, -1 do path[t - 1] = predecessors[t][path[t]] end
    return path, logprob
end
function M.decode(model, observations)
    local fb = M.forward_backward(model, observations)
    local path, logprob = M.viterbi(model, observations)
    local posterior, confidence = {}, {}
    for t, row in ipairs(fb.posterior) do posterior[t] = M.maximum(row); confidence[t] = row[posterior[t]] end
    return {viterbi = path, logprob = logprob, posterior = posterior, confidence = confidence, fb = fb}
end
return M
