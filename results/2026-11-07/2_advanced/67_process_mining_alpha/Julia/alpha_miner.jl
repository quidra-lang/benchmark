function extend_pair(pair,activity,side,relation)
    first,second = pair
    group = side==1 ? first : second
    (activity in group || relation(activity,activity)!="#") && return nothing
    any(other->relation(activity,other)!="#",group) && return nothing
    if side==1
        any(other->relation(activity,other)!="->",second) && return nothing
        (Tuple(sort!([collect(first);activity])),second)
    else
        any(other->relation(other,activity)!="->",first) && return nothing
        (first,Tuple(sort!([collect(second);activity])))
    end
end
pair_order(pair) = pair
function triangle_counts(log)
    counts = Dict{Tuple{String,String},Int}()
    for (trace,weight) in log,i in 1:length(trace)-2
        a,b,c = trace[i:i+2]
        a==c && a!=b && (counts[(a,b)]=get(counts,(a,b),0)+weight)
    end
    counts
end
function plus_relation(counts,triangles,a,b)
    forward,backward = count_at(counts,a,b)>0,count_at(counts,b,a)>0
    loop = a!=b && count_at(triangles,a,b)>0 && count_at(triangles,b,a)>0
    forward && (!backward || loop) ? "->" : backward && (!forward || loop) ? "<-" : forward && backward ? "||" : "#"
end
