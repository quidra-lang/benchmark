local M = {}

function M.class_counts(rows, size)
    local counts = {}
    for index = 1, size do counts[index] = 0 end
    for _, row in ipairs(rows) do counts[row.label] = counts[row.label] + 1 end
    return counts
end

function M.sum(values)
    local total = 0
    for _, value in ipairs(values) do total = total + value end
    return total
end

function M.square_sum(counts)
    local total = 0
    for _, value in ipairs(counts) do total = total + value * value end
    return total
end

function M.majority(counts)
    local best = 1
    for index = 2, #counts do
        if counts[index] > counts[best] then best = index end
    end
    return best
end

function M.evaluation_value(left, right)
    local nl, nr = M.sum(left), M.sum(right)
    return {M.square_sum(left) * nr + M.square_sum(right) * nl, nl * nr}
end

function M.compare(first, second)
    local a, b = first[1] * second[2], second[1] * first[2]
    return a < b and -1 or (a > b and 1 or 0)
end

function M.improves(value, counts)
    return value[1] * M.sum(counts) > M.square_sum(counts) * value[2]
end

function M.decrease(node)
    local left = M.square_sum(node.left.counts) / node.left.size
    local right = M.square_sum(node.right.counts) / node.right.size
    local parent = M.square_sum(node.counts) / node.size
    return (left + right) - parent
end

return M
