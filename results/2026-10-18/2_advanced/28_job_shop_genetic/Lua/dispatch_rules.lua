local M = {}
function M.giffler_thompson(instance, rule, gene_positions)
    local starts, next_index, ready, free = {}, {}, {}, {}
    for _, job in ipairs(instance.jobs) do
        next_index[job.number], ready[job.number] = 1, 0
    end
    for machine = 1, instance.machine_count do
        free[machine] = 0
    end
    local decisions, ties = 0, 0
    for _ = 1, #instance.operations do
        local candidates, cutoff, chosen_machine = {}, 2147483647, nil
        for _, job in ipairs(instance.jobs) do
            local ident = job.operations[next_index[job.number]]
            if ident then
                local operation = instance.operations[ident]
                local earliest = math.max(ready[job.number], free[operation.machine])
                candidates[#candidates + 1] = {operation = operation, earliest = earliest}
                local completion = earliest + operation.duration
                if completion < cutoff or completion == cutoff and operation.machine < chosen_machine then
                    cutoff, chosen_machine = completion, operation.machine
                end
            end
        end
        local chosen, minimum, conflict_count, minimum_count = nil, 2147483647, 0, 0
        for _, candidate in ipairs(candidates) do
            local operation = candidate.operation
            if operation.machine == chosen_machine and candidate.earliest < cutoff then
                conflict_count = conflict_count + 1
                local value
                if rule == "SPT" then
                    value = operation.duration
                elseif rule == "LPT" then
                    value = -operation.duration
                elseif rule == "MWKR" then
                    value = -operation.duration - operation.tail
                elseif rule == "FIFO" then
                    value = ready[operation.job]
                else
                    value = gene_positions[operation.ident]
                end
                if value < minimum then
                    minimum, chosen, minimum_count = value, candidate, 1
                elseif value == minimum then
                    minimum_count = minimum_count + 1
                end
            end
        end
        if conflict_count > 1 then
            decisions = decisions + 1
        end
        if minimum_count > 1 then
            ties = ties + 1
        end
        local operation = chosen.operation
        starts[operation.ident] = chosen.earliest
        ready[operation.job], free[chosen_machine] = chosen.earliest + operation.duration, chosen.earliest + operation.duration
        next_index[operation.job] = next_index[operation.job] + 1
    end
    return starts, decisions, ties
end
return M
