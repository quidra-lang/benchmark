root(p,q) = (isqrt(fld(40000p,q))+1)÷2
function consecutive_ranges(indices)
    ranges = Tuple{Int,Int}[]
    for index in indices
        if !isempty(ranges) && index == ranges[end][2]+1
            ranges[end] = (ranges[end][1],index)
        else
            push!(ranges,(index,index))
        end
    end
    ranges
end
function rr_statistics(values)
    isempty(values) && return (mean_rr=nothing,mean_hr=nothing)
    (mean_rr=rdiv(100sum(values),length(values)),mean_hr=rdiv(6000000length(values),sum(values)))
end
function nn_statistics(intervals,pairs)
    e,k = length(intervals),length(pairs)
    differences = [b-a for (a,b) in pairs]
    totals = [a+b for (a,b) in pairs]
    variance = k*sum(abs2,differences)-sum(differences)^2
    histogram = Dict{Int,Int}()
    for value in intervals
        bin = fld(16value,125)
        histogram[bin] = get(histogram,bin,0)+1
    end
    max_count = isempty(histogram) ? 0 : maximum(values(histogram))
    nn50 = count(d->abs(d)>50,differences)
    (e=e,k=k,mean_nn=e>0 ? rdiv(100sum(intervals),e) : nothing,
     sdnn=e>=2 ? root(e*sum(abs2,intervals)-sum(intervals)^2,e*(e-1)) : nothing,
     rmssd=k>0 ? root(sum(abs2,differences),k) : nothing,
     sdsd=k>=2 ? root(variance,k*(k-1)) : nothing,nn50=nn50,
     pnn50=k>0 ? rdiv(10000nn50,k) : nothing,
     sd1=k>=2 ? root(variance,2k*(k-1)) : nothing,
     sd2=k>=2 ? root(k*sum(abs2,totals)-sum(totals)^2,2k*(k-1)) : nothing,
     histogram=histogram,max_count=max_count,
     triangular_index=e>0 ? rdiv(100e,max_count) : nothing)
end
