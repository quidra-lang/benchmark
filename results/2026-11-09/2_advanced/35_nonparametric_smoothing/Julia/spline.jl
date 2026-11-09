mutable struct SplineFit
    positions::Vector{Int}
    x::Vector{Float64}
    penalty::Float64
    h::Vector{Float64}
    d::Vector{Float64}
    l1::Vector{Float64}
    l2::Vector{Float64}
    fit::Tuple{Vector{Float64},Vector{Float64}}
    fitted::Vector{Float64}
    basis::Vector{Tuple{Vector{Float64},Vector{Float64}}}
    leverage::Union{Nothing,Vector{Float64}}
    edf::Union{Nothing,Float64}
end
function SplineFit(positions,values,penalty;diagnostics=true)
    x = positions./100
    h = diff(x)
    count = length(positions)-2
    a,c = 1 ./h[1:count],1 ./h[2:count+1]
    b = .-(a.+c)
    diagonal = [(h[i]+h[i+1])/3+penalty*(a[i]*a[i]+b[i]*b[i]+c[i]*c[i]) for i in 1:count]
    first_band = [h[i+1]/6+penalty*c[i]*(b[i]+b[i+1]) for i in 1:count-1]
    second_band = [penalty*c[i]*c[i+1] for i in 1:count-2]
    d,l1,l2 = zeros(count),zeros(count),zeros(count)
    for i in 1:count
        i >= 3 && (l2[i]=second_band[i-2]/d[i-2])
        if i >= 2
            correction = i >= 3 ? l2[i]*d[i-2]*l1[i-1] : 0.0
            l1[i] = (first_band[i-1]-correction)/d[i-1]
        end
        value = diagonal[i]
        i >= 2 && (value -= l1[i]*l1[i]*d[i-1])
        i >= 3 && (value -= l2[i]*l2[i]*d[i-2])
        d[i] = value
    end
    model = SplineFit(
        positions,
        x,
        penalty,
        h,
        d,
        l1,
        l2,
        (Float64[],Float64[]),
        Float64[],
        Tuple{Vector{Float64},Vector{Float64}}[],
        nothing,
        nothing
    )
    model.fit = fit_values(model,values)
    model.fitted = model.fit[1]
    diagnostics && prepare_basis!(model)
    model
end
function fit_values(model::SplineFit,values)
    n = length(values)
    count = n-2
    z = zeros(count)
    for i in 1:count
        value = (values[i+2]-values[i+1])/model.h[i+1]-(values[i+1]-values[i])/model.h[i]
        i >= 2 && (value -= model.l1[i]*z[i-1])
        i >= 3 && (value -= model.l2[i]*z[i-2])
        z[i] = value
    end
    gamma = zeros(n)
    for i in count:-1:1
        value = z[i]/model.d[i]
        i+1 <= count && (value -= model.l1[i+1]*gamma[i+2])
        i+2 <= count && (value -= model.l2[i+2]*gamma[i+3])
        gamma[i+1] = value
    end
    omega = [(gamma[2]-gamma[1])/model.h[1]]
    for i in 2:n-1
        push!(omega,(gamma[i+1]-gamma[i])/model.h[i]-(gamma[i]-gamma[i-1])/model.h[i-1])
    end
    push!(omega,0-(gamma[n]-gamma[n-1])/model.h[n-1])
    [value-model.penalty*adjustment for (value,adjustment) in zip(values,omega)],gamma
end
function evaluate_fit(model::SplineFit,fit,position)
    fitted,gamma = fit
    x0 = position/100
    index = searchsortedfirst(model.positions,position)
    n = length(model.positions)
    index <= n && model.positions[index] == position && return fitted[index]
    if index == 1
        slope = (fitted[2]-fitted[1])/model.h[1]-model.h[1]*gamma[2]/6
        return fitted[1]-(model.x[1]-x0)*slope
    elseif index == n+1
        slope = (fitted[n]-fitted[n-1])/model.h[n-1]+model.h[n-1]*gamma[n-1]/6
        return fitted[n]+(x0-model.x[n])*slope
    end
    i = index-1
    left,right = x0-model.x[i],model.x[i+1]-x0
    (left*fitted[i+1]+right*fitted[i])/model.h[i]-left*right*((1+left/model.h[i])*gamma[i+1]+(1+right/model.h[i])*gamma[i])/6
end
function prepare_basis!(model::SplineFit)
    isempty(model.basis) || return
    n = length(model.positions)
    for i in 1:n
        unit = zeros(n)
        unit[i] = 1.0
        push!(model.basis,fit_values(model,unit))
    end
    model.leverage = [fit[1][i] for (i,fit) in enumerate(model.basis)]
    model.edf = ordered_sum(model.leverage)
end
estimate(model::SplineFit,position) = evaluate_fit(model,model.fit,position)
function weights(model::SplineFit,position)
    prepare_basis!(model)
    [evaluate_fit(model,fit,position) for fit in model.basis]
end
