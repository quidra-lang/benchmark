local M = {}
function M.gene_operations(instance, chromosome)
    local counts, operations = {}, {}
    for _, gene in ipairs(chromosome) do
        counts[gene] = (counts[gene] or 0) + 1
        operations[#operations + 1] = instance.job_map[gene].operations[counts[gene]]
    end
    return operations
end
function M.decode(instance, chromosome)
    local starts, ready, free = {}, {}, {}
    for machine = 1, instance.machine_count do
        free[machine] = 0
    end
    for _, job in ipairs(instance.jobs) do
        ready[job.number] = 0
    end
    for _, ident in ipairs(M.gene_operations(instance, chromosome)) do
        local operation = instance.operations[ident]
        local start = math.max(ready[operation.job], free[operation.machine])
        starts[ident] = start
        ready[operation.job], free[operation.machine] = start + operation.duration, start + operation.duration
    end
    return starts
end
function M.tournament(rng, values, size)
    local best
    for _ = 1, size do
        local index = rng:below(#values) + 1
        if not best or values[index] < values[best] or values[index] == values[best] and index < best then
            best = index
        end
    end
    return best
end
local function preserve(keeper, donor, kept)
    local fillers, child, position = {}, {}, 1
    for _, gene in ipairs(donor) do
        if not kept[gene] then
            fillers[#fillers + 1] = gene
        end
    end
    for i, gene in ipairs(keeper) do
        if kept[gene] then
            child[i] = gene
        else
            child[i], position = fillers[position], position + 1
        end
    end
    return child
end
function M.crossover(rng, first, second, job_numbers)
    local kept = {}
    for _, job in ipairs(job_numbers) do
        if rng:below(2) == 0 then
            kept[job] = true
        end
    end
    return preserve(first, second, kept), preserve(second, first, kept)
end
function M.swap_mutation(rng, chromosome)
    local first, second = rng:below(#chromosome) + 1, rng:below(#chromosome) + 1
    chromosome[first], chromosome[second] = chromosome[second], chromosome[first]
end
function M.insert_mutation(rng, chromosome)
    local source, target = rng:below(#chromosome) + 1, rng:below(#chromosome) + 1
    table.insert(chromosome, target, table.remove(chromosome, source))
end
return M
