function ordered_total(items)
    result = 0.0
    for item in items
        result += item
    end
    result
end
function parent_row(parents,assignment,sizes)
    row = 0
    for p in parents
        row = row*sizes[p]+assignment[p]-1
    end
    row+1
end
function count_samples(v,parents,samples,sizes)
    rows = prod((sizes[p] for p in parents);init=1)
    counts = zeros(Int,rows,sizes[v])
    for sample in samples
        counts[parent_row(parents,sample,sizes),sample[v]] += 1
    end
    counts
end
function learn_cpt(counts,alpha)
    cpt = zeros(size(counts))
    for r in axes(counts,1)
        denominator = ordered_total(counts[r,s]+alpha for s in axes(counts,2))
        for s in axes(counts,2)
            cpt[r,s] = (counts[r,s]+alpha)/denominator
        end
    end
    cpt
end
function log_likelihood(counts,cpt)
    result = 0.0
    for r in axes(counts,1),s in axes(counts,2)
        counts[r,s]>0 && (result+=counts[r,s]*log(cpt[r,s]))
    end
    result
end
parameter_count(counts) = size(counts,1)*(size(counts,2)-1)
function family_score(v,parents,samples,sizes,alpha)
    counts = count_samples(v,sort(collect(parents)),samples,sizes)
    log_likelihood(counts,learn_cpt(counts,alpha))-parameter_count(counts)*log(length(samples))/2
end
