include("series_io.jl")
include("decomposition.jl")
include("smoothing.jl")
include("autoregression.jl")
include("evaluation.jl")

const METHODS = (
    "naive",
    "snaive",
    "drift",
    "ses",
    "holt",
    "damped",
    "hw_add",
    "hw_mult",
    "decomp_add",
    "decomp_mult",
    "ar"
)
const MODELS = (METHODS..., "combo")
const SMOOTHING_PARAMETERS = Dict(
    "ses" => (:alpha,),
    "holt" => (:alpha, :beta),
    "damped" => (:alpha, :beta, :phi),
    "hw_add" => (:alpha, :beta, :gamma),
    "hw_mult" => (:alpha, :beta, :gamma)
)
const INTERVAL_FIELDS = (:forecast, :lo80, :hi80, :lo95, :hi95)
const ACCURACY_FIELDS = (
    :me,
    :mae,
    :rmse,
    :mape,
    :smape,
    :mase,
    :fva,
    :cv_rmse,
    :cover80,
    :cover95,
    :winkler80,
    :winkler95,
    :rank
)

Base.@kwdef mutable struct ForecastModel
    name::String
    series::Vector{Float64}
    season::Int
    residuals::Vector{Float64} = Float64[]
    parameters::Dict{Symbol,Float64} = Dict{Symbol,Float64}()
    states::Vector{NamedTuple} = NamedTuple[]
    intercept::Float64 = 0.0
    slope::Float64 = 0.0
    seasonal::Vector{Float64} = Float64[]
    kind::String = "none"
    differenced::Vector{Float64} = Float64[]
    offset::Int = 0
    average::Float64 = 0.0
    order::Int = 0
    variances::Vector{Float64} = Float64[]
    sigma2::Float64 = 0.0
    aic::Vector{Float64} = Float64[]
    coefficients::Vector{Float64} = Float64[]
    correlations::Vector{Float64} = Float64[]
    partial::Vector{Float64} = Float64[]
    members::Vector{ForecastModel} = ForecastModel[]
end
rmse(errors) = sqrt(ordered_sum(error*error for error in errors)/length(errors))
function interpolate_missing(raw)
    values = [isnothing(value) ? 0.0 : Float64(value) for value in raw]
    left = 1
    while left < length(raw)
        right = left+1
        while isnothing(raw[right])
            right += 1
        end
        for t in (left+1):(right-1)
            values[t] = raw[left]+(raw[right]-raw[left])*(t-left)/(right-left)
        end
        left = right
    end
    values
end
function future_periods(last,horizon)
    periods = String[]
    for _ in 1:horizon
        last = next_month(last)
        push!(periods,last)
    end
    periods
end
function prepare_series(record,settings)
    season = settings.season
    values = interpolate_missing(record.raw)
    missing = Set(findall(isnothing,record.raw))
    decomposition = decompose(values,season)
    trend,additive,residuals,defined = decomposition.trend,decomposition.additive,decomposition.residual_add,decomposition.defined
    average = series_mean(residuals[defined])
    deviation = sqrt(sample_variance(residuals[defined]))
    past = Dict(i=>record.events[period] for (i,period) in enumerate(record.periods) if haskey(
        record.events,
        period
    ))
    outliers = Dict(t=>(residuals[t]-average)/deviation for t in defined if !(t in missing) && !haskey(
        past,
        t
    ) && abs(residuals[t]-average) > settings.outlier*deviation)
    kinds = String[]
    grouped = Dict{String,Vector{Int}}()
    for t in sort(collect(keys(past)))
        kind = past[t]
        if !haskey(grouped,kind)
            push!(kinds,kind)
            grouped[kind] = Int[]
        end
        push!(grouped[kind],t)
    end
    lifts = Dict(kind=>(
        occurrences=length(grouped[kind]),
        lift=series_mean([values[t]/(trend[t]+additive[(t-1)%season+1]) for t in grouped[kind]])
    ) for kind in kinds)
    corrected = [haskey(past,t) || haskey(
        outliers,
        t
    ) ? trend[t]+additive[(t-1)%season+1] : value for (t,value) in enumerate(values)]
    variance_r = sample_variance(residuals[defined])
    variance_t = sample_variance([trend[t]+residuals[t] for t in defined])
    variance_s = sample_variance([additive[(t-1)%season+1]+residuals[t] for t in defined])
    (
        name=record.name,
        periods=record.periods,
        raw=record.raw,
        values=values,
        corrected=Float64.(corrected),
        future_periods=future_periods(record.periods[end],settings.horizon),
        missing=missing,
        past=past,
        outliers=outliers,
        kinds=kinds,
        lifts=lifts,
        decomposition=decomposition,
        strength_trend=max(0.0,1-variance_r/variance_t),
        strength_seasonal=max(0.0,1-variance_r/variance_s)
    )
end
function decomposition_prediction(model,time)
    base = model.intercept+model.slope*(time+1)
    seasonal = model.seasonal[time%model.season+1]
    model.name == "decomp_add" ? base+seasonal : base*seasonal
end
function fit_ar!(model,settings)
    transformed = [difference(model.series,model.season,kind) for kind in DIFFERENCE_KINDS]
    variances = [autocorrelation(values,0)[2] for (values,_) in transformed]
    chosen = argmin(variances)
    values,offset = transformed[chosen]
    average,variance,correlations = autocorrelation(values,settings.max_lag)
    coefficients,partial,prediction_variances = durbin_levinson(correlations)
    aic = [length(values)*log(variance*prediction_variances[p+1])+2*p for p in 0:settings.max_ar]
    order = argmin(aic)-1
    model.kind = DIFFERENCE_KINDS[chosen]
    model.differenced = values
    model.offset = offset
    model.average = average
    model.order = order
    model.variances = variances
    model.sigma2 = variance*prediction_variances[order+1]
    model.aic = aic
    model.coefficients = coefficients[order+1]
    model.correlations = correlations
    model.partial = partial
    model.residuals = ar_residuals(values,average,model.coefficients)
end
function fit_method(name,values,settings)
    model = ForecastModel(name=name,series=copy(values),season=settings.season)
    season,n = settings.season,length(values)
    if name == "naive"
        model.residuals = [values[t]-values[t-1] for t in 2:n]
    elseif name == "snaive"
        model.residuals = [values[t]-values[t-season] for t in (season+1):n]
    elseif name == "drift"
        model.slope = (values[end]-values[1])/(n-1)
        model.residuals = [values[t]-values[t-1]-model.slope for t in 2:n]
    elseif haskey(SMOOTHING_PARAMETERS,name)
        names = SMOOTHING_PARAMETERS[name]
        best_score = Inf
        parameters = Dict{Symbol,Float64}()
        function visit(depth)
            if depth <= length(names)
                key = names[depth]
                for value in getproperty(settings,key)
                    parameters[key] = value
                    visit(depth+1)
                end
            else
                residuals,states = smoothing_recurse(name,values,season,parameters)
                score = ordered_sum(error*error for error in residuals)
                if score < best_score
                    best_score = score
                    model.parameters = copy(parameters)
                    model.residuals = residuals
                    model.states = states
                end
            end
        end
        visit(1)
    elseif name in ("decomp_add","decomp_mult")
        components = decompose(values,season)
        additive = name == "decomp_add"
        model.seasonal = additive ? components.additive : components.multiplicative
        adjusted = [additive ? value-model.seasonal[(t-1)%season+1] : value/model.seasonal[(t-1)%season+1] for (
            t,
            value
        ) in enumerate(values)]
        model.intercept,model.slope = least_squares_line(adjusted)
        model.residuals = [value-decomposition_prediction(model,t-1) for (t,value) in enumerate(values)]
    else
        fit_ar!(model,settings)
    end
    model
end
combination_model(models,values,season) = ForecastModel(
    name="combo",
    series=copy(values),
    season=season,
    members=models
)
function forecast(model,origin,steps)
    name,values,season = model.name,model.series,model.season
    if name == "combo"
        predictions = [forecast(member,origin,steps) for member in model.members]
        return [ordered_sum(row[i] for row in predictions)/length(predictions) for i in 1:steps]
    elseif name == "naive"
        return fill(values[origin],steps)
    elseif name == "snaive"
        return [values[origin-season+(i-1)%season+1] for i in 1:steps]
    elseif name == "drift"
        slope = (values[origin]-values[1])/(origin-1)
        return [values[origin]+step*slope for step in 1:steps]
    elseif haskey(SMOOTHING_PARAMETERS,name)
        return smoothing_forecast(name,model.states[origin+1],model.parameters,origin,steps,season)
    elseif name in ("decomp_add","decomp_mult")
        return [decomposition_prediction(model,origin+step-1) for step in 1:steps]
    end
    ar_forecast(
        values,
        model.differenced,
        model.offset,
        model.kind,
        model.average,
        model.coefficients,
        origin,
        steps,
        season
    )
end
function cross_validate(model,settings)
    values,horizon = model.series,settings.horizon
    counts,squared,absolute = zeros(Int,horizon),zeros(horizon),zeros(horizon)
    for origin in settings.cv_start:(length(values)-1)
        predictions = forecast(model,origin,min(horizon,length(values)-origin))
        for (i,prediction) in enumerate(predictions)
            error = values[origin+i]-prediction
            counts[i] += 1
            squared[i] += error*error
            absolute[i] += abs(error)
        end
    end
    sigma = sqrt.(squared ./ counts)
    mae = absolute ./ counts
    holdout = settings.holdout
    (counts=counts,sigma=sigma,mae=mae,cv_rmse=sqrt(ordered_sum(squared[1:holdout])/sum(counts[1:holdout])))
end
function interval_rows(predicted,sigma,coefficients,multipliers=ones(length(predicted)))
    low,high = coefficients
    [(
        forecast=value*multiplier,
        lo80=(value-low*error)*multiplier,
        hi80=(value+low*error)*multiplier,
        lo95=(value-high*error)*multiplier,
        hi95=(value+high*error)*multiplier
    ) for (value,error,multiplier) in zip(predicted,sigma,multipliers)]
end
function evaluate_holdout(models,cvs,actual,training,settings)
    scale = seasonal_scale(training,settings.season)
    metrics = Dict{String,Dict{Symbol,Any}}()
    intervals = Dict{String,Vector{NamedTuple}}()
    for name in MODELS
        predicted = forecast(models[name],length(training),length(actual))
        rows = interval_rows(predicted,cvs[name].sigma,settings.interval)
        intervals[name] = rows
        measures = accuracy(actual,predicted,scale)
        measures[:cv_rmse] = cvs[name].cv_rmse
        measures[:cover80] = count(i->rows[i].lo80 <= actual[i] <= rows[i].hi80,eachindex(actual))
        measures[:cover95] = count(i->rows[i].lo95 <= actual[i] <= rows[i].hi95,eachindex(actual))
        measures[:winkler80] = ordered_sum(winkler(
            value,
            row.lo80,
            row.hi80,
            10
        ) for (row,value) in zip(rows,actual))/length(actual)
        measures[:winkler95] = ordered_sum(winkler(
            value,
            row.lo95,
            row.hi95,
            40
        ) for (row,value) in zip(rows,actual))/length(actual)
        metrics[name] = measures
    end
    naive_mae = metrics["naive"][:mae]
    for measures in values(metrics)
        measures[:fva] = 100*(naive_mae-measures[:mae])/naive_mae
    end
    ranking = rank_models(MODELS,metrics)
    for (rank,name) in enumerate(ranking)
        metrics[name][:rank] = rank
    end
    metrics,intervals,ranking[1]
end
function inventory_plan(model,demands,policy,settings)
    lead,review = policy.lead_time,policy.review
    protection = lead+review
    values = model.series
    errors = Float64[]
    for origin in settings.cv_start:(length(values)-protection)
        predictions = forecast(model,origin,protection)
        push!(errors,ordered_sum(values[origin+i]-prediction for (i,prediction) in enumerate(predictions)))
    end
    safety = policy.service*rmse(errors)
    reviews = collect(1:review:(length(demands)-protection+1))
    last = reviews[end]-1+protection
    on_hand,outstanding = Float64(policy.on_hand),0
    receipts = Dict{Int,Int}()
    rows = NamedTuple[]
    orders,ordered = 0,0
    for step in 1:last
        receipt = pop!(receipts,step,0)
        on_hand += receipt
        outstanding -= receipt
        review_row = nothing
        if step in reviews
            position = on_hand+outstanding
            target = ordered_sum(demands[step:(step+protection-1)])+safety
            quantity = max(0,ceil(Int,target-position))
            review_row = (position=position,target=target,order=quantity)
            if quantity > 0
                orders += 1
                ordered += quantity
                outstanding += quantity
                receipts[step+lead] = quantity
            end
        end
        on_hand -= demands[step]
        status = on_hand < 0 ? "short" : on_hand < safety ? "low" : "ok"
        push!(
            rows,
            (step=step,receipt=receipt,demand=demands[step],review=review_row,on_hand=on_hand,status=status)
        )
    end
    (
        safety=safety,
        rows=rows,
        orders=orders,
        ordered=ordered,
        short_periods=count(row->row.status == "short",rows),
        lowest=minimum(row.on_hand for row in rows),
        average=series_mean([row.on_hand for row in rows])
    )
end
function yearly_totals(periods,actual,future,demands)
    years = sort(unique([period[1:4] for period in vcat(periods,future)]))
    rows = NamedTuple[]
    previous = nothing
    for year in years
        actual_values = [value for (period,value) in zip(periods,actual) if period[1:4] == year]
        forecast_values = [value for (period,value) in zip(future,demands) if period[1:4] == year]
        actual_total,forecast_total = ordered_sum(actual_values),ordered_sum(forecast_values)
        total = actual_total+forecast_total
        complete = length(actual_values)+length(forecast_values) == 12
        growth = complete && !isnothing(previous) && previous.complete ? 100*(total-previous.total)/previous.total : nothing
        row = (
            year=year,
            actual_months=length(actual_values),
            actual=actual_total,
            forecast_months=length(forecast_values),
            forecast=forecast_total,
            total=total,
            growth=growth,
            complete=complete
        )
        push!(rows,row)
        previous = row
    end
    rows
end
function residual_diagnostics(errors,lags)
    n = length(errors)
    average = series_mean(errors)
    centered = errors .- average
    squared = ordered_sum(value*value for value in centered)
    m2 = squared/n
    m3 = ordered_sum(value*value*value for value in centered)/n
    m4 = ordered_sum(value*value*value*value for value in centered)/n
    sd = sqrt(squared/(n-1))
    dw = ordered_sum((errors[i]-errors[i-1])*(errors[i]-errors[i-1]) for i in 2:n)/ordered_sum(value*value for value in errors)
    skewness,kurtosis = m3/(m2*sqrt(m2)),m4/(m2*m2)-3
    jb = n/6*(skewness*skewness+kurtosis*kurtosis/4)
    (
        count=n,
        mean=average,
        sd=sd,
        dw=dw,
        skewness=skewness,
        kurtosis=kurtosis,
        jb=jb,
        ljung_box=ljung_box(errors,lags)
    )
end
function analyze(record,settings)
    data = prepare_series(record,settings)
    training_count = length(data.values)-settings.holdout
    training = data.corrected[1:training_count]
    actual = data.values[(training_count+1):end]
    models = Dict(name=>fit_method(name,training,settings) for name in METHODS)
    cvs = Dict(name=>cross_validate(models[name],settings) for name in METHODS)
    selected = sort(
        collect(METHODS),
        by=name->(cvs[name].cv_rmse,findfirst(==(name),METHODS))
    )[1:settings.combo]
    members = [name for name in METHODS if name in selected]
    models["combo"] = combination_model([models[name] for name in members],training,settings.season)
    cvs["combo"] = cross_validate(models["combo"],settings)
    metrics,intervals,best = evaluate_holdout(models,cvs,actual,training,settings)
    final_names = best == "combo" ? members : [best]
    final_fits = [fit_method(name,data.corrected,settings) for name in final_names]
    final = best == "combo" ? combination_model(final_fits,data.corrected,settings.season) : only(final_fits)
    final_cv = cross_validate(final,settings)
    future = forecast(final,length(data.values),settings.horizon)
    multipliers = [haskey(
        record.events,
        period
    ) ? data.lifts[record.events[period]].lift : 1.0 for period in data.future_periods]
    future_rows = interval_rows(future,final_cv.sigma,settings.interval,multipliers)
    demands = [row.forecast for row in future_rows]
    merge(
        data,
        (
            training_count=training_count,
            models=models,
            cv=cvs,
            members=members,
            metrics=metrics,
            intervals=intervals,
            best=best,
            final_fits=final_fits,
            future_rows=future_rows,
            policy=record.policy,
            plan=inventory_plan(final,demands,record.policy,settings),
            years=yearly_totals(data.periods,data.values,data.future_periods,demands),
            residual_diagnostics=Dict(name=>residual_diagnostics(
                models[name].residuals,
                settings.ljung_box
            ) for name in METHODS)
        )
    )
end
function model_lines(model)
    name = model.name
    common = "rmse $(real_format(rmse(model.residuals))) residuals $(length(model.residuals))"
    if name in ("naive","snaive")
        return ["$name $common"]
    elseif name == "drift"
        return ["drift slope $(real_format(model.slope)) $common"]
    elseif haskey(SMOOTHING_PARAMETERS,name)
        parameters = join(
            ("$key $(real_format(model.parameters[key]))" for key in SMOOTHING_PARAMETERS[name]),
            ' '
        )
        state = model.states[end]
        line = "$name $parameters $common level $(real_format(state.level))"
        name != "ses" && (line *= " slope $(real_format(state.slope))")
        lines = [line]
        if !isnothing(state.components)
            origin = length(model.series)
            values = [state.components[(origin+i)%model.season+1] for i in 0:(model.season-1)]
            push!(lines,"$name seasonal "*join(real_format.(values),' '))
        end
        return lines
    elseif name in ("decomp_add","decomp_mult")
        return [
            "$name intercept $(real_format(model.intercept)) slope $(real_format(model.slope)) $common",
            "$name seasonal "*join(real_format.(model.seasonal),' ')
        ]
    end
    variance = join(
        ("$kind $(real_format(value))" for (kind,value) in zip(DIFFERENCE_KINDS,model.variances)),
        ' '
    )
    coefficients = isempty(model.coefficients) ? "none" : join(real_format.(model.coefficients),' ')
    [
        "ar variance $variance",
        "ar difference $(model.kind) n $(length(model.differenced)) mean $(real_format(model.average)) order $(model.order) sigma2 $(real_format(model.sigma2)) $common",
        "ar aic "*join(real_format.(model.aic),' '),
        "ar coefficients $coefficients"
    ]
end
function decomposition_lines(analyses,settings)
    lines = ["series,period,value,cleaned,trend,seasonal_add,residual_add,seasonal_mult,residual_mult,flag"]
    for data in analyses
        decomposition = data.decomposition
        for (t,period) in enumerate(data.periods)
            flag = haskey(data.past,t) ? data.past[t] : t in data.missing ? "missing" : haskey(
                data.outliers,
                t
            ) ? "outlier" : "ok"
            j = (t-1)%settings.season+1
            values = (
                data.values[t],
                data.corrected[t],
                decomposition.trend[t],
                decomposition.additive[j],
                decomposition.residual_add[t],
                decomposition.multiplicative[j],
                decomposition.residual_mult[t]
            )
            push!(lines,join((data.name,period,real_format.(values)...,flag),','))
        end
    end
    lines
end
function fitted_lines(analyses,settings)
    lines = String[]
    for data in analyses
        push!(
            lines,
            "series $(data.name)",
            "data observations $(length(data.values)) train $(data.training_count) holdout $(settings.holdout) missing $(length(data.missing)) outliers $(length(data.outliers)) events $(length(data.past))"
        )
        for kind in data.kinds
            lift = data.lifts[kind]
            push!(lines,"event $kind occurrences $(lift.occurrences) lift $(real_format(lift.lift))")
        end
        for t in sort(collect(keys(data.outliers)))
            push!(
                lines,
                "outlier $(data.periods[t]) value $(real_format(data.values[t])) expected $(real_format(data.corrected[t])) score $(real_format(data.outliers[t]))"
            )
        end
        push!(
            lines,
            "strength trend $(real_format(data.strength_trend)) seasonal $(real_format(data.strength_seasonal))"
        )
        for name in METHODS
            append!(lines,model_lines(data.models[name]))
        end
        push!(
            lines,
            "combo members "*join(data.members,' '),
            "best $(data.best) rmse $(real_format(data.metrics[data.best][:rmse]))"
        )
        for model in data.final_fits
            append!(lines,["final $line" for line in model_lines(model)])
        end
    end
    lines
end
function forecast_lines(analyses)
    lines = ["series,stage,method,period,actual,forecast,lo80,hi80,lo95,hi95"]
    for data in analyses
        for method in MODELS,(i,row) in enumerate(data.intervals[method])
            index = data.training_count+i
            push!(
                lines,
                join(
                    (
                        data.name,
                        "holdout",
                        method,
                        data.periods[index],
                        data.raw[index],
                        (real_format(getproperty(row,key)) for key in INTERVAL_FIELDS)...
                    ),
                    ','
                )
            )
        end
        for (period,row) in zip(data.future_periods,data.future_rows)
            push!(
                lines,
                join(
                    (
                        data.name,
                        "future",
                        data.best,
                        period,
                        "NA",
                        (real_format(getproperty(row,key)) for key in INTERVAL_FIELDS)...
                    ),
                    ','
                )
            )
        end
    end
    lines
end
function accuracy_lines(analyses)
    lines = ["series,method,"*join(string.(ACCURACY_FIELDS),',')]
    for data in analyses,method in MODELS
        metrics = data.metrics[method]
        fields = [key in (
            :cover80,
            :cover95,
            :rank
        ) ? string(metrics[key]) : real_format(metrics[key]) for key in ACCURACY_FIELDS]
        push!(lines,join(vcat([data.name,method],fields),','))
    end
    lines
end
function cv_lines(analyses)
    lines = ["series,method,step,origins,mae,rmse"]
    for data in analyses,method in MODELS
        cv = data.cv[method]
        for i in eachindex(cv.counts)
            push!(
                lines,
                "$(data.name),$method,$i,$(cv.counts[i]),$(real_format(cv.mae[i])),$(real_format(cv.sigma[i]))"
            )
        end
    end
    lines
end
function correlation_bar(value,band)
    width = floor(Int,abs(value)*20+0.5)
    threshold = floor(Int,band*20+0.5)
    bar = fill(' ',41)
    bar[21-threshold] = bar[21+threshold] = ':'
    bar[21] = '|'
    value > 0 && (bar[22:(21+width)] .= '#')
    value < 0 && (bar[(21-width):20] .= '#')
    String(bar)
end
function correlogram_lines(analyses)
    lines = String[]
    for data in analyses
        ar = data.models["ar"]
        n = length(ar.differenced)
        band = 2/sqrt(n)
        push!(lines,"series $(data.name) difference $(ar.kind) n $n band $(real_format(band))")
        for (label,sequence) in (("acf",ar.correlations),("pacf",ar.partial)),lag in 1:(length(sequence)-1)
            value = sequence[lag+1]
            line = "$label $(lpad(string(lag),2)) $(lpad(real_format(value),7)) [$(correlation_bar(value,band))]"
            push!(lines,line*(abs(value) > band ? " *" : ""))
        end
        for method in METHODS
            stats = data.residual_diagnostics[method]
            push!(
                lines,
                "residuals $method n $(stats.count) mean $(real_format(stats.mean)) sd $(real_format(stats.sd)) dw $(real_format(stats.dw)) skewness $(real_format(stats.skewness)) kurtosis $(real_format(stats.kurtosis)) jb $(real_format(stats.jb))"
            )
            parts = ["lag $(r.lag) q $(real_format(r.q)) p $(real_format(r.p))" for r in stats.ljung_box]
            push!(lines,"ljung_box $method "*join(parts,' '))
        end
    end
    lines
end
function forecast_chart(row,low,high)
    column(value) = floor(Int,(value-low)/(high-low)*60+0.5)+1
    cells = fill(' ',61)
    cells[column(row.lo95):column(row.hi95)] .= '-'
    cells[column(row.lo80):column(row.hi80)] .= '='
    cells[column(row.forecast)] = 'o'
    !isnothing(row.actual) && (cells[column(row.actual)] = '*')
    String(cells)
end
function seasonal_profile(value,peak)
    width = floor(Int,abs(value-1)/peak*30+0.5)
    cells = fill(' ',61)
    cells[31] = '|'
    value > 1 && (cells[32:(31+width)] .= '#')
    value < 1 && (cells[(31-width):30] .= '#')
    String(cells)
end
function chart_lines(analyses)
    lines = String[]
    for data in analyses
        rows = NamedTuple[]
        for (i,row) in enumerate(data.intervals[data.best])
            index = data.training_count+i
            push!(rows,merge(row,(period=data.periods[index],actual=data.values[index])))
        end
        for (period,row) in zip(data.future_periods,data.future_rows)
            push!(rows,merge(row,(period=period,actual=nothing)))
        end
        actual = [row.actual for row in rows if !isnothing(row.actual)]
        low = minimum(vcat([row.lo95 for row in rows],actual))
        high = maximum(vcat([row.hi95 for row in rows],actual))
        push!(
            lines,
            "chart $(data.name) method $(data.best)",
            "scale low $(real_format(low)) high $(real_format(high))"
        )
        for row in rows
            push!(lines,"$(row.period) |$(forecast_chart(row,low,high))|")
        end
        seasonal = data.decomposition.multiplicative
        peak = maximum(abs(value-1) for value in seasonal)
        push!(lines,"profile peak $(real_format(peak))")
        for (i,value) in enumerate(seasonal)
            push!(lines,"season $(lpad(string(i),2)) $(real_format(value)) [$(seasonal_profile(value,peak))]")
        end
    end
    lines
end
function plan_lines(analyses)
    lines = String[]
    for data in analyses
        policy,plan = data.policy,data.plan
        push!(
            lines,
            "series $(data.name) method $(data.best)",
            "policy on_hand $(policy.on_hand) lead_time $(policy.lead_time) review $(policy.review) service $(real_format(policy.service)) safety_stock $(real_format(plan.safety))"
        )
        for row in plan.rows
            period = data.future_periods[row.step]
            if !isnothing(row.review)
                review = row.review
                push!(
                    lines,
                    "review $period position $(real_format(review.position)) target $(real_format(review.target)) order $(review.order)"
                )
            end
            push!(
                lines,
                "period $period demand $(real_format(row.demand)) receipt $(row.receipt) on_hand $(real_format(row.on_hand)) status $(row.status)"
            )
        end
        push!(
            lines,
            "summary orders $(plan.orders) ordered $(plan.ordered) short_periods $(plan.short_periods) lowest $(real_format(plan.lowest)) average $(real_format(plan.average))"
        )
        for year in data.years
            push!(
                lines,
                "year $(year.year) actual_months $(year.actual_months) actual $(real_format(year.actual)) forecast_months $(year.forecast_months) forecast $(real_format(year.forecast)) total $(real_format(year.total)) growth $(real_format(year.growth))"
            )
        end
    end
    lines
end
function main()
    records,settings = read_inputs()
    analyses = [analyze(record,settings) for record in records]
    outputs = (
        ("decomposition.csv",decomposition_lines(analyses,settings)),
        ("models.txt",fitted_lines(analyses,settings)),
        ("forecasts.csv",forecast_lines(analyses)),
        ("accuracy.csv",accuracy_lines(analyses)),
        ("cv.csv",cv_lines(analyses)),
        ("correlogram.txt",correlogram_lines(analyses)),
        ("chart.txt",chart_lines(analyses)),
        ("plan.txt",plan_lines(analyses))
    )
    for (name,lines) in outputs
        write_lines(name,lines)
    end
end
main()
