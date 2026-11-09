local base = require('alignment').base
local M = {models = {'P', 'JC', 'K2P'}}
function M.pair(first, second, weights)
    local n, s, v = 0, 0, 0
    for i, w in ipairs(weights) do
        local a, b = first:sub(i, i), second:sub(i, i)
        if base[a] and base[b] then
            n = n + w
            if a ~= b then
                if (a == 'A' and b == 'G') or (a == 'G' and b == 'A') or (a == 'C' and b == 'T') or (a == 'T' and b == 'C') then s = s + w else v = v + w end
            end
        end
    end
    return n, s, v
end
function M.all(sequences, weights)
    local out = {}
    for i = 1, #sequences do
        for j = i + 1, #sequences do
            local n, s, v = M.pair(sequences[i], sequences[j], weights)
            out[#out + 1] = {i = i, j = j, n = n, s = s, v = v}
        end
    end
    return out
end
function M.correct(model, n, s, v, replacement)
    local saturated = n == 0
    if model == 'JC' then saturated = saturated or 4 * (s + v) >= 3 * n
    elseif model == 'K2P' then saturated = saturated or 2 * s + v >= n or 2 * v >= n end
    if saturated then return replacement, true end
    if model == 'P' then return (s + v) / n, false end
    if model == 'JC' then return -0.75 * math.log(1 - 4 * (s + v) / (3 * n)), false end
    return -0.5 * math.log(1 - 2 * s / n - v / n) - 0.25 * math.log(1 - 2 * v / n), false
end
function M.matrix(pairs_list, count, model, replacement)
    local matrix, saturated = {}, {}
    for i = 1, count do matrix[i] = {}; for j = 1, count do matrix[i][j] = 0.0 end end
    for _, pair in ipairs(pairs_list) do
        local value, sat = M.correct(model, pair.n, pair.s, pair.v, replacement)
        matrix[pair.i][pair.j], matrix[pair.j][pair.i] = value, value
        if sat then saturated[#saturated + 1] = pair end
    end
    return matrix, saturated
end
return M
