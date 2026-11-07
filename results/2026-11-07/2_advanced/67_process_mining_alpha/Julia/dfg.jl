function directly_follows(log)
    counts = Dict{Tuple{String,String},Int}()
    for (trace,weight) in log,i in 1:length(trace)-1
        pair = (trace[i],trace[i+1])
        counts[pair] = get(counts,pair,0)+weight
    end
    counts
end
count_at(counts,a,b) = get(counts,(a,b),0)
function basic_relation(counts,a,b)
    forward,backward = count_at(counts,a,b)>0,count_at(counts,b,a)>0
    forward && !backward ? "->" : backward && !forward ? "<-" : forward ? "||" : "#"
end
function table_lines(rows,width)
    n = length(rows)
    lines = ["    "*join(lpad(i,width) for i in 1:n)]
    for (i,row) in enumerate(rows)
        push!(lines,lpad(i,4)*join(lpad(value,width) for value in row))
    end
    lines
end
function footprint(activities,relation)
    [ ["ACTIVITY $i $a" for (i,a) in enumerate(activities)];table_lines(
        [[relation(a,b) for b in activities] for a in activities],
        4
    )]
end
