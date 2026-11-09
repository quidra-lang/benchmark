mutable struct Minstd
    state::Int64
end
function uniform!(random)
    random.state = 48271*random.state%2147483647
    random.state/2147483647
end
function choose_state(probabilities,random)
    u,cumulative = uniform!(random),0.0
    for (state,probability) in enumerate(probabilities)
        cumulative += probability
        u<cumulative && return state
    end
    length(probabilities)
end
function weighted_sample(topological,parents,cpts,sizes,evidence,random)
    sample,weight = zeros(Int,length(sizes)),1.0
    for v in topological
        row = parent_row(parents[v],sample,sizes)
        if haskey(evidence,v)
            sample[v] = evidence[v]
            weight *= cpts[v][row,evidence[v]]
        else
            sample[v] = choose_state(cpts[v][row,:],random)
        end
    end
    sample,weight
end
