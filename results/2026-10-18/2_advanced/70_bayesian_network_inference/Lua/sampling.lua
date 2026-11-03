local parent_row = require('learning').parent_row
local M = {}
function M.generator(seed) return {state = seed} end
function M.uniform(random)
    random.state = (48271 * random.state) % 2147483647
    return random.state / 2147483647
end
function M.choose(probabilities, random)
    local uniform, cumulative = M.uniform(random), 0.0
    for state, probability in ipairs(probabilities) do cumulative = cumulative + probability; if uniform < cumulative then return state end end
    return #probabilities
end
function M.weighted_sample(topological, parents, cpts, sizes, evidence, random)
    local sample, weight = {}, 1.0
    for _, v in ipairs(topological) do
        local row = cpts[v][parent_row(parents[v], sample, sizes)]
        if evidence[v] then sample[v] = evidence[v]; weight = weight * row[evidence[v]]
        else sample[v] = M.choose(row, random) end
    end
    return sample, weight
end
return M
