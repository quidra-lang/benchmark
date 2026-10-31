function lower_bounds(sequence,reverse_index)
    lower,upper,mismatches,bounds = 0,reverse_index.size,0,Int[]
    for base in sequence
        lower,upper = extend_interval(reverse_index,lower,upper,base)
        if lower>=upper
            mismatches += 1
            lower,upper = 0,reverse_index.size
        end
        push!(bounds,mismatches)
    end
    bounds
end
function backtrack(sequence,maximum,forward_index,reverse_index)
    bounds = lower_bounds(sequence,reverse_index)
    stack = [(length(sequence)-1,maximum,0,forward_index.size)]
    nodes,leaves = 0,NTuple{3,Int}[]
    while !isempty(stack)
        position,remaining,lower,upper = pop!(stack)
        nodes += 1
        remaining<(position>=0 ? bounds[position+1] : 0) && continue
        if position== -1
            push!(leaves,(lower,upper,maximum-remaining))
            continue
        end
        for base in "TGCA"
            first,last = extend_interval(forward_index,lower,upper,base)
            first>=last && continue
            mismatch = base!=sequence[position+1]
            (!mismatch || remaining>=1) && push!(stack,(position-1,remaining-Int(mismatch),first,last))
        end
    end
    (nodes=nodes,leaves=leaves,positions=sum((upper-lower for (lower,upper,_) in leaves);init=0))
end
