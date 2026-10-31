function ordered_sum(values)
    total = 0.0
    for value in values
        total += value
    end
    total
end
struct Stump
    feature::Int
    thresholds::Vector{Float64}
    values::Vector{Float64}
end
stump_output(stump,values) = stump.values[count(t->values[stump.feature]>t,stump.thresholds)+1]
function search_space(rows)
    orders,groups,thresholds = Vector{Int}[],Vector{Vector{Int}}[],Vector{Float64}[]
    for j in eachindex(rows[1].x)
        order = sort(collect(eachindex(rows));by=i->(rows[i].x[j],i))
        batches = Vector{Int}[]
        distinct = Float64[]
        for i in order
            value = rows[i].x[j]
            if isempty(distinct) || value!=distinct[end]
                push!(distinct,value)
                push!(batches,Int[])
            end
            push!(batches[end],i)
        end
        cuts = vcat([distinct[1]-1],[(distinct[i]+distinct[i+1])/2 for i in 1:length(distinct)-1])
        push!(orders,order)
        push!(groups,batches)
        push!(thresholds,cuts)
    end
    (rows=rows,orders=orders,groups=groups,thresholds=thresholds)
end
function left_cumulative(groups,values)
    result = [0.0]
    total = 0.0
    for group in groups[1:end-1]
        for i in group
            total += values[i]
        end
        push!(result,total)
    end
    result
end
function choose(candidates)
    minimum_value = minimum(c[1] for c in candidates)
    candidates[findfirst(c->c[1]<=minimum_value+1e-9,candidates)]
end
function discrete_search(space,labels,weights)
    positive = [y==1 ? w : 0.0 for (y,w) in zip(labels,weights)]
    negative = [y==-1 ? w : 0.0 for (y,w) in zip(labels,weights)]
    wp,wn = ordered_sum(positive),ordered_sum(negative)
    candidates = Tuple{Float64,Int,Float64,Int}[]
    for j in eachindex(space.thresholds)
        lp,ln = left_cumulative(space.groups[j],positive),left_cumulative(space.groups[j],negative)
        for (k,threshold) in enumerate(space.thresholds[j])
            push!(candidates,(lp[k]+(wn-ln[k]),j,threshold,1),(ln[k]+(wp-lp[k]),j,threshold,-1))
        end
    end
    choose(candidates)
end
function regression_search(space,targets,weights)
    w = ordered_sum(weights)
    products = weights.*targets
    s = ordered_sum(products)
    q = ordered_sum(weights[i]*targets[i]*targets[i] for i in eachindex(weights))
    candidates = Tuple{Float64,Int,Float64,Float64,Float64}[]
    for j in eachindex(space.thresholds)
        wl,sl = left_cumulative(space.groups[j],weights),left_cumulative(space.groups[j],products)
        for (k,threshold) in enumerate(space.thresholds[j])
            wr,sr = w-wl[k],s-sl[k]
            right = sr/wr
            left = k==1 ? 0.0 : sl[k]/wl[k]
            gain = k==1 ? sr*sr/wr : sl[k]*sl[k]/wl[k]+sr*sr/wr
            push!(candidates,(q-gain,j,threshold,left,right))
        end
    end
    error,j,threshold,left,right = choose(candidates)
    Stump(j,[threshold],[left,right]),error
end
function multiclass_search(space,labels,weights,classes)
    total_weight = ordered_sum(weights)
    totals = [ordered_sum(weights[i] for i in eachindex(labels) if labels[i]==c) for c in 1:classes]
    candidates = Tuple{Float64,Int,Float64,Int,Int}[]
    for j in eachindex(space.thresholds)
        left = zeros(classes)
        for (k,threshold) in enumerate(space.thresholds[j])
            if k>1
                for i in space.groups[j][k-1]
                    left[labels[i]] += weights[i]
                end
            end
            right = totals.-left
            a,b = argmax(left),argmax(right)
            push!(candidates,(total_weight-(left[a]+right[b]),j,threshold,a,b))
        end
    end
    error,j,threshold,left,right = choose(candidates)
    Stump(j,[threshold],Float64[left,right]),error
end
function real_geometry(space,bins)
    n = length(space.rows)
    cuts,assignments = Vector{Float64}[],Vector{Int}[]
    for (j,order) in enumerate(space.orders)
        values = [space.rows[i].x[j] for i in order]
        feature_cuts = [(values[fld(b*n,bins)]+values[fld(b*n,bins)+1])/2 for b in 1:bins-1]
        push!(cuts,feature_cuts)
        push!(assignments,[count(cut->row.x[j]>cut,feature_cuts)+1 for row in space.rows])
    end
    cuts,assignments
end
function real_search(assignments,labels,weights,bins)
    candidates = []
    for (j,memberships) in enumerate(assignments)
        positive,negative = zeros(bins),zeros(bins)
        for (label,weight,bin) in zip(labels,weights,memberships)
            (label==1 ? positive : negative)[bin] += weight
        end
        normalizer = 2ordered_sum(sqrt(positive[b]*negative[b]) for b in 1:bins)
        push!(candidates,(normalizer,j,positive,negative))
    end
    choose(candidates)
end
