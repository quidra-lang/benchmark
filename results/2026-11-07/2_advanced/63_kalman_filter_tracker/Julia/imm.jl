mutable struct IMMFilter
    models::Vector{KalmanFilter}
    transition::Matrix{Float64}
    probabilities::Vector{Float64}
end
function IMMFilter(densities,transition,initial,sigma,velocity_variance,measurement)
    IMMFilter(
        [KalmanFilter("CV",q,sigma,velocity_variance,0.0,measurement) for q in densities],
        [transition[1] transition[2];transition[3] transition[4]],
        copy(initial)
    )
end
function imm_step!(filter,interval,measurement)
    mu,transition = filter.probabilities,filter.transition
    predicted = [transition[1,j]*mu[1]+transition[2,j]*mu[2] for j in 1:2]
    old_states,old_covariances = [m.x for m in filter.models],[m.p for m in filter.models]
    likelihoods = Float64[]
    for (j,model) in enumerate(filter.models)
        w1,w2 = transition[1,j]*mu[1]/predicted[j],transition[2,j]*mu[2]/predicted[j]
        mixed = [w1*old_states[1][r]+w2*old_states[2][r] for r in 1:4]
        covariance = [
            w1*(old_covariances[1][r,s]+(old_states[1][r]-mixed[r])*(old_states[1][s]-mixed[s]))+w2*(old_covariances[2][
                r,
                s
            ]+(old_states[2][r]-mixed[r])*(old_states[2][s]-mixed[s])) for r in 1:4,
            s in 1:4
        ]
        model.x,model.p = mixed,covariance
        predict!(model,interval)
        likelihood = 1.0
        if !isnothing(measurement)
            update = update!(model,measurement)
            likelihood = exp(-update.distance2/2)/(2*pi*sqrt(determinant2(update.covariance)))
        end
        push!(likelihoods,likelihood)
    end
    denominator = likelihoods[1]*predicted[1]+likelihoods[2]*predicted[2]
    filter.probabilities = [likelihoods[j]*predicted[j]/denominator for j in 1:2]
end
imm_estimate(filter) = [filter.probabilities[1]*filter.models[1].x[r]+filter.probabilities[2]*filter.models[2].x[r] for r in 1:4]
