function ordered_sum(values)
    result = 0.0
    for value in values
        result += value
    end
    result
end
series_mean(values) = ordered_sum(values)/length(values)
function sample_variance(values)
    average = series_mean(values)
    ordered_sum((value-average)*(value-average) for value in values)/(length(values)-1)
end
function decompose(values,season)
    n,half = length(values),season÷2
    defined = collect((half+1):(n-half))
    trend = Union{Nothing,Float64}[nothing for _ in values]
    for t in defined
        value = 0.5*values[t-half]
        for i in (t-half+1):(t+half-1)
            value += values[i]
        end
        value += 0.5*values[t+half]
        trend[t] = value/season
    end
    additive,multiplicative = Float64[],Float64[]
    for position in 0:(season-1)
        times = [t for t in defined if (t-1)%season == position]
        push!(additive,series_mean([values[t]-trend[t] for t in times]))
        push!(multiplicative,series_mean([values[t]/trend[t] for t in times]))
    end
    average_add,average_mult = ordered_sum(additive)/season,ordered_sum(multiplicative)/season
    additive = additive .- average_add
    multiplicative = multiplicative ./ average_mult
    residual_add = Union{Nothing,Float64}[nothing for _ in values]
    residual_mult = copy(residual_add)
    for t in defined
        j = (t-1)%season+1
        residual_add[t] = values[t]-trend[t]-additive[j]
        residual_mult[t] = values[t]/(trend[t]*multiplicative[j])
    end
    (
        trend=trend,
        additive=additive,
        multiplicative=multiplicative,
        residual_add=residual_add,
        residual_mult=residual_mult,
        defined=defined
    )
end
function least_squares_line(values)
    n = length(values)
    center,average = (n+1)/2,series_mean(values)
    numerator = ordered_sum((t-center)*(value-average) for (t,value) in enumerate(values))
    denominator = ordered_sum((t-center)*(t-center) for t in 1:n)
    slope = numerator/denominator
    average-slope*center,slope
end
