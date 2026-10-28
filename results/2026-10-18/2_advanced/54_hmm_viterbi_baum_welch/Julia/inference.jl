maximum_index(values) = argmax(values)
emission_factors(
    model,
    observation
) = observation==0 ? ones(length(model.states)) : model.emission[:,observation]
log_emission_factors(
    model,
    observation
) = observation==0 ? zeros(length(model.states)) : log.(model.emission[:,observation])
function scaled_forward(model,observations)
    k,t_count = length(model.states),length(observations)
    values,emissions,scales = zeros(t_count,k),zeros(t_count,k),zeros(t_count)
    loglik = 0.0
    for t in 1:t_count
        emissions[t,:] = emission_factors(model,observations[t])
        unscaled = zeros(k)
        for j in 1:k
            incoming = t==1 ? model.initial[j] : ordered_sum(values[t-1,i]*model.transition[i,j] for i in 1:k)
            unscaled[j] = incoming*emissions[t,j]
        end
        scales[t] = ordered_sum(unscaled)
        values[t,:] = unscaled./scales[t]
        loglik += log(scales[t])
    end
    (values=values,scales=scales,emissions=emissions,loglik=loglik)
end
function forward_backward(model,observations)
    forward = scaled_forward(model,observations)
    t_count,k = size(forward.values)
    backward = zeros(t_count,k)
    backward[end,:] .= 1.0
    for t in t_count-1:-1:1,i in 1:k
        backward[t,i] = ordered_sum(model.transition[i,j]*forward.emissions[t+1,j]*backward[
            t+1,
            j
        ] for j in 1:k)/forward.scales[t+1]
    end
    (
        forward=forward.values,
        backward=backward,
        scales=forward.scales,
        emissions=forward.emissions,
        posterior=forward.values.*backward,
        loglik=forward.loglik
    )
end
posterior_transition(
    model,
    result,
    t,
    i,
    j
) = result.forward[t,i]*model.transition[i,j]*result.emissions[t+1,j]*result.backward[t+1,j]/result.scales[t+1]
function viterbi(model,observations)
    k,t_count = length(model.states),length(observations)
    transition = log.(model.transition)
    scores = log.(model.initial).+log_emission_factors(model,observations[1])
    previous = zeros(Int,t_count,k)
    for t in 2:t_count
        factors = log_emission_factors(model,observations[t])
        next_scores = zeros(k)
        for j in 1:k
            candidates = [scores[i]+transition[i,j] for i in 1:k]
            i = maximum_index(candidates)
            previous[t,j] = i
            next_scores[j] = candidates[i]+factors[j]
        end
        scores = next_scores
    end
    path = zeros(Int,t_count)
    path[end] = maximum_index(scores)
    logprob = scores[path[end]]
    for t in t_count:-1:2
        path[t-1] = previous[t,path[t]]
    end
    path,logprob
end
function decode(model,observations)
    fb = forward_backward(model,observations)
    path,logprob = viterbi(model,observations)
    posterior = [maximum_index(fb.posterior[t,:]) for t in axes(fb.posterior,1)]
    confidence = [fb.posterior[t,state] for (t,state) in enumerate(posterior)]
    (viterbi=path,viterbi_logprob=logprob,posterior=posterior,confidence=confidence,fb=fb)
end
