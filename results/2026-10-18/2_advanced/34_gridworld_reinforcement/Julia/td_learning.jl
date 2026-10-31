choose!(generator,row,epsilon) = draw!(generator)%1000 < epsilon ? draw!(generator)%4+1 : first_max(row)
td_target(reward,terminal,next_value,gamma) = 10000*reward+(terminal ? 0 : fld(gamma*next_value,100))
expected_value(row,epsilon) = fld(epsilon*sum(row)+4*(1000-epsilon)*maximum(row),4000)
function td_update!(q,state,action,target,alpha)
    q[state,action] += fld(alpha*(target-q[state,action]),100)
end
mutable struct DynaModel
    outcomes::Matrix{Union{Nothing,Tuple{Int,Int}}}
    pairs::Vector{Tuple{Int,Int}}
end
DynaModel(count) = DynaModel(
    fill!(Matrix{Union{Nothing,Tuple{Int,Int}}}(undef,count,4),nothing),
    Tuple{Int,Int}[]
)
function record!(model,state,action,reward,next_state)
    isnothing(model.outcomes[state,action]) && push!(model.pairs,(state,action))
    model.outcomes[state,action] = (reward,next_state)
end
function plan!(model,generator,q,gamma,alpha,count)
    for _ in 1:count
        state,action = model.pairs[draw!(generator)%length(model.pairs)+1]
        reward,next_state = model.outcomes[state,action]
        next_value = next_state == 0 ? 0 : maximum(@view q[next_state,:])
        td_update!(q,state,action,td_target(reward,next_state == 0,next_value,gamma),alpha)
    end
end
