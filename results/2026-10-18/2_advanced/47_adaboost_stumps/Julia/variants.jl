function update_weights(rows,weights,stump)
    updated = [weight*exp(-row.label*stump_output(stump,row.x)) for (row,weight) in zip(rows,weights)]
    updated./ordered_sum(updated)
end
function train_real(rows,max_rounds,bins,smoothing,convergence)
    space = search_space(rows)
    cuts,assignments = real_geometry(space,bins)
    labels = [row.label for row in rows]
    weights = fill(1/length(rows),length(rows))
    rounds = NamedTuple[]
    bound = 1.0
    stop = "completed"
    for _ in 1:max_rounds
        normalizer,j,positive,negative = real_search(assignments,labels,weights,bins)
        if normalizer>=1-convergence
            stop = "converged"
            break
        end
        values = [0.5*log((p+smoothing)/(n+smoothing)) for (p,n) in zip(positive,negative)]
        stump = Stump(j,cuts[j],values)
        bound *= normalizer
        push!(rounds,round_record(stump;weights=weights,z=normalizer,bound=bound))
        weights = update_weights(rows,weights,stump)
    end
    (rounds=rounds,stop=stop,cuts=cuts)
end
function train_gentle(rows,max_rounds)
    space = search_space(rows)
    targets = [row.label for row in rows]
    weights = fill(1/length(rows),length(rows))
    rounds = NamedTuple[]
    for _ in 1:max_rounds
        stump,error = regression_search(space,targets,weights)
        push!(rounds,round_record(stump;weights=weights,error=error))
        weights = update_weights(rows,weights,stump)
    end
    (rounds=rounds,stop="completed",cuts=nothing)
end
function train_logit(rows,max_rounds,clip_limit)
    space = search_space(rows)
    targets = [row.label==1 ? 1.0 : 0.0 for row in rows]
    scores,probabilities = zeros(length(rows)),fill(0.5,length(rows))
    rounds = NamedTuple[]
    for _ in 1:max_rounds
        q = probabilities.*(1 .- probabilities)
        responses = clamp.((targets.-probabilities)./q,-clip_limit,clip_limit)
        weights = q./ordered_sum(q)
        fitted,error = regression_search(space,responses,weights)
        stump = Stump(fitted.feature,fitted.thresholds,fitted.values./2)
        for (i,row) in enumerate(rows)
            scores[i] += stump_output(stump,row.x)
            probabilities[i] = 1/(1+exp(-2scores[i]))
        end
        loss = ordered_sum(log(1+exp(-2row.label*score)) for (row,score) in zip(rows,scores))/length(rows)
        push!(rounds,round_record(stump;weights=weights,error=error,loss=loss))
    end
    (rounds=rounds,stop="completed",cuts=nothing)
end
