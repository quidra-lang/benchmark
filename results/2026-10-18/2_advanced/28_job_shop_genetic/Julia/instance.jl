function load_instance(path)
    lines = readlines(path)
    job_count,machine_count = parse.(Int,split(lines[1]))
    jobs,operations,errors = NamedTuple[],NamedTuple[],String[]
    for number in 1:job_count
        steps = Tuple{Int,Int}[]
        valid = true
        for (index,token) in enumerate(split(lines[number+1]))
            machine,duration = parse.(Int,split(token,':'))
            reason = !(1 <= machine <= machine_count) ? "unknown machine $machine" : !(1 <= duration <= 99) ? "bad duration $duration" : any(m == machine for (
                m,
                _
            ) in steps) ? "repeated machine $machine" : nothing
            if !isnothing(reason)
                push!(errors,"job $number operation $index: $reason")
                valid = false
                break
            end
            push!(steps,(machine,duration))
        end
        valid || continue
        first_id = length(operations)+1
        work = sum(d for (_,d) in steps)
        head = 0
        ids = Int[]
        for (index,(machine,duration)) in enumerate(steps)
            id = length(operations)+1
            push!(ids,id)
            push!(
                operations,
                (
                    id=id,
                    job=number,
                    index=index,
                    machine=machine,
                    duration=duration,
                    head=head,
                    tail=work-head-duration,
                    job_prev=index == 1 ? 0 : id-1,
                    job_next=index == length(steps) ? 0 : id+1,
                    code="J$number-$index"
                )
            )
            head += duration
        end
        push!(jobs,(number=number,operations=ids,work=work))
    end
    machines = NamedTuple[]
    for m in 1:machine_count
        ids = [op.id for op in operations if op.machine == m]
        load = sum(operations[id].duration for id in ids)
        head = minimum(operations[id].head for id in ids)
        tail = minimum(operations[id].tail for id in ids)
        push!(machines,(number=m,operations=ids,load=load,head=head,tail=tail,bound=head+load+tail))
    end
    (
        machine_count=machine_count,
        jobs=jobs,
        operations=operations,
        errors=errors,
        durations=[op.duration for op in operations],
        job_map=Dict(job.number=>job for job in jobs),
        machines=machines
    )
end
