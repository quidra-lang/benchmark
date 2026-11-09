local K = require("kernels")
local S = require("smo")
local M = { pairs = { { 1, 2 }, { 1, 3 }, { 2, 3 } } }
M.__index = M
function M.new(examples, kernel, coefficient, settings)
    local result = setmetatable({ kernel = kernel, C = coefficient, ovr_models = {}, ovo_models = {} }, M)
    local points, classes = {}, {}
    for i, example in ipairs(examples) do points[i], classes[i] = example.point, example.label end
    local matrix = kernel:matrix(points)
    for class = 1, 3 do
        local labels = {}
        for i, value in ipairs(classes) do labels[i] = value == class and 1 or -1 end
        result.ovr_models[class] = S.train(points, labels, kernel, matrix, coefficient, settings)
    end
    for _, pair in ipairs(M.pairs) do
        local indices, pair_points, labels = {}, {}, {}
        for i, class in ipairs(classes) do
            if class == pair[1] or class == pair[2] then indices[#indices + 1], pair_points[#pair_points + 1], labels[#labels + 1] = i, points[i], class == pair[1] and 1 or -1 end
        end
        result.ovo_models[#result.ovo_models + 1] = S.train(pair_points, labels, kernel, K.submatrix(matrix, indices), coefficient, settings)
    end
    return result
end
function M:classify(point)
    local rest_values, rest = {}, 1
    for i, model in ipairs(self.ovr_models) do rest_values[i] = model:decision(point); if rest_values[i] > rest_values[rest] then rest = i end end
    local pair_values, votes, scores = {}, { 0, 0, 0 }, { 0.0, 0.0, 0.0 }
    for i, pair in ipairs(M.pairs) do
        local value = self.ovo_models[i]:decision(point)
        local winner = value > 0 and pair[1] or pair[2]
        pair_values[i], votes[winner] = value, votes[winner] + 1
        scores[pair[1]], scores[pair[2]] = scores[pair[1]] + value, scores[pair[2]] - value
    end
    local largest, chosen, ties = math.max(table.unpack(votes)), nil, 0
    for i = 1, 3 do
        if votes[i] == largest then
            ties = ties + 1
            if not chosen or scores[i] > scores[chosen] then chosen = i end
        end
    end
    return { ovr_values = rest_values, ovo_values = pair_values, votes = votes, ovr = rest, ovo = chosen, tied = ties > 1 }
end
return M
