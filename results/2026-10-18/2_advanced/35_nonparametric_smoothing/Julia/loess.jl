function median_value(values)
    ordered = sort(values)
    middle = length(ordered)÷2
    isodd(length(ordered)) ? ordered[middle+1] : (ordered[middle]+ordered[middle+1])/2
end
function cholesky_lower(matrix)
    n = size(matrix,1)
    lower = zeros(n,n)
    for row in 1:n, column in 1:row
        sigma = matrix[row,column]
        for k in 1:column-1
            sigma -= lower[row,k]*lower[column,k]
        end
        lower[row,column] = row == column ? sqrt(sigma) : sigma/lower[column,column]
    end
    lower
end
function solve_lower(lower,right)
    count = length(right)
    intermediate = zeros(count)
    for row in 1:count
        value = right[row]
        for k in 1:row-1
            value -= lower[row,k]*intermediate[k]
        end
        intermediate[row] = value/lower[row,row]
    end
    solution = zeros(count)
    for row in count:-1:1
        value = intermediate[row]
        for k in row+1:count
            value -= lower[k,row]*solution[k]
        end
        solution[row] = value/lower[row,row]
    end
    solution
end
mutable struct LoessFit
    positions::Vector{Int}
    x::Vector{Float64}
    y::Vector{Float64}
    span::Int
    degree::Int
    rho::Vector{Float64}
    records::Vector{Tuple{Int,Float64,Int,Float64}}
    cache::Dict{Int,Any}
    fitted::Union{Nothing,Vector{Float64}}
    leverage::Union{Nothing,Vector{Float64}}
    edf::Union{Nothing,Float64}
end
function local_fit(fit::LoessFit,position)
    count = length(fit.positions)
    q = fit.span*count÷100
    neighborhood = sort(collect(1:count),by=i->(abs(fit.positions[i]-position),i))[1:q]
    distance = maximum(abs(fit.positions[i]-position) for i in neighborhood)
    count_basis = fit.degree+1
    matrix,right = zeros(count_basis,count_basis),zeros(count_basis)
    rows = Tuple{Int,Float64,Vector{Float64}}[]
    for i in sort(neighborhood)
        a = abs(fit.positions[i]-position)/distance
        s = 1-a*a*a
        weight = s*s*s*fit.rho[i]
        delta = fit.x[i]-position/100
        basis = fit.degree == 1 ? [1.0,delta] : [1.0,delta,delta*delta]
        push!(rows,(i,weight,basis))
        for row in 1:count_basis
            right[row] += weight*basis[row]*fit.y[i]
            for column in 1:count_basis
                matrix[row,column] += weight*basis[row]*basis[column]
            end
        end
    end
    lower = cholesky_lower(matrix)
    beta = solve_lower(lower,right)
    zeta = solve_lower(lower,vcat([1.0],zeros(fit.degree)))
    coefficients = zeros(count)
    for (i,weight,basis) in rows
        coefficients[i] = weight*ordered_sum(zeta[k]*basis[k] for k in 1:count_basis)
    end
    beta[1],zeta[1],coefficients
end
function LoessFit(positions,values,span,degree,iterations;diagnostics=true)
    fit = LoessFit(
        positions,
        positions./100,
        values,
        span,
        degree,
        ones(length(positions)),
        Tuple{Int,Float64,Int,Float64}[],
        Dict{Int,Any}(),
        nothing,
        nothing,
        nothing
    )
    diagnostics || return fit
    fits = [local_fit(fit,position) for position in positions]
    for iteration in 1:iterations
        residuals = [y-pair[1] for (y,pair) in zip(values,fits)]
        scale = median_value(abs.(residuals))
        for (i,residual) in enumerate(residuals)
            u = residual/(6*scale)
            v = 1-u*u
            fit.rho[i] = abs(u) < 1 ? v*v : 0.0
        end
        updated = [local_fit(fit,position) for position in positions]
        change = maximum(abs(new[1]-old[1]) for (new,old) in zip(updated,fits))
        push!(fit.records,(iteration,scale,count(==(0.0),fit.rho),change))
        fits = updated
    end
    for (position,pair) in zip(positions,fits)
        fit.cache[position] = pair
    end
    fit.fitted = [pair[1] for pair in fits]
    fit.leverage = [rho*pair[2] for (rho,pair) in zip(fit.rho,fits)]
    fit.edf = ordered_sum(fit.leverage)
    fit
end
function evaluate(fit::LoessFit,position)
    get!(()->local_fit(fit,position),fit.cache,position)
end
estimate(fit::LoessFit,position) = evaluate(fit,position)[1]
weights(fit::LoessFit,position) = evaluate(fit,position)[3]
