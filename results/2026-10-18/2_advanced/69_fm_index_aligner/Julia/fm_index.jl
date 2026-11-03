struct FMIndex
    size::Int
    bwt::Vector{Char}
    interval::Int
    c::Dict{Char,Int}
    checkpoints::Vector{Vector{Int}}
    samples::Dict{Int,Int}
end
function FMIndex(text,suffixes,interval,sample_interval=0)
    n = length(text)
    bwt = [text[position>0 ? position : n] for position in suffixes]
    c,offset = Dict{Char,Int}(),0
    for symbol in SYMBOLS
        c[symbol] = offset
        offset += count(==(symbol),text)
    end
    counts = zeros(Int,length(SYMBOLS))
    checkpoints = [copy(counts)]
    for (position,symbol) in enumerate(bwt)
        counts[SYMBOL_NUMBER[symbol]+1] += 1
        position%interval==0 && push!(checkpoints,copy(counts))
    end
    samples = Dict{Int,Int}()
    if sample_interval>0
        for (i,position) in enumerate(suffixes)
            position%sample_interval==0 && (samples[i-1]=position)
        end
    end
    FMIndex(n,bwt,interval,c,checkpoints,samples)
end
function occurrence(index,symbol,position)
    checkpoint = position÷index.interval
    start = checkpoint*index.interval
    index.checkpoints[checkpoint+1][SYMBOL_NUMBER[symbol]+1]+count(==(symbol),index.bwt[start+1:position])
end
function lf(index,row)
    symbol = index.bwt[row+1]
    index.c[symbol]+occurrence(index,symbol,row)
end
function extend_interval(index,lower,upper,base)
    base=='N' && return (0,0)
    index.c[base]+occurrence(index,base,lower),index.c[base]+occurrence(index,base,upper)
end
function locate(index,row)
    steps = 0
    while !haskey(index.samples,row)
        row = lf(index,row)
        steps += 1
    end
    index.samples[row]+steps,steps
end
function inverse_bwt(index)
    result,row = fill('\$',index.size),0
    for position in index.size-2:-1:0
        result[position+1] = index.bwt[row+1]
        row = lf(index,row)
    end
    join(result)
end
function backward_search(index,sequence)
    lower,upper = 0,index.size
    for base in reverse(sequence)
        lower,upper = extend_interval(index,lower,upper,base)
        lower>=upper && break
    end
    lower,upper
end
