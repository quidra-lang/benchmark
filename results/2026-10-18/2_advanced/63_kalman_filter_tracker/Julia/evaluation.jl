using Printf
function squared_distance(a,b)
    dx,dy = a[1]-b[1],a[2]-b[2]
    dx*dx+dy*dy
end
distance(a,b) = sqrt(squared_distance(a,b))
function ospa(first,second,cutoff)
    isempty(first) && isempty(second) && return 0.0
    (isempty(first) || isempty(second)) && return cutoff
    smaller,larger = length(first)<=length(second) ? (first,second) : (second,first)
    costs = [min(cutoff,distance(a,b))*min(cutoff,distance(a,b)) for a in smaller,b in larger]
    cost = ordered_total(costs[row,column] for (row,column) in minimum_matching(costs))
    sqrt((cost+cutoff*cutoff*(length(larger)-length(smaller)))/length(larger))
end
function continuity(labels)
    covered,groups,swaps,previous,previous_covered,delay = 0,0,0,0,false,nothing
    for (index,label) in enumerate(labels)
        if label==0
            previous_covered = false
            continue
        end
        covered += 1
        isnothing(delay) && (delay=index-1)
        !previous_covered && (groups+=1)
        previous!=0 && label!=previous && (swaps+=1)
        previous,previous_covered = label,true
    end
    (covered=covered,breaks=max(0,groups-1),swaps=swaps,delay=delay)
end
function real_text(value)
    isnothing(value) && return "-"
    text = @sprintf("%.4f",value)
    text=="-0.0000" ? "0.0000" : text
end
