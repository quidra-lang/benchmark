function dependencies(instructions)
    last_writer = zeros(Int,32)
    sources = Vector{NamedTuple}[]
    for (i,instruction) in enumerate(instructions)
        current = NamedTuple[]
        for (field,register) in ((1,instruction.rs1),(2,instruction.rs2))
            register>0 && push!(current,(field=field,register=register,producer=last_writer[register+1]))
        end
        push!(sources,current)
        instruction.rd>0 && (last_writer[instruction.rd+1]=i)
    end
    sources
end
id_resolved(
    instruction,
    variant
) = (instruction.kind=="JUMP" && instruction.rs1==-1) || (instruction.kind in (
    "BRANCH",
    "JUMP"
) && variant.stage=="ID")
function ready_cycle(instruction,producer,producer_time,variant)
    variant.forwarding || return producer_time[5]+1
    result = producer.kind=="LOAD" ? producer_time[5] : producer_time[4]
    result+id_resolved(instruction,variant)
end
function forwarding_path(instruction,producer_time,instruction_time,variant)
    (isnothing(producer_time) || !variant.forwarding) && return 1
    resolved = id_resolved(instruction,variant)
    use_cycle = instruction_time[3]-resolved
    producer_time[4]==use_cycle && return 2
    !resolved && producer_time[5]==use_cycle && return 3
    1
end
