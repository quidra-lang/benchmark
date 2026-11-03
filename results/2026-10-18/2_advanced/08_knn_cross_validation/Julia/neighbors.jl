module Neighbors
using ..Dataset: Row
export Neighbor, Prediction, distance, neighbororder, prediction
struct Neighbor
    row::Row
    distance::Float64
end
struct Prediction
    label::Int
    share::Float64
    runner::Int
    runner_share::Float64
    estimate::Float64
    nearest::Vector{Neighbor}
end
function distance(a,b,metric)
    total,dot,aa,bb = 0.0,0.0,0.0,0.0
    for (x,y) in zip(a,b)
        if metric == :cosine
            dot += x*y
            aa += x*x
            bb += y*y
        else
            delta = x-y
            if metric == :squared_euclidean
                total += delta*delta
            elseif metric == :manhattan
                total += abs(delta)
            else
                total = max(total,abs(delta))
            end
        end
    end
    if metric == :cosine
        na,nb = sqrt(aa),sqrt(bb)
        return na == 0 || nb == 0 ? 1.0 : 1-dot/(na*nb)
    end
    total
end
function neighbororder(query,references,vectors,metric)
    sort!([Neighbor(row,distance(query,vector,metric)) for (row,vector) in zip(references,vectors)],by=n -> (n.distance,n.row.id))
end
function prediction(order,k,weighting,classes)
    nearest = order[1:min(k,length(order))]
    counts,distances,weights = zeros(Int,classes),zeros(classes),zeros(classes)
    totalweight,total,weighted = 0.0,0.0,0.0
    for neighbor in nearest
        label,gap = neighbor.row.label,neighbor.distance
        weight = 1/(gap+0.000000001)
        counts[label] += 1
        distances[label] += gap
        weights[label] += weight
        totalweight += weight
        total += neighbor.row.target
        weighted += weight*neighbor.row.target
    end
    labels = findall(>(0),counts)
    sort!(labels,by=c -> (weighting == :uniform ? -Float64(counts[c]) : -weights[c],distances[c],c))
    share(c) = weighting == :uniform ? counts[c]/length(nearest) : weights[c]/totalweight
    runner = length(labels) > 1 ? labels[2] : 0
    estimate = weighting == :uniform ? total/length(nearest) : weighted/totalweight
    Prediction(labels[1],share(labels[1]),runner,runner == 0 ? 0.0 : share(runner),estimate,nearest)
end
end
