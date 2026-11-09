local numeric = require("numerics")
local M = {}
function M.evaluate(subjects, vectors, beta)
    local size, predictors, risks, order = #beta, {}, {}, {}
    for index, vector in ipairs(vectors) do
        local value = 0.0
        for c = 1, size do
            value = value + beta[c] * vector[c]
        end
        predictors[index], risks[index], order[index] = value, math.exp(value), index
    end
    table.sort(order, function(a, b)
        if subjects[a].time ~= subjects[b].time then
            return subjects[a].time > subjects[b].time
        end
        return subjects[a].id < subjects[b].id
    end)
    local s0, s1, s2 = 0.0, numeric.zeros(size), numeric.matrix(size, size)
    local likelihood, score, information = 0.0, numeric.zeros(size), numeric.matrix(size, size)
    local event_sums, position = {}, 1
    while position <= #order do
        local moment = subjects[order[position]].time
        local events = {}
        while position <= #order and subjects[order[position]].time == moment do
            local index = order[position]
            local risk, vector = risks[index], vectors[index]
            s0 = s0 + risk
            for c = 1, size do
                s1[c] = s1[c] + risk * vector[c]
                for d = 1, size do
                    s2[c][d] = s2[c][d] + risk * vector[c] * vector[d]
                end
            end
            if subjects[index].event == 1 then
                events[#events + 1] = index
            end
            position = position + 1
        end
        if #events > 0 then
            local sum = 0.0
            for _, index in ipairs(events) do
                sum = sum + predictors[index]
            end
            likelihood = likelihood + (sum - #events * math.log(s0))
            for c = 1, size do
                local sum_x = 0
                for _, index in ipairs(events) do
                    sum_x = sum_x + vectors[index][c]
                end
                score[c] = score[c] + (sum_x - #events * s1[c] / s0)
                for d = 1, size do
                    information[c][d] = information[c][d] + #events * (s2[c][d] / s0 - (s1[c] / s0) * (s1[d] / s0))
                end
            end
            event_sums[moment] = {s0 = s0, s1 = numeric.copy(s1), events = #events}
        end
    end
    return {loglik = likelihood, score = score, information = information, predictors = predictors, event_sums = event_sums}
end
function M.fit(subjects, vectors)
    local beta = numeric.zeros(#vectors[1])
    local null = M.evaluate(subjects, vectors, beta)
    local current, iterations = null, {}
    for iteration = 1, 25 do
        local change = numeric.solve(current.information, current.score)
        for c = 1, #beta do
            beta[c] = beta[c] + change[c]
        end
        iterations[#iterations + 1] = {iteration = iteration, loglik = current.loglik, beta = numeric.copy(beta)}
        current = M.evaluate(subjects, vectors, beta)
    end
    return {beta = beta, null = null, final = current, iterations = iterations}
end
return M
