local M = {}
function M.sum(values)
    local result = 0.0
    for _, value in ipairs(values) do
        result = result + value
    end
    return result
end
function M.cv(observed, predicted)
    local result = 0.0
    for i, value in ipairs(observed) do
        if predicted[i] == nil then
            return nil
        end
        local residual = value - predicted[i]
        result = result + residual * residual
    end
    return result / #observed
end
function M.gcv(observed, fitted, edf)
    local factor = 1 - edf / #observed
    return M.cv(observed, fitted) / (factor * factor)
end
function M.choose(candidates)
    local best
    for i, candidate in ipairs(candidates) do
        if candidate.score ~= nil and (not best or candidate.score < candidates[best].score) then
            best = i
        end
    end
    return best
end
return M
