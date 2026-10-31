function tokenize(data,offset_bits,length_bits)
    window,lookahead = 1<<offset_bits,(1<<length_bits)+2
    prefixes = Dict{NTuple{3,Int},Vector{Int}}()
    tokens = NTuple{3,Int}[]
    position = 1
    while position<=length(data)
        distance,longest = 0,0
        limit = min(lookahead,length(data)-position+1)
        if limit>=3
            key = Tuple(data[position:position+2])
            candidates = get!(prefixes,key,Int[])
            for start in Iterators.reverse(candidates)
                position-start>window && break
                d = position-start
                matched = 3
                while matched<limit && data[position+matched]==data[position+matched-d]
                    matched += 1
                end
                if matched>longest
                    distance,longest = d,matched
                end
                longest==limit && break
            end
        end
        if longest>=3
            push!(tokens,(1,distance,longest))
            consumed = longest
        else
            push!(tokens,(0,data[position],0))
            consumed = 1
        end
        for start in position:min(position+consumed-1,length(data)-2)
            push!(get!(prefixes,Tuple(data[start:start+2]),Int[]),start)
        end
        position += consumed
    end
    tokens
end
function copy_match!(output,distance,matched,original)
    distance>length(output) && throw(DecodeError("bad_offset",length(output)))
    length(output)+matched>original && throw(DecodeError("overrun",length(output)))
    for _ in 1:matched
        push!(output,output[end-distance+1])
    end
end
