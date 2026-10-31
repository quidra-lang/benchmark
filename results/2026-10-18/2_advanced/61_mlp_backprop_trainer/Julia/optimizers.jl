Base.@kwdef mutable struct OptimizerState
    momentum::Vector{Float64}
    first::Vector{Float64}
    second::Vector{Float64}
    power1::Float64 = 1.0
    power2::Float64 = 1.0
end
initialize_optimizer(count) = OptimizerState(momentum=zeros(count),first=zeros(count),second=zeros(count))
function epoch_rate(run,epoch,step,gamma)
    rate = run.rate
    for _ in 1:((epoch-1)÷step)
        rate *= gamma
    end
    rate
end
function update_parameters!(theta,grad,state,run,rate)
    if run.optimizer=="SGD"
        for i in eachindex(grad)
            theta[i] -= rate*grad[i]
        end
    elseif run.optimizer=="MOMENTUM"
        mu = run.extra[1]
        for i in eachindex(grad)
            state.momentum[i] = mu*state.momentum[i]+grad[i]
            theta[i] -= rate*state.momentum[i]
        end
    else
        beta1,beta2,epsilon = run.extra
        state.power1 *= beta1
        state.power2 *= beta2
        for (i,value) in enumerate(grad)
            state.first[i] = beta1*state.first[i]+(1-beta1)*value
            state.second[i] = beta2*state.second[i]+(1-beta2)*value*value
            corrected_first = state.first[i]/(1-state.power1)
            corrected_second = state.second[i]/(1-state.power2)
            theta[i] -= rate*corrected_first/(sqrt(corrected_second)+epsilon)
        end
    end
end
