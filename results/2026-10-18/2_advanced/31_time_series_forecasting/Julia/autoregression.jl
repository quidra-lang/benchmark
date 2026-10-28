const DIFFERENCE_KINDS = ("none","first","seasonal","both")
function difference(values,season,kind)
    kind == "none" && return (copy(values),0)
    kind == "first" && return ([values[t]-values[t-1] for t in 2:length(values)],1)
    kind == "seasonal" && return ([values[t]-values[t-season] for t in (season+1):length(values)],season)
    [(values[t]-values[t-1])-(values[t-season]-values[t-season-1]) for t in (season+2):length(values)],season+1
end
function autocorrelation(values,max_lag)
    average = series_mean(values)
    centered = values .- average
    n = length(values)
    variance = ordered_sum(value*value for value in centered)/n
    correlations = [1.0]
    for lag in 1:max_lag
        numerator = ordered_sum(centered[i]*centered[i+lag] for i in 1:(n-lag))
        push!(correlations,numerator/n/variance)
    end
    average,variance,correlations
end
function durbin_levinson(correlations)
    coefficients = [Float64[]]
    partial,variances = [0.0],[1.0]
    for order in 1:(length(correlations)-1)
        previous = coefficients[end]
        correction = ordered_sum(previous[j]*correlations[order-j+1] for j in 1:(order-1))
        theta = (correlations[order+1]-correction)/variances[end]
        current = vcat([previous[j]-theta*previous[order-j] for j in 1:(order-1)],[theta])
        push!(coefficients,current)
        push!(partial,theta)
        push!(variances,variances[end]*(1-theta*theta))
    end
    coefficients,partial,variances
end
function ar_residuals(values,average,coefficients)
    order = length(coefficients)
    [values[i]-average-ordered_sum(coefficients[j]*(values[i-j]-average) for j in 1:order) for i in (order+1):length(values)]
end
function ar_forecast(values,differenced,offset,kind,average,coefficients,origin,steps,season)
    transformed = copy(differenced[1:(origin-offset)])
    extended = copy(values[1:origin])
    result = Float64[]
    for _ in 1:steps
        predicted = average+ordered_sum(c*(transformed[end-j+1]-average) for (j,c) in enumerate(coefficients))
        push!(transformed,predicted)
        if kind == "first"
            predicted += extended[end]
        elseif kind == "seasonal"
            predicted += extended[end-season+1]
        elseif kind == "both"
            predicted = predicted+extended[end]+extended[end-season+1]-extended[end-season]
        end
        push!(extended,predicted)
        push!(result,predicted)
    end
    result
end
function ljung_box(errors,lags)
    n = length(errors)
    _,_,correlations = autocorrelation(errors,maximum(lags))
    result = NamedTuple[]
    for lag in lags
        q = n*(n+2)*ordered_sum(correlations[k+1]*correlations[k+1]/(n-k) for k in 1:lag)
        x,term = q/2,1.0
        terms = [term]
        for i in 1:(lag÷2-1)
            term = term*x/i
            push!(terms,term)
        end
        push!(result,(lag=lag,q=q,p=exp(-x)*ordered_sum(terms)))
    end
    result
end
