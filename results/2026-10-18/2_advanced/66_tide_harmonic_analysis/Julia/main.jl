include("records.jl")
include("cleaning.jl")
include("harmonic_fit.jl")
include("predict.jl")
include("report.jl")

const DOODSON_WEIGHTS = (0,2,1,1,2,0,1,1,0,2,0,1,1,0,1,0,0,1,0,1)
const LEADING = ("M2","S2","K1","O1")
ordered_sum(values) = foldl(+,values;init=0.0)
average(values) = ordered_sum(values)/length(values)
rms(values) = sqrt(ordered_sum(v*v for v in values)/length(values))
words(parts...) = join(string.(parts)," ")
kv(name,value) = string(name,"=",value)
function select_constituents(constituents,tau,rayleigh)
    selected,status = NamedTuple[],Dict{String,String}()
    for c in constituents
        if c.speed*tau<360rayleigh
            status[c.name] = "short"
            continue
        end
        conflict = findfirst(chosen->abs(c.speed-chosen.speed)*tau<360rayleigh,selected)
        if !isnothing(conflict)
            status[c.name] = "conflict:"*selected[conflict].name
        else
            status[c.name] = "fitted"
            push!(selected,c)
        end
    end
    selected,status
end
function residual_statistics(values,usable,model)
    residuals = Dict(t=>values[t]-predict_height(model,t) for t in usable)
    squared = ordered_sum(residuals[t]*residuals[t] for t in usable)
    dof = length(usable)-model.unknowns
    mean = average([values[t] for t in usable])
    total = ordered_sum((values[t]-mean)*(values[t]-mean) for t in usable)
    paired = [t for t in usable if haskey(residuals,t+1)]
    lag1 = ordered_sum(residuals[t]*residuals[t+1] for t in paired)/ordered_sum(residuals[t]*residuals[t] for t in paired)
    (
        residuals=residuals,
        squared=squared,
        variance=squared/dof,
        dof=dof,
        rms=sqrt(squared/length(usable)),
        max_abs=maximum(abs,Base.values(residuals)),
        explained_percent=100*(1-squared/total),
        lag1=lag1
    )
end
function constituent_errors(model,variance,min_snr)
    errors = Dict{String,NamedTuple}()
    for c in model.selected
        constant = model.constants[c.name]
        a,b,amp,ia,ib = constant.a,constant.b,constant.amplitude,constant.index_a,constant.index_b
        va,vb,cab = variance*model.inverse[ia,ia],variance*model.inverse[ib,ib],variance*model.inverse[ia,ib]
        ae = sqrt(a*a*va+b*b*vb+2a*b*cab)/amp
        pe = sqrt(b*b*va+a*a*vb-2a*b*cab)/(amp*amp)*180/TIDE_PI
        ratio = amp/ae
        snr = ratio*ratio
        errors[c.name] = (amplitude_error=ae,phase_error=pe,snr=snr,significant=snr>=min_snr ? "yes" : "no")
    end
    errors
end
function cross_validate(values,usable,first,last,constituents,rayleigh,residuals)
    mid = first+(last-first)÷2
    training,testing = filter(<=(mid),usable),filter(>(mid),usable)
    selected,_ = select_constituents(constituents,training[end]-training[1],rayleigh)
    model = fit(values,training,selected)
    errors = [values[t]-predict_height(model,t) for t in testing]
    squared = ordered_sum(e*e for e in errors)
    mean = average([values[t] for t in testing])
    variation = ordered_sum((values[t]-mean)*(values[t]-mean) for t in testing)
    (
        midpoint=mid,
        training_count=length(training),
        testing_count=length(testing),
        constituents=length(selected),
        rms=sqrt(squared/length(testing)),
        in_sample_rms=sqrt(ordered_sum(residuals[t]*residuals[t] for t in testing)/length(testing)),
        skill=1-squared/variation
    )
end
function residual_events(usable,residuals,threshold,minimum_hours)
    events,current,current_sign = NamedTuple[],Int[],""
    function flush!()
        length(current)<minimum_hours && return
        peak = current_sign=="positive" ? argmax(t->residuals[t],current) : argmin(t->residuals[t],current)
        push!(events,(kind=current_sign,start=current[1],stop=current[end],peak=peak,value=residuals[peak]))
    end
    for t in usable
        value = residuals[t]
        kind = value>threshold ? "positive" : value< -threshold ? "negative" : ""
        if !isempty(kind) && kind==current_sign && !isempty(current) && t==current[end]+1
            push!(current,t)
        else
            flush!()
            current = isempty(kind) ? Int[] : [t]
            current_sign = kind
        end
    end
    flush!()
    events
end
function daily_means(cleaning,model)
    rows = NamedTuple[]
    usable = Set(cleaning.usable)
    for day in cleaning.first÷24:cleaning.last÷24
        noon = 24day+12
        (noon-19<cleaning.first || noon+19>cleaning.last) && continue
        total,missing = 0.0,0
        for j in -19:19
            t = noon+j
            if t in usable
                value = cleaning.values[t]
            else
                value = predict_height(model,t)
                missing += 1
            end
            total += DOODSON_WEIGHTS[abs(j)+1]*value
        end
        push!(rows,(day=day,level=total/30,filled=missing))
    end
    levels = [row.level for row in rows]
    mean,mean_day = average(levels),(length(rows)-1)/2
    numerator = ordered_sum((i-1-mean_day)*(value-mean) for (i,value) in enumerate(levels))
    denominator = ordered_sum((i-mean_day)*(i-mean_day) for i in 0:length(rows)-1)
    (
        rows=rows,
        days=length(rows),
        average=mean,
        slope_mm_per_day=1000*numerator/denominator,
        max=rows[argmax(levels)],
        min=rows[argmin(levels)]
    )
end
function refine_extrema(model,start,hours,grid,min_range)
    extrema = find_extrema(model,start,hours,grid)
    raw = length(extrema)
    while length(extrema)>=2
        index = argmin(i->abs(extrema[i].height-extrema[i+1].height),1:length(extrema)-1)
        abs(extrema[index].height-extrema[index+1].height)>=min_range && break
        deleteat!(extrema,index:index+1)
    end
    extrema = [(;e...,rounded=floor(Int,e.minute+0.5),day=floor(Int,e.minute+0.5)÷1440) for e in extrema]
    labels = fill("",length(extrema))
    for day in unique([e.day for e in extrema]),kind in ("high","low")
        indices = [i for (i,e) in enumerate(extrema) if e.day==day && e.kind==kind]
        isempty(indices) && continue
        best = kind=="high" ? argmax(i->extrema[i].height,indices) : argmin(i->extrema[i].height,indices)
        for i in indices
            labels[i] = kind=="high" ? (i==best ? "HHW" : "LHW") : (i==best ? "LLW" : "HLW")
        end
    end
    [(;e...,label=labels[i]) for (i,e) in enumerate(extrema)],raw
end
function daily_extrema(extrema,start,days)
    table = NamedTuple[]
    for day in start:start+days-1
        highs = [e.height for e in extrema if e.day==day && e.kind=="high"]
        lows = [e.height for e in extrema if e.day==day && e.kind=="low"]
        hhw,llw = isempty(highs) ? nothing : maximum(highs),isempty(lows) ? nothing : minimum(lows)
        span = isnothing(hhw) || isnothing(llw) ? nothing : hhw-llw
        push!(table,(day=day,high_waters=length(highs),low_waters=length(lows),hhw=hhw,llw=llw,range=span))
    end
    table
end
function characteristics(model,extrema,daily,hourly,start,hours)
    constants = model.constants
    highs,lows = filter(e->e.kind=="high",extrema),filter(e->e.kind=="low",extrema)
    mhhw,mllw = average([d.hhw for d in daily if !isnothing(d.hhw)]),average([d.llw for d in daily if !isnothing(d.llw)])
    mhw,mlw = average([e.height for e in highs]),average([e.height for e in lows])
    mtl,dtl,mn,gt = (mhw+mlw)/2,(mhhw+mllw)/2,mhw-mlw,mhhw-mllw
    rises,falls = Int[],Int[]
    for i in 2:length(extrema)
        previous,current = extrema[i-1],extrema[i]
        previous.kind=="low" && current.kind=="high" && push!(rises,current.rounded-previous.rounded)
        previous.kind=="high" && current.kind=="low" && push!(falls,current.rounded-previous.rounded)
    end
    m2,s2,m4 = constants["M2"],constants["S2"],constants["M4"]
    phase = 2*m2.phase-m4.phase
    while phase<0
        phase += 360
    end
    while phase>=360
        phase -= 360
    end
    form = (constants["K1"].amplitude+constants["O1"].amplitude)/(m2.amplitude+s2.amplitude)
    kind = form<0.25 ? "semidiurnal" : form<1.5 ? "mixed_semidiurnal" : form<3 ? "mixed_diurnal" : "diurnal"
    complete = filter(d->!isnothing(d.range),daily)
    total_amp = ordered_sum(constants[c.name].amplitude for c in model.selected)
    dw,dg = s2.speed-m2.speed,s2.phase-m2.phase
    q1,q2 = (dw*start-dg)/180,(dw*(start+hours)-dg)/180
    spring_neap = NamedTuple[]
    for q in ceil(Int,min(q1,q2)):floor(Int,max(q1,q2))
        t = (dg+180q)/dw
        start<=t<=start+hours && push!(
            spring_neap,
            (kind=iseven(q) ? "spring" : "neap",minute=floor(Int,60t+0.5))
        )
    end
    (
        mhhw=mhhw,
        mllw=mllw,
        mhw=mhw,
        mlw=mlw,
        mtl=mtl,
        dtl=dtl,
        mn=mn,
        gt=gt,
        highs=highs,
        lows=lows,
        rise_minutes=average(rises),
        fall_minutes=average(falls),
        m4_m2_ratio=m4.amplitude/m2.amplitude,
        relative_phase=phase,
        dominance=phase<180 ? "flood" : "ebb",
        form_number=form,
        type=kind,
        spring=2*(m2.amplitude+s2.amplitude),
        neap=2*(m2.amplitude-s2.amplitude),
        hat=model.mean_level+total_amp,
        lat=model.mean_level-total_amp,
        highest=argmax(e->e.height,highs),
        lowest=argmin(e->e.height,lows),
        widest=argmax(d->d.range,complete),
        narrowest=argmin(d->d.range,complete),
        above_mhhw=100count(>(mhhw),hourly)/length(hourly),
        below_mllw=100count(<(mllw),hourly)/length(hourly),
        spring_neap=spring_neap
    )
end
function inspect_station(station,record,constituents,settings,start)
    cleaning = prepare_record(record,settings.flat_run)
    selected,status = select_constituents(constituents,cleaning.record_length,settings.rayleigh)
    preliminary = fit(cleaning.values,cleaning.candidates,selected)
    residuals = Dict(t=>cleaning.values[t]-predict_height(preliminary,t) for t in cleaning.candidates)
    prefit = rms([residuals[t] for t in cleaning.candidates])
    cleaning = detect_spikes(cleaning,residuals,settings)
    cleaning = (;cleaning...,prefit_rms=prefit)
    model = fit(cleaning.values,cleaning.usable,selected)
    residual = residual_statistics(cleaning.values,cleaning.usable,model)
    errors = constituent_errors(model,residual.variance,settings.snr_min)
    validation = cross_validate(
        cleaning.values,
        cleaning.usable,
        cleaning.first,
        cleaning.last,
        constituents,
        settings.rayleigh,
        residual.residuals
    )
    surges = residual_events(cleaning.usable,residual.residuals,settings.surge_threshold,settings.surge_hours)
    means = daily_means(cleaning,model)
    hourly = predict_hours(model,start,settings.prediction_hours)
    extrema,raw = refine_extrema(
        model,
        start,
        settings.prediction_hours,
        settings.grid_minutes,
        settings.min_range
    )
    daily = daily_extrema(extrema,start÷24,settings.prediction_hours÷24)
    c = characteristics(model,extrema,daily,hourly,start,settings.prediction_hours)
    (
        code=station.code,
        name=station.name,
        cleaning=cleaning,
        status=status,
        model=model,
        residual=residual,
        errors=errors,
        validation=validation,
        surges=surges,
        daily_means=means,
        hourly=hourly,
        extrema=extrema,
        raw_extrema=raw,
        daily=daily,
        characteristics=c
    )
end
function station_outputs(station,constituents,settings)
    code,c,m,r = station.code,station.cleaning,station.model,station.residual
    stamp(t) = datetime_at_hour(settings.epoch,t)
    minute_stamp(t) = datetime_at_minute(settings.epoch,t)
    date(day) = date_at_day(settings.epoch,day)
    cleaning = [
        words(kv("station",code),kv("name",station.name)),
        words(
            "span",
            kv("start",stamp(c.first)),
            kv("end",stamp(c.last)),
            kv("hours",c.record_length+1),
            kv("record_length",c.record_length)
        ),
        words(
            "counts",
            kv("rows",c.rows),
            kv("numeric",length(c.numeric_times)),
            kv("na",count(==("na"),values(c.reasons))),
            kv("absent",count(==("absent"),values(c.reasons))),
            kv("flat",count(==("flat"),values(c.reasons))),
            kv("spikes",length(c.spikes)),
            kv("usable",length(c.usable))
        )
    ]
    for run in c.flat_runs
        push!(
            cleaning,
            words(
                "flat",
                kv("start",stamp(run.start)),
                kv("end",stamp(run.stop)),
                kv("value",decimal(run.value,3)),
                kv("removed",run.stop-run.start)
            )
        )
    end
    push!(
        cleaning,
        words(
            "spike_test",
            kv("window",settings.spike_window),
            kv("candidates",length(c.candidates)),
            kv("tested",c.tested),
            kv("prefit_rms",decimal(c.prefit_rms,4))
        )
    )
    for spike in c.spikes
        push!(
            cleaning,
            words(
                "spike",
                kv("time",stamp(spike.time)),
                kv("value",decimal(spike.value,3)),
                kv("residual",decimal(spike.residual,4)),
                kv("median",decimal(spike.median,4)),
                kv("mad",decimal(spike.mad,4)),
                kv("limit",decimal(spike.limit,4))
            )
        )
    end
    for gap in c.gaps
        push!(
            cleaning,
            words(
                "gap",
                kv("start",stamp(gap.start)),
                kv("end",stamp(gap.stop)),
                kv("hours",gap.stop-gap.start+1),
                kv("cause",gap.cause)
            )
        )
    end
    constants = String[]
    for constituent in constituents
        name = constituent.name
        status = station.status[name]
        if status!="fitted"
            push!(constants,join((code,name,decimal(constituent.speed,7),status),",")*",,,,,,")
        else
            constant,error = m.constants[name],station.errors[name]
            push!(
                constants,
                join(
                    (
                        code,
                        name,
                        decimal(constituent.speed,7),
                        "fitted",
                        decimal(constant.amplitude,4),
                        decimal(constant.phase,2),
                        decimal(error.amplitude_error,4),
                        decimal(error.phase_error,2),
                        decimal(error.snr,1),
                        error.significant
                    ),
                    ","
                )
            )
        end
    end
    extremes = [words(
        kv("station",code),
        kv("extremes",length(station.extrema)),
        kv("raw",station.raw_extrema),
        kv("removed",station.raw_extrema-length(station.extrema))
    )]
    for (i,e) in enumerate(station.extrema)
        change = i==1 ? "none" : decimal(e.height-station.extrema[i-1].height,3)
        push!(extremes,words(minute_stamp(e.rounded),e.label,decimal(e.height,3),kv("change",change)))
    end
    for day in station.daily
        push!(
            extremes,
            words(
                "day",
                kv("date",date(day.day)),
                kv("high_waters",day.high_waters),
                kv("low_waters",day.low_waters),
                kv("hhw",optional(day.hhw,3)),
                kv("llw",optional(day.llw,3)),
                kv("range",optional(day.range,3))
            )
        )
    end
    summary = [
        "[station $code] $(station.name)",
        words(
            "record",
            kv("first",stamp(c.first)),
            kv("last",stamp(c.last)),
            kv("length",c.record_length),
            kv("usable",length(c.usable))
        ),
        words(
            "fit",
            kv("constituents",length(m.selected)),
            kv("unknowns",m.unknowns),
            kv("dof",r.dof),
            kv("mean_level",decimal(m.mean_level,4))
        ),
        words(
            "residual",
            kv("rms",decimal(r.rms,4)),
            kv("max_abs",decimal(r.max_abs,4)),
            kv("explained_percent",decimal(r.explained_percent,4)),
            kv("lag1_autocorrelation",decimal(r.lag1,4))
        )
    ]
    top = sort!(copy(c.usable);by=t->(-abs(r.residuals[t]),t))[1:settings.top_residuals]
    for (rank,t) in enumerate(top)
        push!(
            summary,
            words(
                "top_residual",
                kv("rank",rank),
                kv("time",stamp(t)),
                kv("observed",decimal(c.values[t],3)),
                kv("fitted",decimal(predict_height(m,t),4)),
                kv("residual",decimal(r.residuals[t],4))
            )
        )
    end
    v = station.validation
    push!(
        summary,
        words(
            "validation",
            kv("split",stamp(v.midpoint)),
            kv("train",v.training_count),
            kv("test",v.testing_count),
            kv("constituents",v.constituents),
            kv("rms",decimal(v.rms,4)),
            kv("in_sample_rms",decimal(v.in_sample_rms,4)),
            kv("skill",decimal(v.skill,4))
        )
    )
    t = station.characteristics
    push!(summary,words(kv("form_number",decimal(t.form_number,4)),kv("type",t.type)))
    push!(
        summary,
        words(
            "ranges",
            kv("spring",decimal(t.spring,3)),
            kv("neap",decimal(t.neap,3)),
            kv("mn",decimal(t.mn,3)),
            kv("gt",decimal(t.gt,3))
        )
    )
    push!(
        summary,
        words(
            "asymmetry",
            kv("rise_minutes",decimal(t.rise_minutes,1)),
            kv("fall_minutes",decimal(t.fall_minutes,1)),
            kv("m4_m2_ratio",decimal(t.m4_m2_ratio,4)),
            kv("relative_phase",decimal(t.relative_phase,2)),
            kv("dominance",t.dominance)
        )
    )
    push!(
        summary,
        words(
            "datums",
            (kv(name,decimal(getproperty(t,name),3)) for name in (:mhhw,:mhw,:mtl,:dtl,:mlw,:mllw))...
        )
    )
    push!(summary,words("bounds",kv("hat",decimal(t.hat,3)),kv("lat",decimal(t.lat,3))))
    push!(
        summary,
        words(
            "window",
            kv("high_waters",length(t.highs)),
            kv("low_waters",length(t.lows)),
            kv("highest",decimal(t.highest.height,3)),
            kv("highest_time",minute_stamp(t.highest.rounded)),
            kv("lowest",decimal(t.lowest.height,3)),
            kv("lowest_time",minute_stamp(t.lowest.rounded))
        )
    )
    push!(
        summary,
        words(
            "daily_range",
            kv("widest",decimal(t.widest.range,3)),
            kv("widest_date",date(t.widest.day)),
            kv("narrowest",decimal(t.narrowest.range,3)),
            kv("narrowest_date",date(t.narrowest.day))
        )
    )
    push!(
        summary,
        words("exceedance",kv("above_mhhw",decimal(t.above_mhhw,2)),kv("below_mllw",decimal(t.below_mllw,2)))
    )
    for event in t.spring_neap
        push!(summary,words(event.kind,kv("time",minute_stamp(event.minute))))
    end
    push!(
        summary,
        words(
            "surges",
            kv("count",length(station.surges)),
            kv("threshold",decimal(settings.surge_threshold,3)),
            kv("min_hours",settings.surge_hours)
        )
    )
    for surge in station.surges
        push!(
            summary,
            words(
                "surge",
                kv("type",surge.kind),
                kv("start",stamp(surge.start)),
                kv("end",stamp(surge.stop)),
                kv("hours",surge.stop-surge.start+1),
                kv("peak",decimal(surge.value,4)),
                kv("peak_time",stamp(surge.peak))
            )
        )
    end
    d = station.daily_means
    push!(
        summary,
        words(
            "daily_mean",
            kv("days",d.days),
            kv("average",decimal(d.average,4)),
            kv("slope_mm_per_day",decimal(d.slope_mm_per_day,3)),
            kv("max",decimal(d.max.level,4)),
            kv("max_date",date(d.max.day)),
            kv("min",decimal(d.min.level,4)),
            kv("min_date",date(d.min.day))
        )
    )
    for row in d.rows
        push!(
            summary,
            words(
                "daily_mean",
                kv("date",date(row.day)),
                kv("level",decimal(row.level,4)),
                kv("filled",row.filled)
            )
        )
    end
    (cleaning=cleaning,constants=constants,extremes=extremes,summary=summary)
end
function nearest_lag(extrema,reference)
    average([e.rounded-argmin(r->(abs(r.rounded-e.rounded),r.rounded),reference).rounded for e in extrema])
end
function comparisons(stations,settings)
    reference = stations[settings.reference]
    lines = ["[comparison] reference=$(settings.reference)"]
    for station in settings.stations
        code = station.code
        code==settings.reference && continue
        own,ref = stations[code].characteristics,reference.characteristics
        push!(
            lines,
            words(
                code,
                "tide",
                kv("hw_lag_min",decimal(nearest_lag(own.highs,ref.highs),1)),
                kv("lw_lag_min",decimal(nearest_lag(own.lows,ref.lows),1)),
                kv("range_ratio",decimal(own.gt/ref.gt,4)),
                kv("mtl_diff",decimal(own.mtl-ref.mtl,3))
            )
        )
        for name in LEADING
            current,refc = stations[code].model.constants[name],reference.model.constants[name]
            phase = current.phase-refc.phase
            phase>180 && (phase-=360)
            phase<= -180 && (phase+=360)
            push!(
                lines,
                words(
                    code,
                    name,
                    kv("amplitude_ratio",decimal(current.amplitude/refc.amplitude,4)),
                    kv("phase_diff",decimal(phase,2)),
                    kv("time_lag_min",decimal(phase/current.speed*60,1))
                )
            )
        end
    end
    lines
end
function correlations(stations,order,max_lag)
    lines = ["[correlation] max_lag=$max_lag"]
    for i in 1:length(order)-1,j in i+1:length(order)
        a,b = stations[order[i]],stations[order[j]]
        by_lag = Dict{Int,Tuple{Float64,Int}}()
        for lag in -max_lag:max_lag
            pairs = [(
                a.residual.residuals[t],
                b.residual.residuals[t+lag]
            ) for t in a.cleaning.usable if haskey(b.residual.residuals,t+lag)]
            mx,my = average(first.(pairs)),average(last.(pairs))
            sxy = ordered_sum((x-mx)*(y-my) for (x,y) in pairs)
            sxx = ordered_sum((x-mx)*(x-mx) for (x,_) in pairs)
            syy = ordered_sum((y-my)*(y-my) for (_,y) in pairs)
            by_lag[lag] = (sxy/sqrt(sxx*syy),length(pairs))
        end
        best = argmin(lag->(-by_lag[lag][1],abs(lag),lag),-max_lag:max_lag)
        push!(
            lines,
            words(
                "$(order[i])-$(order[j])",
                kv("lag0",decimal(by_lag[0][1],4)),
                kv("best_lag",best),
                kv("best",decimal(by_lag[best][1],4)),
                kv("pairs",by_lag[best][2])
            )
        )
    end
    lines
end
function plot_lines(station,settings,start)
    width,top,bottom,step = settings.plot_hours,settings.plot_top,settings.plot_bottom,settings.plot_step
    rows = (top-bottom)÷step+1
    grid,marks = fill(' ',rows,width),Dict{Int,Char}()
    zero_row = floor(Int,(top-100*station.model.mean_level)/step+0.5)
    0<=zero_row<rows && (grid[zero_row+1,:].='-')
    for e in station.extrema
        column = fld(e.rounded-60start+30,60)
        0<=column<width && (marks[column]=e.kind=="high" ? 'H' : 'L')
    end
    for column in 0:width-1
        row = floor(Int,(top-100predict_height(station.model,start+column))/step+0.5)
        if row<0
            grid[1,column+1] = '^'
        elseif row>=rows
            grid[end,column+1] = 'v'
        else
            grid[row+1,column+1] = get(marks,column,'*')
        end
    end
    labels = [decimal((top-q*step)/100,2) for q in 0:rows-1]
    [words(
        "[plot]",
        kv("station",station.code),
        kv("start",datetime_at_hour(settings.epoch,start)),
        kv("hours",width),
        kv("step_cm",step)
    );render_plot(grid,labels)]
end
function main()
    input = read_all_inputs()
    settings,constituents = input.settings,input.constituents
    order = [station.code for station in settings.stations]
    start = epoch_hours(settings.epoch,settings.prediction_start)
    stations = Dict(station.code=>inspect_station(
        station,
        input.observations[station.code],
        constituents,
        settings,
        start
    ) for station in settings.stations)
    cleaning,constants,extremes,summary = String[],["station,constituent,speed,status,amplitude,phase,amplitude_error,phase_error,snr,significant"],String[],String[]
    for code in order
        lines = station_outputs(stations[code],constituents,settings)
        append!(cleaning,lines.cleaning)
        append!(constants,lines.constants)
        append!(extremes,lines.extremes)
        append!(summary,lines.summary)
    end
    predictions = ["time,"*join(order,",")]
    for i in 0:settings.prediction_hours
        push!(
            predictions,
            datetime_at_hour(settings.epoch,start+i)*","*join(
                (decimal(stations[code].hourly[i+1],3) for code in order),
                ","
            )
        )
    end
    append!(summary,comparisons(stations,settings))
    append!(summary,correlations(stations,order,settings.correlation_lag))
    append!(summary,plot_lines(stations[settings.plot_code],settings,start))
    for (name,lines) in [
        "cleaning.txt"=>cleaning,
        "constituents.csv"=>constants,
        "predictions.csv"=>predictions,
        "extremes.txt"=>extremes,
        "summary.txt"=>summary
    ]
        write_lines(name,lines)
    end
end
main()
