function smoothed_model(template,name,initial,transition,emission,alpha)
    make_model(
        name,
        template.states,
        template.symbols,
        template.missing,
        initial.+alpha,
        transition.+alpha,
        emission.+alpha
    )
end
function baum_welch_step(model,sequences,pseudocount)
    k,m = length(model.states),length(model.symbols)
    initial,transition,emission = zeros(k),zeros(k,k),zeros(k,m)
    for observations in sequences
        result = forward_backward(model,observations)
        for i in 1:k
            initial[i] += result.posterior[1,i]
        end
        for (t,observation) in enumerate(observations),i in 1:k
            observation!=0 && (emission[i,observation]+=result.posterior[t,i])
            if t<length(observations)
                for j in 1:k
                    transition[i,j] += posterior_transition(model,result,t,i,j)
                end
            end
        end
    end
    smoothed_model(model,"BAUM_WELCH",initial,transition,emission,pseudocount)
end
function estimate_by_counting(template,pairs,alpha,name="SUPERVISED")
    k,m = length(template.states),length(template.symbols)
    initial,transition,emission = zeros(k),zeros(k,k),zeros(k,m)
    for (observations,path) in pairs
        initial[path[1]] += 1
        for (t,state) in enumerate(path)
            observations[t]!=0 && (emission[state,observations[t]]+=1)
            t<length(path) && (transition[state,path[t+1]]+=1)
        end
    end
    smoothed_model(template,name,initial,transition,emission,alpha)
end
total_loglik(model,sequences) = ordered_sum(scaled_forward(
    model,
    observations
).loglik for observations in sequences)
