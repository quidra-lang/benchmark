local M = {}
function M.total(values)
    local result = 0.0
    for _, value in ipairs(values) do result = result + value end
    return result
end
function M.parent_row(parents, assignment, sizes)
    local row = 0
    for _, parent in ipairs(parents) do row = row * sizes[parent] + assignment[parent] - 1 end
    return row + 1
end
function M.count_samples(variable, parents, samples, sizes)
    local row_count, counts = 1, {}
    for _, parent in ipairs(parents) do row_count = row_count * sizes[parent] end
    for r = 1, row_count do counts[r] = {}; for s = 1, sizes[variable] do counts[r][s] = 0 end end
    for _, sample in ipairs(samples) do local row = counts[M.parent_row(parents, sample, sizes)]; row[sample[variable]] = row[sample[variable]] + 1 end
    return counts
end
function M.learn(counts, alpha)
    local result = {}
    for r, row in ipairs(counts) do
        local denominator = 0.0
        for _, count in ipairs(row) do denominator = denominator + (count + alpha) end
        result[r] = {}
        for s, count in ipairs(row) do result[r][s] = (count + alpha) / denominator end
    end
    return result
end
function M.log_likelihood(counts, cpt)
    local result = 0.0
    for r, row in ipairs(counts) do for s, count in ipairs(row) do if count ~= 0 then result = result + count * math.log(cpt[r][s]) end end end
    return result
end
function M.parameter_count(counts) return (#counts[1] - 1) * #counts end
function M.family_score(variable, parents, samples, sizes, alpha)
    local ordered = {}
    for _, parent in ipairs(parents) do ordered[#ordered + 1] = parent end
    table.sort(ordered)
    local counts = M.count_samples(variable, ordered, samples, sizes)
    return M.log_likelihood(counts, M.learn(counts, alpha)) - M.parameter_count(counts) * math.log(#samples) / 2
end
return M
