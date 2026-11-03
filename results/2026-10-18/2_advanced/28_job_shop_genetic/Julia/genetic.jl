function gene_operations(instance,chromosome)
    counts = Dict(job.number=>0 for job in instance.jobs)
    ids = Int[]
    for gene in chromosome
        counts[gene] += 1
        push!(ids,instance.job_map[gene].operations[counts[gene]])
    end
    ids
end
function decode(instance,chromosome)
    starts = zeros(Int,length(instance.operations))
    ready = Dict(job.number=>0 for job in instance.jobs)
    free = zeros(Int,instance.machine_count)
    for id in gene_operations(instance,chromosome)
        op = instance.operations[id]
        starts[id] = max(ready[op.job],free[op.machine])
        ready[op.job] = free[op.machine] = starts[id]+op.duration
    end
    starts
end
function tournament!(rng,values,size)
    picks = [below!(rng,length(values))+1 for _ in 1:size]
    picks[argmin([(values[i],i) for i in picks])]
end
function crossover!(rng,first,second,jobs)
    kept = Set(job for job in jobs if below!(rng,2) == 0)
    function preserve(keeper,donor)
        fillers = [gene for gene in donor if !(gene in kept)]
        index = 0
        [gene in kept ? gene : fillers[index+=1] for gene in keeper]
    end
    preserve(first,second),preserve(second,first)
end
function swap_mutation!(rng,chromosome)
    a,b = below!(rng,length(chromosome))+1,below!(rng,length(chromosome))+1
    chromosome[a],chromosome[b] = chromosome[b],chromosome[a]
end
function insert_mutation!(rng,chromosome)
    a,b = below!(rng,length(chromosome))+1,below!(rng,length(chromosome))+1
    gene = chromosome[a]
    deleteat!(chromosome,a)
    insert!(chromosome,b,gene)
end
