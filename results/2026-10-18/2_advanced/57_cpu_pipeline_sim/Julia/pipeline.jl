const CAUSES = ("control","structural","load_use","raw")
const STAGES = ("IF","ID","EX","MEM","WB")
function simulate(instructions,sources,variant,mispredicted)
    n = length(instructions)
    timings = zeros(Int,n,5)
    records,delays = NamedTuple[],Int[]
    for (i,instruction) in enumerate(instructions)
        execute = instruction.kind=="MUL" ? variant.latency : 1
        if i==1
            fetch,decode,start = 1,2,3
        else
            previous = timings[i-1,:]
            fetch = mispredicted[i-1] ? previous[3]+!id_resolved(instructions[i-1],variant) : previous[2]
            decode = max(fetch+1,previous[3])
            ideal = previous[3]+1
            load_ready,raw_ready = ideal,ideal
            load_producer,raw_producer = 0,0
            for source in sources[i]
                p = source.producer
                p==0 && continue
                ready = ready_cycle(instruction,instructions[p],timings[p,:],variant)
                if instructions[p].kind=="LOAD"
                    if ready>load_ready
                        load_ready,load_producer = ready,p
                    end
                elseif ready>raw_ready
                    raw_ready,raw_producer = ready,p
                end
            end
            bounds = (decode+1,previous[4],load_ready,raw_ready)
            producers = (0,0,load_producer,raw_producer)
            start = ideal
            for cause in 1:4
                if bounds[cause]>start
                    push!(
                        records,
                        (
                            cause=cause,
                            cycles=bounds[cause]-start,
                            responsible=cause<=2 ? i-1 : i,
                            waiting=i,
                            producer=producers[cause]
                        )
                    )
                    start = bounds[cause]
                end
            end
            push!(delays,start-ideal)
        end
        timings[i,:] = [fetch,decode,start,start+execute,start+execute+1]
    end
    if instructions[end].kind=="MUL" && variant.latency>=2
        push!(records,(cause=2,cycles=variant.latency-1,responsible=n,waiting=0,producer=0))
    end
    (timings=timings,records=records,delays=delays,cycles=timings[end,5])
end
