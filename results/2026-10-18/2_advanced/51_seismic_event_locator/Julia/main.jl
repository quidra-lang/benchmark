include("waveform_io.jl")
include("magnitude.jl")
include("picker.jl")
include("associator.jl")
include("locator.jl")
scaled(value,digits) = value<0 ? -floor(Int,-value*10^digits+0.5) : floor(Int,value*10^digits+0.5)
function decimal(value,digits)
    integer = scaled(value,digits)
    magnitude,scale = abs(integer),10^digits
    (integer<0 ? "-" : "")*"$(magnitude÷scale).$(lpad(magnitude%scale,digits,'0'))"
end
time_notation(sample) = "$(sample÷100).$(lpad(sample%100,2,'0'))"
station_ordered(picks) = sort(picks;by=p->p.station)
function observations(picks,stations,corrections=zeros(length(stations)))
    [(station=stations[p.station],time=p.sample/100-corrections[p.station]) for p in station_ordered(picks)]
end
function locate_candidates!(candidates,stations,params)
    events = NamedTuple[]
    for index in eachindex(candidates)
        candidate = candidates[index]
        initial = station_ordered(candidate.picks)
        first = run_location(observations(initial,stations),params)
        passes = [(picks=initial,run=first)]
        dropped = [(pick=p,error=r) for (p,r) in zip(
            initial,
            first.residuals
        ) if abs(r)>params["residual_limit"][1]]
        retained = [p for (p,r) in zip(initial,first.residuals) if abs(r)<=params["residual_limit"][1]]
        rejected = !isempty(dropped) && length(retained)<params["min_stations"][1]
        if rejected
            for p in initial
                p.state = "rejected"
            end
            event_number = 0
        else
            adopted = first
            if !isempty(dropped)
                adopted = run_location(observations(retained,stations),params)
                push!(passes,(picks=retained,run=adopted))
            end
            event_number = length(events)+1
            for (p,r) in zip(retained,adopted.residuals)
                p.state,p.event,p.first_residual = "used",event_number,r
            end
            for d in dropped
                d.pick.state,d.pick.event = "dropped",event_number
            end
            push!(events,(number=event_number,candidate=candidate.number,used=retained,first=adopted))
        end
        candidates[index] = (;candidate...,passes=passes,dropped=dropped,rejected=rejected,event=event_number)
    end
    events
end
function station_time_corrections(events,stations)
    values = [Float64[] for _ in stations]
    for event in events,p in event.used
        push!(values[p.station],p.first_residual)
    end
    [isempty(v) ? 0.0 : ordered_sum(v)/length(v) for v in values]
end
function quality_for_event(event,stations,params)
    solution,used,obs = event.final.solution,event.used,event.observations
    velocity = params["velocity"][1]
    ellipse = error_ellipse(solution,obs,velocity)
    x,y,z = solution[1:3]
    angles = Float64[]
    for p in used
        station = stations[p.station]
        angle = atan(station.x-x,station.y-y)*180/PI_VALUE
        push!(angles,angle<0 ? angle+360 : angle)
    end
    sort!(angles)
    gap = maximum(vcat(diff(angles),[angles[1]+360-angles[end]]))
    dmin = minimum(sqrt((stations[p.station].x-x)^2+(stations[p.station].y-y)^2) for p in used)
    fits(bounds) = gap<=bounds[1] && event.final.rms<=bounds[2] && ellipse.smaj<=bounds[3]
    grade = fits(params["quality_a"]) ? "A" : fits(params["quality_b"]) ? "B" : "C"
    first = event.first.solution
    dh,dz = sqrt((x-first[1])^2+(y-first[2])^2),z-first[3]
    jackknife = NamedTuple[]
    for (i,p) in enumerate(used)
        remaining = [o for (j,o) in enumerate(obs) if i!=j]
        alternative = geiger(solution,remaining,velocity).solution
        dx,dy,dz = alternative[1]-x,alternative[2]-y,alternative[3]-z
        push!(jackknife,(station=p.station,dx=dx,dy=dy,dz=dz,shift=sqrt(dx*dx+dy*dy)))
    end
    (
        ;ellipse...,
        gap=gap,
        dmin=dmin,
        grade=grade,
        dh=dh,
        dz=z-first[3],
        jackknife=jackknife,
        max_jack=jackknife[argmax([j.shift for j in jackknife])]
    )
end
function relocate_events!(events,stations,params,corrections)
    for i in eachindex(events)
        event = events[i]
        obs = observations(event.used,stations,corrections)
        start_rms = location_rms(event.first.solution,obs,params["velocity"][1])
        final = geiger(event.first.solution,obs,params["velocity"][1])
        for (p,r) in zip(event.used,final.residuals)
            p.residual = r
        end
        event = (;event...,observations=obs,start_rms=start_rms,final=final,solution=final.solution)
        events[i] = (;event...,quality=quality_for_event(event,stations,params))
    end
end
function compute_magnitudes!(events,stations,params)
    station_residuals = [Float64[] for _ in stations]
    for i in eachindex(events)
        event = events[i]
        magnitudes = [(
            ;per_pick_magnitude(p,distance(event.solution,stations[p.station])/1000,params)...,
            pick=p
        ) for p in event.used]
        local_values = [item.ml for item in magnitudes if !isnothing(item.ml)]
        ml = isempty(local_values) ? nothing : median_value(local_values)
        md = median_value([item.md for item in magnitudes])
        for item in magnitudes
            isnothing(item.ml) || push!(station_residuals[item.pick.station],item.ml-ml)
        end
        events[i] = (;event...,magnitudes=magnitudes,ml=ml,md=md)
    end
    corrections = [isempty(values) ? 0.0 : ordered_sum(values)/length(values) for values in station_residuals]
    for i in eachindex(events)
        event = events[i]
        corrected = [item.ml-corrections[item.pick.station] for item in event.magnitudes if !isnothing(item.ml)]
        events[i] = (;event...,ml_corrected=isempty(corrected) ? nothing : median_value(corrected))
    end
    corrections,station_residuals
end
function travel_time_regression(events,stations,params)
    points = [(
        distance(event.solution,stations[p.station])/1000,
        p.sample/100-event.solution[4]
    ) for event in events for p in event.used]
    n = length(points)
    sd,st = ordered_sum(d for (d,t) in points),ordered_sum(t for (d,t) in points)
    sdd,sdt = ordered_sum(d*d for (d,t) in points),ordered_sum(d*t for (d,t) in points)
    slope = (n*sdt-sd*st)/(n*sdd-sd*sd)
    intercept = (st-slope*sd)/n
    error = ordered_sum((t-intercept-slope*d)^2 for (d,t) in points)
    (n=n,velocity=1000/slope,intercept=intercept,rms=sqrt(error/n))
end
function cluster_events!(events,params)
    n = length(events)
    neighbors = [Int[] for _ in 1:n]
    dlimit,tlimit = params["cluster"]
    for i in 1:n-1,j in i+1:n
        a,b = events[i].solution,events[j].solution
        if abs(a[4]-b[4])<=tlimit && sqrt(ordered_sum((a[k]-b[k])^2 for k in 1:3))<=dlimit
            push!(neighbors[i],j)
            push!(neighbors[j],i)
        end
    end
    seen,clusters = falses(n),NamedTuple[]
    for start in 1:n
        seen[start] && continue
        queue = [start]
        seen[start] = true
        cursor = 1
        while cursor<=length(queue)
            current = queue[cursor]
            cursor += 1
            for other in neighbors[current]
                if !seen[other]
                    seen[other] = true
                    push!(queue,other)
                end
            end
        end
        members = sort(queue)
        number = length(clusters)+1
        for i in members
            events[i] = (;events[i]...,cluster=number)
        end
        center = [ordered_sum(events[i].solution[k] for i in members)/length(members) for k in 1:3]
        origins = [events[i].solution[4] for i in members]
        push!(clusters,(number=number,members=members,center=center,span=maximum(origins)-minimum(origins)))
    end
    clusters
end
function reassociate!(picks,events,stations,corrections,params)
    station_sets = [Set(p.station for p in event.used) for event in events]
    added = Pick[]
    for pick in picks
        pick.state=="unassociated" || continue
        choices = Tuple{Float64,Int,Float64}[]
        for event in events
            pick.station in station_sets[event.number] && continue
            rho = pick.sample/100-event.solution[4]-distance(
                event.solution,
                stations[pick.station]
            )/params["velocity"][1]-corrections[pick.station]
            abs(rho)<=params["residual_limit"][1] && push!(choices,(abs(rho),event.number,rho))
        end
        isempty(choices) && continue
        _,number,rho = minimum(choices)
        pick.state,pick.event,pick.residual = "added",number,rho
        push!(station_sets[number],pick.station)
        push!(added,pick)
    end
    added
end
function magnitude_relation(events)
    available = [event for event in events if !isnothing(event.ml)]
    n = length(available)
    x,y = [event.md for event in available],[event.ml for event in available]
    xm,ym = ordered_sum(x)/n,ordered_sum(y)/n
    xx = ordered_sum((value-xm)^2 for value in x)
    xy = ordered_sum((a-xm)*(b-ym) for (a,b) in zip(x,y))
    yy = ordered_sum((value-ym)^2 for value in y)
    slope = xy/xx
    (n=n,slope=slope,intercept=ym-slope*xm,r=xy/sqrt(xx*yy),mean_diff=ym-xm)
end
function picks_report(picks,stations)
    lines = ["station,sample,time_s,duration,snr,amplitude,clipped,event,status,residual"]
    for p in picks
        error = p.state in ("used","added") ? decimal(p.residual,4) : "-"
        event = p.state in ("used","dropped","added") ? p.event : 0
        push!(
            lines,
            "$(stations[p.station].code),$(p.sample),$(time_notation(p.sample)),$(p.duration),$(decimal(p.ratio,2)),$(p.amplitude),$(p.clipped ? "yes" : "no"),$event,$(p.state),$error"
        )
    end
    lines
end
function format_solution(label,solution,rms,index=0)
    prefix = label*(index==0 ? "" : " $index")
    x,y,z,t0 = solution
    "$prefix x=$(decimal(x,1)) y=$(decimal(y,1)) z=$(decimal(z,1)) t0=$(decimal(t0,3)) rms=$(decimal(rms,4))"
end
function pass_lines(number,picks,run,stations,velocity)
    lines = ["PASS $number stations="*join((stations[p.station].code for p in picks),","),format_solution("GRID",run.grid.solution,run.grid.rms),
        "PROFILE "*join((decimal(v,4) for v in run.grid.profile)," ")]
    append!(lines,[format_solution("ITER",record.solution,record.rms,record.number) for record in run.trace])
    for (p,r) in zip(picks,run.residuals)
        d = distance(run.solution,stations[p.station])
        push!(
            lines,
            "RES $(stations[p.station].code) dist=$(decimal(d,1)) tt=$(decimal(d/velocity,4)) obs=$(time_notation(p.sample)) res=$(decimal(r,4))"
        )
    end
    lines
end
function locations_report(picks,candidates,events,stations,corrections,fit,clusters,added,params)
    lines = String[]
    velocity = params["velocity"][1]
    for candidate in candidates
        push!(
            lines,
            "CANDIDATE $(candidate.number) picks=$(length(candidate.picks)) first=$(time_notation(candidate.first.sample))"
        )
        append!(lines,pass_lines(1,candidate.passes[1].picks,candidate.passes[1].run,stations,velocity))
        for item in candidate.dropped
            push!(lines,"DROP $(stations[item.pick.station].code) res=$(decimal(item.error,4))")
        end
        if candidate.rejected
            push!(lines,"RESULT REJECTED stations=$(length(candidate.picks)-length(candidate.dropped))")
        else
            if length(candidate.passes)==2
                append!(
                    lines,
                    pass_lines(2,candidate.passes[2].picks,candidate.passes[2].run,stations,velocity)
                )
            end
            push!(lines,"RESULT EVENT $(candidate.event)")
        end
    end
    push!(lines,"CORRECTIONS")
    for (s,station) in enumerate(stations)
        n = count(p->p.state=="used" && p.station==s,picks)
        push!(lines,"$(station.code) n=$n correction=$(decimal(corrections[s],4))")
    end
    for event in events
        q,final = event.quality,event.final
        push!(lines,"EVENT $(event.number)",format_solution("START",event.first.solution,event.start_rms))
        append!(
            lines,
            [format_solution("ITER",record.solution,record.rms,record.number) for record in final.trace]
        )
        for p in event.used
            d = distance(event.solution,stations[p.station])
            push!(
                lines,
                "RES $(stations[p.station].code) dist=$(decimal(d,1)) tt=$(decimal(d/velocity,4)) obs=$(time_notation(p.sample)) corr=$(decimal(corrections[p.station],4)) res=$(decimal(p.residual,4))"
            )
        end
        push!(lines,"ELLIPSE smaj=$(decimal(q.smaj,1)) smin=$(decimal(q.smin,1)) az=$(decimal(q.az,1)) erz=$(decimal(q.erz,1)) ert=$(decimal(q.ert,4))",
            "SHIFT dh=$(decimal(q.dh,1)) dz=$(decimal(q.dz,1))","GAP $(decimal(q.gap,1)) DMIN $(decimal(q.dmin,1)) QUALITY $(q.grade)")
        for j in q.jackknife
            push!(
                lines,
                "JACK $(stations[j.station].code) dx=$(decimal(j.dx,1)) dy=$(decimal(j.dy,1)) dz=$(decimal(j.dz,1)) shift=$(decimal(j.shift,1))"
            )
        end
        push!(
            lines,
            "JACKKNIFE max=$(decimal(q.max_jack.shift,1)) station=$(stations[q.max_jack.station].code)"
        )
    end
    push!(
        lines,
        "FIT n=$(fit.n) velocity=$(decimal(fit.velocity,1)) intercept=$(decimal(fit.intercept,4)) rms=$(decimal(fit.rms,4))"
    )
    for cluster in clusters
        length(cluster.members)<2 && continue
        x,y,z = cluster.center
        push!(
            lines,
            "CLUSTER $(cluster.number) events=$(join(cluster.members,",")) x=$(decimal(x,1)) y=$(decimal(y,1)) z=$(decimal(z,1)) span=$(decimal(cluster.span,3))"
        )
    end
    push!(lines,"ADDED")
    for p in added
        push!(
            lines,
            "$(stations[p.station].code) sample=$(p.sample) event=$(p.event) res=$(decimal(p.residual,4))"
        )
    end
    depths = [event.solution[3] for event in events]
    push!(lines,"SUMMARY picks=$(length(picks)) candidates=$(length(candidates)) events=$(length(events)) rejected=$(count(c->c.rejected,candidates)) unassociated=$(count(p->p.state=="unassociated",picks))",
        "DEPTH min=$(decimal(minimum(depths),1)) median=$(decimal(median_value(depths),1)) max=$(decimal(maximum(depths),1))",
        "QUALITY A=$(count(e->e.quality.grade=="A",events)) B=$(count(e->e.quality.grade=="B",events)) C=$(count(e->e.quality.grade=="C",events)) mean_rms=$(decimal(ordered_sum(e.final.rms for e in events)/length(events),4))")
    lines
end
optional_magnitude(value) = isnothing(value) ? "-" : decimal(value,2)
function catalog_report(events)
    lines = ["event,origin_time,x,y,depth,rms,stations,gap,dmin,smaj,smin,azimuth,erz,ml,md,quality,cluster"]
    for event in events
        x,y,z,t0 = event.solution
        q = event.quality
        fields = [string(event.number),decimal(t0,3),decimal(x,1),decimal(y,1),decimal(z,1),decimal(event.final.rms,4),string(length(event.used)),
            decimal(q.gap,1),decimal(q.dmin,1),decimal(q.smaj,1),decimal(q.smin,1),decimal(q.az,1),decimal(q.erz,1),optional_magnitude(event.ml),decimal(
                event.md,
                2
            ),q.grade,string(event.cluster)]
        push!(lines,join(fields,","))
    end
    lines
end
function frame_lines(rows)
    border = "+"*repeat("-",size(rows,2))*"+"
    vcat([border],["|"*join(rows[r,:])*"|" for r in axes(rows,1)],[border])
end
function timeline_lines(events,params)
    duration,width,low,high,height = Int.(params["timeline"])
    rows = fill(' ',height,width)
    for event in events
        isnothing(event.ml) && continue
        t,h = scaled(event.solution[4],3),magnitude_hundredths(event.ml)
        (0<=t<1000duration && h>=100low) || continue
        column = fld(t*width,1000duration)
        level = min(fld((h-100low)*height,100*(high-low)),height-1)
        for k in 0:level
            r = height-k
            if k==level
                rows[r,column+1] = 'o'
            elseif rows[r,column+1]==' '
                rows[r,column+1] = '|'
            end
        end
    end
    vcat(["TIMELINE t=0..$duration ML=$low..$high"],frame_lines(rows))
end
function magnitudes_report(events,statistics,relation,stations,params)
    lines = String[]
    for event in events
        available = count(item->!isnothing(item.ml),event.magnitudes)
        push!(
            lines,
            "EVENT $(event.number) ML=$(optional_magnitude(event.ml)) n=$available MD=$(decimal(event.md,2))"
        )
        for item in event.magnitudes
            p = item.pick
            prefix = "$(stations[p.station].code) r=$(decimal(item.r,3)) amp=$(p.amplitude) "
            detail = isnothing(item.ml) ? "clipped" : "ml=$(decimal(item.ml,2)) res=$(decimal(item.ml-event.ml,2))"
            push!(lines,prefix*detail*" dur=$(p.duration) md=$(decimal(item.md,2))")
        end
    end
    push!(lines,"CORRECTED")
    append!(lines,["EVENT $(e.number) MLC=$(optional_magnitude(e.ml_corrected))" for e in events])
    push!(lines,"FMD")
    counts = statistics.counts
    for t in minimum(keys(counts)):maximum(keys(counts))
        cumulative = sum(value for (class,value) in counts if class>=t)
        push!(lines,"M=$(magnitude_class(t)) N=$(get(counts,t,0)) CUM=$cumulative")
    end
    push!(lines,"MC $(magnitude_class(statistics.completeness))","BVALUE $(decimal(statistics.b,3)) SIGMA $(decimal(statistics.sigma,3)) N $(statistics.nb)",
        "AVALUE $(decimal(statistics.a,3))","MLMD n=$(relation.n) slope=$(decimal(relation.slope,3)) intercept=$(decimal(relation.intercept,3)) r=$(decimal(relation.r,3)) mean_diff=$(decimal(relation.mean_diff,3))")
    append!(lines,timeline_lines(events,params))
    lines
end
function stations_report(
    stations,
    statistics,
    picks,
    events,
    time_corrections,
    magnitude_corrections,
    magnitude_residuals
)
    lines = String[]
    for (s,station) in enumerate(stations)
        stats = statistics[s]
        local_picks = [p for p in picks if p.station==s]
        used = [p for event in events for p in event.used if p.station==s]
        before = isempty(used) ? "-" : decimal(
            sqrt(ordered_sum(p.first_residual^2 for p in used)/length(used)),
            4
        )
        after = isempty(used) ? "-" : decimal(sqrt(ordered_sum(p.residual^2 for p in used)/length(used)),4)
        states = join(
            ("$name=$(count(p->p.state==name,local_picks))" for name in (
                "used",
                "dropped",
                "added",
                "rejected",
                "unassociated"
            )),
            " "
        )
        push!(lines,"STATION $(station.code) x=$(station.x) y=$(station.y) elevation=$(station.elevation)",
            "SAMPLES start=$(station.start) count=$(length(station.samples)) mean=$(stats.mean) noise=$(decimal(stats.noise,1)) peak=$(stats.peak) clipped=$(stats.clipped)",
            "TRIGGERS total=$(stats.triggers) short=$(stats.short) picks=$(length(local_picks))","PICKS $states",
            "RESIDUALS n=$(length(used)) rms=$before correction=$(decimal(time_corrections[s],4)) after=$after",
            "MAGNITUDES n=$(length(magnitude_residuals[s])) correction=$(decimal(magnitude_corrections[s],2))")
    end
    lines
end
function event_symbol(event)
    isnothing(event.ml) && return '?'
    h = magnitude_hundredths(event.ml)
    h<100 ? '.' : h<200 ? 'o' : h<300 ? 'O' : '@'
end
function map_position(x,y,params)
    left,right,bottom,top = Int.(params["map_area"])
    width,height = Int.(params["map_size"])
    10left<=x<10right && 10bottom<=y<10top || return nothing
    (fld((x-10left)*width,10*(right-left)),height-1-fld((y-10bottom)*height,10*(top-bottom)))
end
function plotted_positions(event,params)
    x,y,z = scaled.(event.solution[1:3],1)
    left,right,bottom,top = Int.(params["map_area"])
    width = Int(params["map_size"][1])
    limit,height = Int.(params["section"])
    row = fld(z*height,10limit)
    ew = 10left<=x<10right && z<10limit ? (fld((x-10left)*width,10*(right-left)),row) : nothing
    ns = 10bottom<=y<10top && z<10limit ? (fld((y-10bottom)*width,10*(top-bottom)),row) : nothing
    (map=map_position(x,y,params),ew=ew,ns=ns)
end
function place_point!(rows,position,symbol)
    isnothing(position) && return
    c,r = position
    priority = Dict(' '=>-1,'?'=>0,'.'=>1,'o'=>2,'O'=>3,'@'=>4,'^'=>5)
    priority[symbol]>priority[rows[r+1,c+1]] && (rows[r+1,c+1]=symbol)
end
position_text(position) = isnothing(position) ? "outside" : "$(position[1]),$(position[2])"
function map_report(events,stations,params)
    left,right,bottom,top = Int.(params["map_area"])
    width,height = Int.(params["map_size"])
    limit,section_height = Int.(params["section"])
    map,ew,ns = fill(' ',height,width),fill(' ',section_height,width),fill(' ',section_height,width)
    locations = [plotted_positions(event,params) for event in events]
    for (event,position) in zip(events,locations)
        symbol = event_symbol(event)
        place_point!(map,position.map,symbol)
        place_point!(ew,position.ew,symbol)
        place_point!(ns,position.ns,symbol)
    end
    station_locations = [map_position(10station.x,10station.y,params) for station in stations]
    for position in station_locations
        place_point!(map,position,'^')
    end
    lines = String[]
    for (heading,rows) in (
        ("MAP x=$left..$right y=$bottom..$top",map),
        ("SECTION EW x=$left..$right z=0..$limit",ew),
        ("SECTION NS y=$bottom..$top z=0..$limit",ns)
    )
        push!(lines,heading)
        append!(lines,frame_lines(rows))
    end
    push!(lines,"LEGEND ^ station . ML<1 o ML<2 O ML<3 @ ML>=3 ? no ML")
    append!(
        lines,
        ["STATION $(station.code) map=$(position_text(position))" for (station,position) in zip(
            stations,
            station_locations
        )]
    )
    for (event,position) in zip(events,locations)
        push!(
            lines,
            "EVENT $(event.number) $(event_symbol(event)) map=$(position_text(position.map)) ew=$(position_text(position.ew)) ns=$(position_text(position.ns))"
        )
    end
    lines
end
function main()
    stations,params = load_inputs()
    picks,station_statistics = Pick[],NamedTuple[]
    for station in stations
        detected,stats = detect_station(station,params)
        append!(picks,detected)
        push!(station_statistics,stats)
    end
    sort!(picks;by=p->(p.sample,p.station))
    candidates = associate(picks,Int(params["association_window"][1]),Int(params["min_stations"][1]))
    events = locate_candidates!(candidates,stations,params)
    time_corrections = station_time_corrections(events,stations)
    relocate_events!(events,stations,params,time_corrections)
    magnitude_corrections,magnitude_residuals = compute_magnitudes!(events,stations,params)
    fit = travel_time_regression(events,stations,params)
    clusters = cluster_events!(events,params)
    added = reassociate!(picks,events,stations,time_corrections,params)
    statistics = frequency_statistics([event.ml for event in events if !isnothing(event.ml)])
    relation = magnitude_relation(events)
    reports = [("picks.csv",picks_report(picks,stations)),("locations.txt",locations_report(picks,candidates,events,stations,time_corrections,fit,clusters,added,params)),
        ("catalog.csv",catalog_report(events)),(
            "magnitudes.txt",
            magnitudes_report(events,statistics,relation,stations,params)
        ),
        (
            "stations.txt",
            stations_report(
                stations,
                station_statistics,
                picks,
                events,
                time_corrections,
                magnitude_corrections,
                magnitude_residuals
            )
        ),("map.txt",map_report(events,stations,params))]
    for (name,lines) in reports
        open(joinpath("output",name),"w") do io
            for line in lines
                println(io,line)
            end
        end
    end
end
main()
