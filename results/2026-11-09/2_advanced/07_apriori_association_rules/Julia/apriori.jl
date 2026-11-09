module Apriori
using ..Baskets
export candidates, countsupports
function candidates(previous,k,taxonomy)
    ordered = sort!(collect(keys(previous)),lt=setless)
    known = Set(ordered)
    joined,excluded,pruned = 0,0,0
    result = UInt128[]
    for i in eachindex(ordered)
        a = ordered[i]
        prefix = a ⊻ bit(128-leading_zeros(a))
        for j in i+1:length(ordered)
            b = ordered[j]
            (b ⊻ bit(128-leading_zeros(b))) != prefix && break
            joined += 1
            candidate = a | b
            if k == 2 && any(pair -> hasitems(candidate,pair),taxonomy)
                excluded += 1
            elseif any(code -> (candidate ⊻ bit(code)) ∉ known,members(candidate))
                pruned += 1
            else
                push!(result,candidate)
            end
        end
    end
    (joined=joined,excluded=excluded,pruned=pruned,masks=result)
end
function countsupports(baskets,candidates)
    supports = Dict(mask => 0 for mask in candidates)
    for basket in baskets, mask in candidates
        hasitems(basket,mask) && (supports[mask] += 1)
    end
    supports
end
end
