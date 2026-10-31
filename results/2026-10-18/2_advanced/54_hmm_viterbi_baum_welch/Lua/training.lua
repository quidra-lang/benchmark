local model_io = require("model_io")
local inference = require("inference")
local M = {}
local function counts(template)
    local initial, transition, emission = {}, {}, {}
    for i = 1, #template.states do
        initial[i], transition[i], emission[i] = 0.0, {}, {}
        for j = 1, #template.states do transition[i][j] = 0.0 end
        for c = 1, #template.symbols do emission[i][c] = 0.0 end
    end
    return initial, transition, emission
end
local function smoothed(template, name, initial, transition, emission, alpha)
    for i = 1, #initial do
        initial[i] = initial[i] + alpha
        for j = 1, #transition[i] do transition[i][j] = transition[i][j] + alpha end
        for c = 1, #emission[i] do emission[i][c] = emission[i][c] + alpha end
    end
    return model_io.model(name, template, initial, transition, emission)
end
function M.baum_welch_step(model, sequences, pseudocount)
    local initial, transition, emission = counts(model)
    for _, observations in ipairs(sequences) do
        local fb = inference.forward_backward(model, observations)
        for i = 1, #model.states do initial[i] = initial[i] + fb.posterior[1][i] end
        for t, observation in ipairs(observations) do
            for i = 1, #model.states do
                if observation ~= -1 then emission[i][observation] = emission[i][observation] + fb.posterior[t][i] end
                if t < #observations then
                    for j = 1, #model.states do transition[i][j] = transition[i][j] + inference.transition_probability(model, fb, t, i, j) end
                end
            end
        end
    end
    return smoothed(model, "BAUM_WELCH", initial, transition, emission, pseudocount)
end
function M.count(template, records, alpha, name)
    local initial, transition, emission = counts(template)
    for _, record in ipairs(records) do
        local path, observations = record.path, record.observations
        initial[path[1]] = initial[path[1]] + 1
        for t, state in ipairs(path) do
            local observation = observations[t]
            if observation ~= -1 then emission[state][observation] = emission[state][observation] + 1 end
            if t < #path then transition[state][path[t + 1]] = transition[state][path[t + 1]] + 1 end
        end
    end
    return smoothed(template, name or "SUPERVISED", initial, transition, emission, alpha)
end
function M.total_loglik(model, sequences)
    local total = 0.0
    for _, observations in ipairs(sequences) do total = total + inference.forward(model, observations).loglik end
    return total
end
return M
