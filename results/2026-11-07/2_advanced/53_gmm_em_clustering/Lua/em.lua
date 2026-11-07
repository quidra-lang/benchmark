local gaussian = require("gaussian")
local M = {}
function M.adjust(initial, kind)
    local result = {weights = {}, means = {}, covariances = {}}
    local shared = {0.0, 0.0, 0.0}
    if kind == "TIED" then
        for column = 1, 3 do
            for k, weight in ipairs(initial.weights) do
                shared[column] = shared[column] + weight * initial.covariances[k][column]
            end
        end
    end
    for k, weight in ipairs(initial.weights) do
        local a, b, c = table.unpack(initial.covariances[k])
        if kind == "DIAG" then b = 0.0
        elseif kind == "SPHERICAL" then a, b, c = (a + c) / 2, 0.0, (a + c) / 2
        elseif kind == "TIED" then a, b, c = table.unpack(shared) end
        result.weights[k] = weight
        result.means[k] = {table.unpack(initial.means[k])}
        result.covariances[k] = {a, b, c}
    end
    return result
end
function M.expectation(points, model)
    local records, loglik = {}, 0.0
    for i, point in ipairs(points) do
        local scores, maximum = {}, -math.huge
        for k, weight in ipairs(model.weights) do
            scores[k] = gaussian.log_density({point.x, point.y}, weight, model.means[k], model.covariances[k])
            maximum = math.max(maximum, scores[k])
        end
        local r, total = {}, 0.0
        for k, score in ipairs(scores) do
            r[k] = math.exp(score - maximum)
            total = total + r[k]
        end
        for k = 1, #r do r[k] = r[k] / total end
        local lp = maximum + math.log(total)
        records[i] = {r = r, lp = lp}
        loglik = loglik + lp
    end
    return records, loglik
end
function M.maximization(points, records, kind, eps)
    local model = {weights = {}, means = {}, covariances = {}}
    local counts, scatter = {}, {}
    local n, count = #points, #records[1].r
    for k = 1, count do
        local nk, sx, sy = 0.0, 0.0, 0.0
        for i, point in ipairs(points) do
            local r = records[i].r[k]
            nk = nk + r
            sx = sx + r * point.x
            sy = sy + r * point.y
        end
        counts[k], model.weights[k] = nk, nk / n
        local mx, my = sx / nk, sy / nk
        model.means[k] = {mx, my}
        local a, b, c = 0.0, 0.0, 0.0
        for i, point in ipairs(points) do
            local r = records[i].r[k]
            local dx, dy = point.x - mx, point.y - my
            a, b, c = a + r * dx * dx, b + r * dx * dy, c + r * dy * dy
        end
        scatter[k] = {a, b, c}
    end
    if kind == "TIED" then
        local shared = {0.0, 0.0, 0.0}
        for column = 1, 3 do
            for k = 1, count do shared[column] = shared[column] + scatter[k][column] end
            shared[column] = shared[column] / n
        end
        shared[1], shared[3] = shared[1] + eps, shared[3] + eps
        for k = 1, count do model.covariances[k] = {table.unpack(shared)} end
    else
        for k = 1, count do
            local a, b, c = table.unpack(scatter[k])
            local nk = counts[k]
            if kind == "FULL" then a, b, c = a / nk + eps, b / nk, c / nk + eps
            elseif kind == "DIAG" then a, b, c = a / nk + eps, 0.0, c / nk + eps
            else a, b, c = (a / nk + c / nk) / 2 + eps, 0.0, (a / nk + c / nk) / 2 + eps end
            model.covariances[k] = {a, b, c}
        end
    end
    return model
end
function M.run(points, initial, kind, iterations, eps)
    local model = M.adjust(initial, kind)
    local records, loglik = M.expectation(points, model)
    local trace = {loglik}
    for _ = 1, iterations do
        model = M.maximization(points, records, kind, eps)
        records, loglik = M.expectation(points, model)
        trace[#trace + 1] = loglik
    end
    return {model = model, records = records, trace = trace, loglik = loglik}
end
return M
