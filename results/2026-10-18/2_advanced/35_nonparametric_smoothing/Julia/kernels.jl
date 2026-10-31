const KAPPA = Dict("epanechnikov"=>0.75,"biweight"=>0.9375,"triweight"=>1.09375)
mutable struct KernelFit
    positions::Vector{Int}
    x::Vector{Float64}
    y::Vector{Float64}
    bandwidth::Int
    kernel::String
    local_linear::Bool
    cache::Dict{Int,Any}
    fitted::Union{Nothing,Vector{Float64}}
    leverage::Union{Nothing,Vector{Float64}}
    edf::Union{Nothing,Float64}
end
function KernelFit(positions,values,bandwidth,kernel,local_linear;diagnostics=true)
    fit = KernelFit(
        positions,
        positions./100,
        values,
        bandwidth,
        kernel,
        local_linear,
        Dict{Int,Any}(),
        nothing,
        nothing,
        nothing
    )
    if diagnostics
        pairs = [evaluate(fit,position) for position in positions]
        if all(pair->!isnothing(pair[1]),pairs)
            fit.fitted = [pair[1] for pair in pairs]
            fit.leverage = [pair[2][i] for (i,pair) in enumerate(pairs)]
            fit.edf = ordered_sum(fit.leverage)
        end
    end
    fit
end
function evaluate(fit::KernelFit,position)
    haskey(fit.cache,position) && return fit.cache[position]
    used = findall(x->abs(x-position) < fit.bandwidth,fit.positions)
    if length(used) < (fit.local_linear ? 2 : 1)
        fit.cache[position] = (nothing,nothing)
        return nothing,nothing
    end
    x0,h = position/100,fit.bandwidth/100
    differences,kernels = Float64[],Float64[]
    for i in used
        delta = fit.x[i]-x0
        u = delta/h
        t = 1-u*u
        weight = KAPPA[fit.kernel]*t
        fit.kernel != "epanechnikov" && (weight *= t)
        fit.kernel == "triweight" && (weight *= t)
        push!(differences,delta)
        push!(kernels,weight)
    end
    s0 = ordered_sum(kernels)
    t0 = ordered_sum(weight*fit.y[i] for (i,weight) in zip(used,kernels))
    weights = zeros(length(fit.positions))
    if fit.local_linear
        s1 = ordered_sum(k*d for (k,d) in zip(kernels,differences))
        s2 = ordered_sum(k*d*d for (k,d) in zip(kernels,differences))
        t1 = ordered_sum(k*d*fit.y[i] for (i,k,d) in zip(used,kernels,differences))
        determinant = s0*s2-s1*s1
        estimate = (s2*t0-s1*t1)/determinant
        for (i,k,d) in zip(used,kernels,differences)
            weights[i] = k*(s2-s1*d)/determinant
        end
    else
        estimate = t0/s0
        for (i,k) in zip(used,kernels)
            weights[i] = k/s0
        end
    end
    fit.cache[position] = (estimate,weights)
end
estimate(fit::KernelFit,position) = evaluate(fit,position)[1]
weights(fit::KernelFit,position) = evaluate(fit,position)[2]
