mutable struct MINSTD
    state::Int
end
function uniform!(generator)
    generator.state = (48271generator.state)%2147483647
    generator.state/2147483647
end
function draw(weights,generator)
    total = ordered_sum(weights)
    threshold = uniform!(generator)*total
    cumulative = 0.0
    for (i,weight) in enumerate(weights)
        cumulative += weight
        threshold<cumulative && return i
    end
    length(weights)
end
function synthetic_sequence(model,t_count,generator)
    states,observations = Int[],Int[]
    for t in 1:t_count
        weights = t==1 ? model.initial : model.transition[states[end],:]
        state = draw(weights,generator)
        symbol = draw(model.emission[state,:],generator)
        push!(states,state)
        push!(observations,symbol)
    end
    states,observations
end
function posterior_path(model,forward,generator)
    t_count,k = size(forward)
    path = zeros(Int,t_count)
    path[end] = draw(forward[end,:],generator)
    for t in t_count-1:-1:1
        weights = [forward[t,i]*model.transition[i,path[t+1]] for i in 1:k]
        path[t] = draw(weights,generator)
    end
    path
end
