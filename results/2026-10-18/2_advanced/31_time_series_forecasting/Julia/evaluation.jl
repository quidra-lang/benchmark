seasonal_scale(
    values,
    season
) = ordered_sum(abs(values[t]-values[t-season]) for t in (season+1):length(values))/(length(values)-season)
function accuracy(actual,predicted,scale)
    n = length(actual)
    errors = actual .- predicted
    mae = ordered_sum(abs(value) for value in errors)/n
    Dict{Symbol,Any}(
        :me=>ordered_sum(errors)/n,
        :mae=>mae,
        :rmse=>sqrt(ordered_sum(value*value for value in errors)/n),
        :mape=>100*ordered_sum(abs(error)/value for (error,value) in zip(errors,actual))/n,
        :smape=>100*ordered_sum(2*abs(error)/(abs(a)+abs(f)) for (error,a,f) in zip(
            errors,
            actual,
            predicted
        ))/n,
        :mase=>mae/scale
    )
end
function winkler(actual,low,high,multiplier)
    actual < low && return high-low+multiplier*(low-actual)
    actual > high && return high-low+multiplier*(actual-high)
    high-low
end
rank_models(names,metrics) = sort(collect(names),by=name->(metrics[name][:rmse],findfirst(==(name),names)))
