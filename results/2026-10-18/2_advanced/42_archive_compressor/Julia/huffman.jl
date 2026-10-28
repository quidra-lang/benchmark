function tree_lengths(frequencies)
    lengths = zeros(Int,length(frequencies))
    nodes = [(weight=f,minimum=s,symbols=[s]) for (s,f) in enumerate(frequencies) if f>0]
    isempty(nodes) && return lengths
    if length(nodes)==1
        lengths[nodes[1].minimum] = 1
        return lengths
    end
    while length(nodes)>1
        sort!(nodes;by=n->(n.weight,n.minimum))
        a,b = popfirst!(nodes),popfirst!(nodes)
        symbols = vcat(a.symbols,b.symbols)
        lengths[symbols] .+= 1
        push!(nodes,(weight=a.weight+b.weight,minimum=min(a.minimum,b.minimum),symbols=symbols))
    end
    lengths
end
function limited_lengths(frequencies,maximum_length)
    weights = copy(frequencies)
    halvings = 0
    while true
        lengths = tree_lengths(weights)
        maximum(lengths)<=maximum_length && return lengths,halvings
        weights = fld.(weights.+1,2)
        halvings += 1
    end
end
function canonical_codes(lengths)
    ordered = sort([s for s in eachindex(lengths) if lengths[s]>0];by=s->(lengths[s],s))
    codes = zeros(Int,length(lengths))
    code,previous = 0,0
    for (i,s) in enumerate(ordered)
        i>1 && (code=(code+1)<<(lengths[s]-previous))
        codes[s] = code
        previous = lengths[s]
    end
    codes
end
