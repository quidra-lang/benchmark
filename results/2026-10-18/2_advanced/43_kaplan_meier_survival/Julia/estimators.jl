function risk_sets(subjects)
    times = sort(unique(s.time for s in subjects))
    risk = length(subjects)
    rows = NamedTuple[]
    for time in times
        events = count(s->s.time==time && s.event==1,subjects)
        censored = count(s->s.time==time && s.event==0,subjects)
        push!(rows,(time=time,risk=risk,events=events,censored=censored))
        risk -= events+censored
    end
    rows
end
function kaplan_meier(subjects)
    events = [r for r in risk_sets(subjects) if r.events>0]
    survival = 1.0
    greenwood = hazard = variance = 0.0
    rows = NamedTuple[]
    for (i,event) in enumerate(events)
        time,risk,deaths = event.time,event.risk,event.events
        survival *= (risk-deaths)/risk
        if risk==deaths
            greenwood = nothing
        elseif !isnothing(greenwood)
            greenwood += deaths/(risk*(risk-deaths))
        end
        if survival==0
            error = lower = upper = nothing
        else
            error = survival*sqrt(greenwood)
            logarithm = log(survival)
            omega = Z95*sqrt(greenwood)/(-logarithm)
            lower,upper = exp(logarithm*exp(omega)),exp(logarithm*exp(-omega))
        end
        hazard += deaths/risk
        variance += deaths/(risk*risk)
        next_time = i<length(events) ? events[i+1].time : nothing
        censored = count(s->s.event==0 && s.time>=time && (isnothing(next_time) || s.time<next_time),subjects)
        push!(rows,(time=time,risk=risk,events=deaths,censored=censored,survival=survival,
                    se=error,lower=lower,upper=upper,hazard=hazard,hazard_se=sqrt(variance)))
    end
    rows
end
function row_at(rows,time)
    for row in Iterators.reverse(rows)
        row.time<=time && return row
    end
    (survival=1.0,se=0.0,lower=nothing,upper=nothing,hazard=0.0,hazard_se=0.0)
end
function life_table(subjects,width,n)
    survival = 1.0
    variance = 0.0
    rows = NamedTuple[]
    for i in 0:n-1
        start,stop = i*width,(i+1)*width
        risk = count(s->s.time>=start,subjects)
        deaths = count(s->start<=s.time<stop && s.event==1,subjects)
        withdrawn = count(s->start<=s.time<stop && s.event==0,subjects)
        f = 2risk-withdrawn
        survival *= (f-2deaths)/f
        variance += 4deaths/(f*(f-2deaths))
        push!(rows,(start=start,stop=stop,risk=risk,events=deaths,withdrawn=withdrawn,exposed=f/2,
                    q=2deaths/f,survival=survival,se=survival*sqrt(variance),hazard=2000deaths/(width*(f-deaths))))
    end
    rows
end
