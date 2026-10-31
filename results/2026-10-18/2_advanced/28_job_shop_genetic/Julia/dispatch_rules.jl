function giffler_thompson(instance,rule,positions=nothing)
    starts = zeros(Int,length(instance.operations))
    next_index = Dict(job.number=>1 for job in instance.jobs)
    ready = Dict(job.number=>0 for job in instance.jobs)
    free = zeros(Int,instance.machine_count)
    decisions,ties = 0,0
    for _ in eachindex(starts)
        candidates = Tuple{Int,Int}[]
        for job in instance.jobs
            if next_index[job.number] <= length(job.operations)
                id = job.operations[next_index[job.number]]
                op = instance.operations[id]
                push!(candidates,(id,max(ready[op.job],free[op.machine])))
            end
        end
        cutoff = minimum(t+instance.operations[id].duration for (id,t) in candidates)
        machine = minimum(instance.operations[id].machine for (
            id,
            t
        ) in candidates if t+instance.operations[id].duration == cutoff)
        conflict = [(id,t) for (
            id,
            t
        ) in candidates if instance.operations[id].machine == machine && t < cutoff]
        priority(id) = (op=instance.operations[id]; rule == "SPT" ? op.duration : rule == "LPT" ? -op.duration : rule == "MWKR" ? -op.duration-op.tail : rule == "FIFO" ? ready[op.job] : positions[id])
        values = [priority(id) for (id,_) in conflict]
        lowest = minimum(values)
        decisions += length(conflict) > 1
        ties += count(==(lowest),values) > 1
        id,start = conflict[findfirst(==(lowest),values)]
        op = instance.operations[id]
        starts[id] = start
        ready[op.job] = free[machine] = start+op.duration
        next_index[op.job] += 1
    end
    starts,decisions,ties
end
