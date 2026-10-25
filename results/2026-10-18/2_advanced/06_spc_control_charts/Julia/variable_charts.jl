module VariableCharts
export Subgroup, Limits, statistics, familylimits, familyseries, outside, realsum
struct Subgroup
    number::Int
    values::Vector{Int}
    total::Int
    squares::Int
    mean::Float64
    range::Int
    sd::Float64
end
struct Limits
    lcl::Float64
    cl::Float64
    ucl::Float64
end
outside(l::Limits,v) = v > l.ucl || v < l.lcl
function realsum(values)
    total = 0.0
    for v in values
        total += v
    end
    total
end
function statistics(values,n)
    groups = Subgroup[]
    for first in 1:n:length(values)
        chosen = values[first:first+n-1]
        t = sum(chosen)
        q = sum(x*x for x in chosen)
        push!(groups,Subgroup(div(first-1,n)+1,chosen,t,q,t/n,maximum(chosen)-minimum(chosen),sqrt((n*q-t*t)/(n*(n-1)))))
    end
    groups
end
function familylimits(family,numbers,groups,values,n,c)
    if family == 3
        chosen = values[numbers]
        mean = sum(chosen)/length(chosen)
        rbar = sum(abs(chosen[j]-chosen[j-1]) for j in 2:length(chosen))/(length(chosen)-1)
        width = 3*rbar/1.128
        return (Limits(mean-width,mean,mean+width),Limits(0.0,rbar,3.267*rbar))
    end
    chosen = groups[numbers]
    mean = sum(g.total for g in chosen)/(length(chosen)*n)
    if family == 1
        spread = sum(g.range for g in chosen)/length(chosen)
        width = c.a2*spread
        return (Limits(mean-width,mean,mean+width),Limits(c.d3*spread,spread,c.d4*spread))
    end
    spread = realsum(g.sd for g in chosen)/length(chosen)
    width = c.a3*spread
    (Limits(mean-width,mean,mean+width),Limits(c.b3*spread,spread,c.b4*spread))
end
function familyseries(family,numbers,groups,values)
    if family == 3
        chosen = values[numbers]
        return ((numbers,Float64.(chosen)),(numbers[2:end],Float64[abs(chosen[j]-chosen[j-1]) for j in 2:length(chosen)]))
    end
    ((numbers,[groups[i].mean for i in numbers]),(numbers,family == 1 ? Float64[groups[i].range for i in numbers] : [groups[i].sd for i in numbers]))
end
end
