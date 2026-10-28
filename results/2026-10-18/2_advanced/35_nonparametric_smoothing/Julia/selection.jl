function ordered_sum(values)
    total = 0.0
    for value in values
        total += value
    end
    total
end
function cross_validation_score(observed,predicted)
    any(isnothing,predicted) && return nothing
    ordered_sum((y-fit)*(y-fit) for (y,fit) in zip(observed,predicted))/length(observed)
end
function generalized_score(observed,fitted,edf)
    rss = ordered_sum((y-fit)*(y-fit) for (y,fit) in zip(observed,fitted))
    factor = 1-edf/length(observed)
    rss/length(observed)/(factor*factor)
end
function choose_candidate(candidates)
    eligible = [i for i in eachindex(candidates) if !isnothing(candidates[i].score)]
    first(sort(eligible,by=i->(candidates[i].score,i)))
end
