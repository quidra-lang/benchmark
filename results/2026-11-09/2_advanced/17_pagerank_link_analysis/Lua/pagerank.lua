local M = {}

function M.run(in_edges, teleport, damping, iterations, tolerance)
    local out_weight, selected, values, changes = {}, {}, {}, {}
    for i = 1, #in_edges do out_weight[i], selected[i] = 0, false end
    for _, edges in ipairs(in_edges) do for _, edge in ipairs(edges) do out_weight[edge[1]] = out_weight[edge[1]] + edge[2] end end
    for _, node in ipairs(teleport) do selected[node] = true end
    for i = 1, #in_edges do values[i] = selected[i] and 1 / #teleport or 0.0 end
    local converged
    for step = 1, iterations do
        local dangling = 0.0
        for i, weight in ipairs(out_weight) do if weight == 0 then dangling = dangling + values[i] end end
        local base = ((1 - damping) + damping * dangling) / #teleport
        local updated, change = {}, 0.0
        for node, edges in ipairs(in_edges) do
            local inflow = 0.0
            for _, edge in ipairs(edges) do inflow = inflow + values[edge[1]] * edge[2] / out_weight[edge[1]] end
            updated[node] = damping * inflow + (selected[node] and base or 0.0)
        end
        for i = 1, #values do change = change + math.abs(updated[i] - values[i]) end
        changes[step], values = change, updated
        if not converged and change < tolerance then converged = step end
    end
    return {values = values, changes = changes, converged = converged}
end

return M
