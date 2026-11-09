function rk4_step(rates,state,multiplier)
    h = 0.25
    half,sixth = h/2,h/6
    k1 = rates(state,multiplier)
    k2 = rates([a+half*p for (a,p) in zip(state,k1)],multiplier)
    k3 = rates([a+half*q for (a,q) in zip(state,k2)],multiplier)
    k4 = rates([a+h*r for (a,r) in zip(state,k3)],multiplier)
    [a+sixth*(((p+2q)+2r)+s) for (a,p,q,r,s) in zip(state,k1,k2,k3,k4)]
end
function simulate(rates,initial,multipliers,inflows)
    state = Float64.(initial)
    daily = Vector{Float64}[]
    for multiplier in multipliers
        state[inflows] .= 0.0
        for _ in 1:4
            state = rk4_step(rates,state,multiplier)
        end
        push!(daily,copy(state))
    end
    daily
end
