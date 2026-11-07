round_record(
    stump;weights=Float64[],
    error=nothing,
    alpha=nothing,
    polarity=nothing,
    z=nothing,
    bound=nothing,
    loss=nothing
) =
    (stump=stump,weights=copy(weights),error=error,alpha=alpha,polarity=polarity,z=z,bound=bound,loss=loss)
function train_discrete(rows,max_rounds;weights=nothing,shrinkage=1.0,space=nothing)
    isnothing(space) && (space=search_space(rows))
    labels = [row.label for row in rows]
    weights = isnothing(weights) ? fill(1/length(rows),length(rows)) : copy(weights)
    rounds = NamedTuple[]
    bound = 1.0
    stop = "completed"
    for _ in 1:max_rounds
        error,j,threshold,polarity = discrete_search(space,labels,weights)
        if error>=0.5
            stop = "weak"
            break
        end
        alpha = error<=1e-10 ? 1.0 : shrinkage*(0.5*log((1-error)/error))
        stump = Stump(j,[threshold],[-polarity*alpha,polarity*alpha])
        before = copy(weights)
        for (i,row) in enumerate(rows)
            decision = row.x[j]>threshold ? polarity : -polarity
            factor = decision==row.label ? exp(-alpha) : exp(alpha)
            weights[i] = weights[i]==0 ? 0.0 : weights[i]*factor
        end
        normalizer = ordered_sum(weights)
        weights ./= normalizer
        bound *= normalizer
        push!(
            rounds,
            round_record(
                stump;weights=before,
                error=error,
                alpha=alpha,
                polarity=polarity,
                z=normalizer,
                bound=bound
            )
        )
        if error<=1e-10
            stop = "perfect"
            break
        end
    end
    (rounds=rounds,stop=stop,cuts=nothing)
end
function train_samme(rows,max_rounds,classes)
    space = search_space(rows)
    labels = [row.label for row in rows]
    weights = fill(1/length(rows),length(rows))
    rounds = NamedTuple[]
    stop = "completed"
    for _ in 1:max_rounds
        stump,error = multiclass_search(space,labels,weights,classes)
        if error>=(classes-1)/classes
            stop = "weak"
            break
        end
        alpha = error<=1e-10 ? 1.0 : log((1-error)/error)+log(classes-1)
        for (i,row) in enumerate(rows)
            stump_output(stump,row.x)!=row.label && (weights[i]*=exp(alpha))
        end
        weights ./= ordered_sum(weights)
        push!(rounds,round_record(stump;error=error,alpha=alpha))
        if error<=1e-10
            stop = "perfect"
            break
        end
    end
    (rounds=rounds,stop=stop,cuts=nothing)
end
