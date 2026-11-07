local M = {}
function M.lower_bounds(sequence, reverse)
    local lower, upper, mismatches, bounds = 0, reverse.size, 0, {[-1] = 0}
    for position = 0, #sequence - 1 do
        lower, upper = reverse:extend(lower, upper, sequence:sub(position + 1, position + 1))
        if lower >= upper then mismatches = mismatches + 1; lower, upper = 0, reverse.size end
        bounds[position] = mismatches
    end
    return bounds
end
function M.backtrack(sequence, maximum, forward, reverse)
    local bounds = M.lower_bounds(sequence, reverse)
    local stack, nodes, leaves, hits = {{#sequence - 1, maximum, 0, forward.size}}, 0, {}, 0
    while #stack > 0 do
        local state = table.remove(stack)
        local position, remaining, lower, upper = table.unpack(state)
        nodes = nodes + 1
        if remaining >= bounds[position] then
            if position == -1 then
                leaves[#leaves + 1] = {lower, upper, maximum - remaining}
                hits = hits + upper - lower
            else
                for index = 1, 4 do
                    local base = ('TGCA'):sub(index, index)
                    local first, last = forward:extend(lower, upper, base)
                    local mismatch = base ~= sequence:sub(position + 1, position + 1)
                    if first < last and (not mismatch or remaining >= 1) then
                        stack[#stack + 1] = {position - 1, remaining - (mismatch and 1 or 0), first, last}
                    end
                end
            end
        end
    end
    return nodes, leaves, hits
end
return M
