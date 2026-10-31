function discounted_return(rewards,gamma)
    value = 0
    for reward in reverse(rewards)
        value = 10000*reward+fld(gamma*value,100)
    end
    value
end
struct ReturnAverages
    sums::Matrix{Int}
    counts::Matrix{Int}
end
ReturnAverages(count) = ReturnAverages(zeros(Int,count,4),zeros(Int,count,4))
function update!(averages,q,history,gamma)
    seen = Set{Tuple{Int,Int}}()
    first_visits = Bool[]
    for (state,action,_) in history
        push!(first_visits,!((state,action) in seen))
        push!(seen,(state,action))
    end
    value = 0
    for index in reverse(eachindex(history))
        state,action,reward = history[index]
        value = 10000*reward+fld(gamma*value,100)
        if first_visits[index]
            averages.sums[state,action] += value
            averages.counts[state,action] += 1
            q[state,action] = fld(averages.sums[state,action],averages.counts[state,action])
        end
    end
end
