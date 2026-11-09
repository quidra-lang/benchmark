include("flight_plans.jl")
include("trajectory.jl")
include("conflict.jl")
include("resolution.jl")
include("report.jl")

const TRAFFIC_PI = 3.141592653589793
words(parts...) = join(string.(parts)," ")
attributes(items::Pair...) = join(["$(first(p))=$(last(p))" for p in items]," ")
sample_times(params) = collect(params.sample_start:60:params.sample_end-1)
pair_name(plans,pair) = join([plans[i].callsign for i in pair],"-")
function ordered_total(items)
    result = 0.0
    for value in items
        result += value
    end
    result
end
function find_blocker(changed,new_trajectory,partner,trajectories,unresolved,start,params)
    blockers = NamedTuple[]
    for other in eachindex(trajectories)
        other==changed && continue
        a,b = minmax(changed,other)
        (a,b) in unresolved && continue
        first = a==changed ? new_trajectory : trajectories[a]
        second = b==changed ? new_trajectory : trajectories[b]
        for conflict in pair_conflicts(a,first,b,second,params.dh,params.dv)
            (other==partner || conflict.start<start+params.lookahead) && push!(blockers,conflict)
        end
    end
    isempty(blockers) ? nothing : argmin(c->(c.start,c.pair...),blockers)
end
function resolve_conflicts(initial,types,params)
    plans = copy(initial)
    trajectories = [build_trajectory(plan,types) for plan in plans]
    unresolved,resolved = Set{Tuple{Int,Int}}(),Set{Tuple{Int,Int}}()
    rounds,unresolved_conflicts = NamedTuple[],NamedTuple[]
    while true
        conflicts = all_conflicts(trajectories,params.dh,params.dv)
        index = findfirst(c->!(c.pair in unresolved),conflicts)
        isnothing(index) && break
        target = conflicts[index]
        a,b = target.pair
        first,second = priority_order(plans[a],plans[b],a,b)
        trials,accepted = NamedTuple[],nothing
        for (aircraft,partner) in ((first,second),(second,first))
            !isnothing(accepted) && break
            for (name,amount) in manoeuvres(params.max_delay)
                proposal = propose(plans[aircraft],name,amount,types,params)
                blocker = nothing
                if isnothing(proposal)
                    status = "infeasible"
                else
                    new_trajectory = build_trajectory(proposal,types)
                    blocker = find_blocker(
                        aircraft,
                        new_trajectory,
                        partner,
                        trajectories,
                        unresolved,
                        target.start,
                        params
                    )
                    status = isnothing(blocker) ? "accepted" : "blocked"
                    if status=="accepted"
                        push!(proposal.history,name)
                        plans[aircraft],trajectories[aircraft] = proposal,new_trajectory
                    end
                end
                entry = (;aircraft,name,status,blocker)
                push!(trials,entry)
                if status=="accepted"
                    accepted = entry
                    break
                end
            end
        end
        if isnothing(accepted)
            push!(unresolved,target.pair)
            push!(unresolved_conflicts,target)
        else
            push!(resolved,target.pair)
        end
        push!(rounds,(number=length(rounds)+1,target=target,trials=trials,accepted=accepted))
    end
    (;plans,trajectories,rounds,unresolved,resolved,unresolved_conflicts)
end
function segment_track(segment)
    vx,vy,_ = segment.velocity
    angle = atan(vx,vy)*180/TRAFFIC_PI
    angle<0 ? angle+360 : angle
end
function sector_contains(sector,point)
    x,y,z = point
    sector.x1/10<=x<sector.x2/10 && sector.y1/10<=y<sector.y2/10 && sector.lower*100<=z<sector.upper*100
end
function classify_conflicts(conflicts,sectors,final_pairs,resolved,dh,final=false)
    [begin
        piece = c.closest
        a,b = piece.a_segment,piece.b_segment
        pa,pb = segment_position(a,piece.tc),segment_position(b,piece.tc)
        ta,tb = segment_track(a),segment_track(b)
        angle = abs(ta-tb)
        angle>180 && (angle=360-angle)
        dot = a.velocity[1]*b.velocity[1]+a.velocity[2]*b.velocity[2]
        cross = a.velocity[1]*b.velocity[2]-a.velocity[2]*b.velocity[1]
        geometry = dot*dot>cross*cross ? (dot<0 ? "head_on" : "trailing") : "crossing"
        severity = 10*piece.distance<4dh ? "HIGH" : 10*piece.distance<7dh ? "MEDIUM" : "LOW"
        midpoint = ntuple(i->(pa[i]+pb[i])/2,3)
        sector = findfirst(s->sector_contains(s,midpoint),sectors)
        sector_name = isnothing(sector) ? "-" : sectors[sector].name
        outcome = final || c.pair in final_pairs ? "remaining" : c.pair in resolved ? "resolved" : "indirect"
        (
            ;c...,
            level_a=pa[3]/100,
            level_b=pb[3]/100,
            track_a=ta,
            track_b=tb,
            angle,
            geometry,
            severity,
            sector=sector_name,
            outcome
        )
    end for c in conflicts]
end
active_conflicts(conflicts,time) = [c for c in conflicts if c.start<=time<c.finish]
function trajectories_csv(plans,trajectories)
    lines = ["callsign,segment,leg,phase,t_start,t_end,x_start,y_start,fl_start,x_end,y_end,fl_end"]
    for (plan,t) in zip(plans,trajectories),s in t.segments
        push!(lines,join(string.([plan.callsign,s.number,s.leg,s.phase,decimal(s.ts),decimal(s.te),decimal(s.start[1]),decimal(s.start[2]),
            round(Int,s.start[3]/100),decimal(s.finish[1]),decimal(s.finish[2]),round(
                Int,
                s.finish[3]/100
            )]),','))
    end
    lines
end
function conflict_lines(label,plans,conflicts,trajectories,params)
    lines = ["CONFLICTS "*attributes("plan"=>label,"count"=>length(conflicts))]
    for (i,c) in enumerate(conflicts)
        p = c.closest
        push!(
            lines,
            words(
                "CONFLICT",
                i,
                pair_name(plans,c.pair),
                attributes(
                    "start"=>decimal(c.start),
                    "end"=>decimal(c.finish),
                    "duration"=>decimal(c.finish-c.start),
                    "outcome"=>c.outcome
                )
            )
        )
        push!(lines,"  CPA "*attributes("t"=>decimal(p.tc),"dist"=>decimal(p.distance),"vert"=>decimal(p.vertical,1),
            "levels"=>"$(decimal(c.level_a,2))/$(decimal(c.level_b,2))","tracks"=>"$(decimal(c.track_a,1))/$(decimal(c.track_b,1))","angle"=>decimal(
                c.angle,
                1
            )))
        push!(lines,"  TYPE "*attributes("geometry"=>c.geometry,"phases"=>"$(p.a_segment.phase)/$(p.b_segment.phase)",
            "segments"=>"$(p.a_segment.number)/$(p.b_segment.number)","sector"=>c.sector,"severity"=>c.severity))
        for piece in c.pieces
            push!(
                lines,
                "  PIECE "*words(
                    "$(piece.a_segment.number)/$(piece.b_segment.number)",
                    decimal(piece.lo),
                    decimal(piece.hi)
                )
            )
        end
    end
    closest = isempty(conflicts) ? "-" : decimal(minimum(c.closest.distance for c in conflicts))
    push!(lines,"SUMMARY "*attributes("count"=>length(conflicts),"total"=>decimal(ordered_total(c.finish-c.start for c in conflicts)),"min_dist"=>closest,
        "head_on"=>count(c->c.geometry=="head_on",conflicts),"crossing"=>count(
            c->c.geometry=="crossing",
            conflicts
        ),"trailing"=>count(
            c->c.geometry=="trailing",
            conflicts
        ),
        "high"=>count(c->c.severity=="HIGH",conflicts),"medium"=>count(
            c->c.severity=="MEDIUM",
            conflicts
        ),"low"=>count(c->c.severity=="LOW",conflicts)))
    involved = [i for i in eachindex(plans) if any(c->i in c.pair,conflicts)]
    for i in involved
        matching = [c for c in conflicts if i in c.pair]
        partners = sort!(unique([p for c in matching for p in c.pair if p!=i]))
        push!(
            lines,
            words(
                "FLIGHT",
                plans[i].callsign,
                attributes(
                    "conflicts"=>length(matching),
                    "first"=>decimal(minimum(c.start for c in matching)),
                    "partners"=>join([plans[p].callsign for p in partners],',')
                )
            )
        )
    end
    push!(lines,"TIMELINE "*attributes("from"=>params.sample_start,"to"=>params.sample_end,"step"=>60))
    for i in involved
        symbols = [isnothing(active_segment(trajectories[i],t)) ? '.' : any(
            c->i in c.pair && c.start<=t<c.finish,
            conflicts
        ) ? 'X' : '-' for t in sample_times(params)]
        push!(lines,plans[i].callsign*" "*join(symbols))
    end
    lines
end
history_text(plan) = isempty(plan.history) ? "-" : join(plan.history,',')
function resolution_lines(initial,final,ti,tf,ci,cf,resolution)
    lines = String[]
    for record in resolution.rounds
        c = record.target
        push!(
            lines,
            words(
                "ROUND",
                record.number,
                pair_name(initial,c.pair),
                attributes(
                    "start"=>decimal(c.start),
                    "end"=>decimal(c.finish),
                    "dist"=>decimal(c.closest.distance)
                )
            )
        )
        for trial in record.trials
            line = "  TRY "*words(initial[trial.aircraft].callsign,trial.name,trial.status)
            if trial.status=="blocked"
                line *= " "*words(pair_name(initial,trial.blocker.pair),"start="*decimal(trial.blocker.start))
            end
            push!(lines,line)
        end
        push!(
            lines,
            isnothing(record.accepted) ? "  RESULT unresolved" : "  RESULT resolved "*words(
                initial[record.accepted.aircraft].callsign,
                record.accepted.name
            )
        )
    end
    total_extra = 0.0
    for i in eachindex(initial)
        old,new = initial[i],final[i]
        extra = tf[i].arrival-ti[i].arrival
        total_extra += extra
        push!(lines,words("FLIGHT",new.callsign,attributes("departure"=>new.departure+new.delay,"delay"=>new.delay,"level"=>signed_integer(new.offset),
            "speed"=>"$(old.speed)->$(new.speed)","arrival"=>"$(decimal(ti[i].arrival))->$(decimal(tf[i].arrival))","extra"=>decimal(extra),"length"=>decimal(tf[i].length),
            "conflicts"=>"$(count(c->i in c.pair,ci))->$(count(c->i in c.pair,cf))","manoeuvres"=>history_text(new))))
    end
    for c in resolution.unresolved_conflicts
        push!(
            lines,
            words(
                "UNRESOLVED",
                pair_name(initial,c.pair),
                attributes("start"=>decimal(c.start),"dist"=>decimal(c.closest.distance))
            )
        )
    end
    attempts = [t for r in resolution.rounds for t in r.trials]
    accepted = [r.accepted for r in resolution.rounds if !isnothing(r.accepted)]
    push!(lines,"TOTAL "*attributes("rounds"=>length(resolution.rounds),"resolved"=>length(accepted),"unresolved"=>length(resolution.unresolved_conflicts),
        "level"=>count(
            t->startswith(t.name,"level_"),
            accepted
        ),"speed"=>count(t->t.name=="speed_down",accepted),"delay"=>count(
            t->startswith(t.name,"delay_"),
            accepted
        ),
        "total_delay"=>sum(p.delay for p in final),"total_extra"=>decimal(total_extra),"trials"=>length(attempts),"infeasible"=>count(
            t->t.status=="infeasible",
            attempts
        ),"blocked"=>count(t->t.status=="blocked",attempts)))
    lines
end
function inside_segment_sector(segment,sector)
    limits = ((sector.x1/10,sector.x2/10),(sector.y1/10,sector.y2/10),(sector.lower*100,sector.upper*100))
    lo,hi = segment.ts,segment.te
    for i in 1:3
        low,high = limits[i]
        p,v = segment.start[i],segment.velocity[i]
        if v==0
            low<=p<high || return nothing
        else
            r1,r2 = (low-p)/v,(high-p)/v
            lo,hi = max(lo,segment.ts+min(r1,r2)),min(hi,segment.ts+max(r1,r2))
        end
    end
    hi-lo>1e-6 ? (lo,hi) : nothing
end
function sector_transits(trajectories,sectors)
    all_transits = NamedTuple[]
    for (aircraft,t) in enumerate(trajectories)
        transits = NamedTuple[]
        for (sector,s) in enumerate(sectors)
            combined = Tuple{Float64,Float64}[]
            for segment in t.segments
                interval = inside_segment_sector(segment,s)
                isnothing(interval) && continue
                lo,hi = interval
                if !isempty(combined) && lo-combined[end][2]<=1e-6
                    combined[end] = (combined[end][1],hi)
                else
                    push!(combined,(lo,hi))
                end
            end
            for (entry,exit) in combined
                push!(transits,(aircraft=aircraft,sector=sector,entry=entry,exit=exit,previous=0,next=0))
            end
        end
        sort!(transits;by=t->(t.entry,t.sector))
        for i in 1:length(transits)-1
            if abs(transits[i+1].entry-transits[i].exit)<=1e-6
                transits[i] = (;transits[i]...,next=transits[i+1].sector)
                transits[i+1] = (;transits[i+1]...,previous=transits[i].sector)
            end
        end
        append!(all_transits,transits)
    end
    all_transits
end
sector_name(sectors,i) = i==0 ? "-" : sectors[i].name
function transit_lines(plans,sectors,transits)
    lines = ["callsign,sector,entry,exit,duration,from,to"]
    for t in transits
        push!(
            lines,
            join(
                [
                    plans[t.aircraft].callsign,
                    sectors[t.sector].name,
                    decimal(t.entry),
                    decimal(t.exit),
                    decimal(t.exit-t.entry),
                    sector_name(sectors,t.previous),
                    sector_name(sectors,t.next)
                ],
                ','
            )
        )
    end
    lines
end
function occupancy_table(trajectories,sectors,times)
    result = zeros(Int,length(sectors),length(times))
    for (i,time) in enumerate(times),trajectory in trajectories
        observed = current_position(trajectory,time)
        isnothing(observed) && continue
        for (j,sector) in enumerate(sectors)
            sector_contains(sector,observed.point) && (result[j,i]+=1)
        end
    end
    result
end
function period_table(sectors,times,oi,of,ti,tf)
    rows = NamedTuple[]
    for (sector,s) in enumerate(sectors),i in 1:5:length(times)
        first,last = times[i],times[i]+300
        initial_peak,final_peak = maximum(oi[sector,i:i+4]),maximum(of[sector,i:i+4])
        initial_entries = count(t->t.sector==sector && first<=t.entry<last,ti)
        final_entries = count(t->t.sector==sector && first<=t.entry<last,tf)
        status = final_peak>s.capacity ? "OVER" : initial_peak>s.capacity ? "RELIEVED" : "OK"
        push!(rows,(sector=sector,period=(i-1)÷5+1,start=first,finish=last,initial_entries=initial_entries,final_entries=final_entries,
            initial_peak=initial_peak,final_peak=final_peak,mean=sum(of[
                sector,
                i:i+4
            ])/5,capacity=s.capacity,status=status))
    end
    rows
end
function sector_load_lines(sectors,periods)
    lines = ["sector,period,start,end,entries_initial,entries_final,peak_initial,peak_final,mean_final,capacity,status"]
    for p in periods
        push!(
            lines,
            join(
                string.([
                    sectors[p.sector].name,
                    p.period,
                    p.start,
                    p.finish,
                    p.initial_entries,
                    p.final_entries,
                    p.initial_peak,
                    p.final_peak,
                    decimal(p.mean,1),
                    p.capacity,
                    p.status
                ]),
                ','
            )
        )
    end
    lines
end
function level_usage(trajectories)
    usage = Dict{Int,NamedTuple}()
    for (aircraft,t) in enumerate(trajectories),s in t.segments
        s.phase=="LVL" || continue
        level = round(Int,s.start[3]/100)
        entry = get(usage,level,(flights=Set{Int}(),time=0.0))
        push!(entry.flights,aircraft)
        usage[level] = (flights=entry.flights,time=entry.time+(s.te-s.ts))
    end
    usage
end
function sector_report(sectors,times,oi,of,ti,tf,ci,cf,trajectories_initial,trajectories_final)
    lines = String[]
    for (i,s) in enumerate(sectors)
        push!(
            lines,
            words(
                "SECTOR",
                s.name,
                attributes(
                    "x"=>"$(s.x1)..$(s.x2)",
                    "y"=>"$(s.y1)..$(s.y2)",
                    "fl"=>"$(s.lower)..$(s.upper)",
                    "capacity"=>s.capacity
                )
            )
        )
        for (label,transits,occupancy,conflicts) in (("INITIAL",ti,oi,ci),("FINAL",tf,of,cf))
            matching = [t for t in transits if t.sector==i]
            dwell = ordered_total(t.exit-t.entry for t in matching)
            peaks = [maximum(occupancy[i,j:j+4]) for j in 1:5:length(times)]
            push!(lines,label*" "*attributes("entries"=>length(matching),"time"=>decimal(dwell),"mean"=>(isempty(matching) ? "-" : decimal(dwell/length(matching))),
                "peak"=>maximum(occupancy[i,:]),"over"=>count(>(s.capacity),peaks),"conflicts"=>count(
                    c->c.sector==s.name,
                    conflicts
                )))
        end
        height = max(s.capacity+1,maximum(of[i,:]))
        rows = [join([v>=k ? '#' : k==s.capacity ? '-' : '.' for v in of[i,:]]) for k in height:-1:1]
        append!(lines,chart(rows))
    end
    before,after = level_usage(trajectories_initial),level_usage(trajectories_final)
    push!(lines,"LEVELS")
    for level in sort!(collect(union(keys(before),keys(after)));rev=true)
        old,new = get(
            before,
            level,
            (flights=Set{Int}(),time=0.0)
        ),get(after,level,(flights=Set{Int}(),time=0.0))
        push!(
            lines,
            words(
                "LEVEL",
                level,
                attributes(
                    "flights"=>"$(length(old.flights))->$(length(new.flights))",
                    "time"=>"$(decimal(old.time))->$(decimal(new.time))"
                )
            )
        )
    end
    handoffs = zeros(Int,length(sectors),length(sectors))
    for t in tf
        t.next!=0 && (handoffs[t.sector,t.next]+=1)
    end
    push!(lines,"HANDOFFS plan=final count=$(sum(handoffs))")
    for i in eachindex(sectors),j in eachindex(sectors)
        handoffs[i,j]>0 && push!(lines,words("HANDOFF",sectors[i].name,sectors[j].name,handoffs[i,j]))
    end
    lines
end
function compute_alerts(trajectories,conflicts,params)
    observations = Dict{Tuple{Int,Int},Vector{NamedTuple}}()
    for time in sample_times(params)
        observed = [current_position(t,time) for t in trajectories]
        for a in eachindex(trajectories),b in a+1:length(trajectories)
            (isnothing(observed[a]) || isnothing(observed[b])) && continue
            pa,pb = observed[a],observed[b]
            relative = ntuple(i->pa.point[i]-pb.point[i],3)
            velocity = ntuple(i->pa.segment.velocity[i]-pb.segment.velocity[i],3)
            loss = loss_interval(relative,velocity,0,params.alert,params.dh,params.dv)
            isnothing(loss) && continue
            push!(get!(observations,(a,b),NamedTuple[]),(time=time,loss=time+loss.lo,distance=loss.distance))
        end
    end
    alerts = NamedTuple[]
    for pair in sort!(collect(keys(observations)))
        groups = Vector{NamedTuple}[]
        for event in observations[pair]
            if !isempty(groups) && event.time-groups[end][end].time==60
                push!(groups[end],event)
            else
                push!(groups,[event])
            end
        end
        for group in groups
            push!(
                alerts,
                (
                    pair=pair,
                    first=group[1].time,
                    last=group[end].time,
                    samples=length(group),
                    predicted=group[1].loss,
                    min_dist=minimum(e.distance for e in group)
                )
            )
        end
    end
    sort!(alerts;by=a->(a.first,a.pair...))
    detected = Set{Int}()
    for i in eachindex(alerts)
        alert = alerts[i]
        matches = findall(
            c->c.pair==alert.pair && c.start<alert.last+params.alert && c.finish>alert.first,
            conflicts
        )
        alerts[i] = (;alert...,lead=isempty(matches) ? nothing : conflicts[matches[1]].start-alert.first)
        union!(detected,matches)
    end
    alerts,[c for (i,c) in enumerate(conflicts) if !(i in detected)]
end
function alert_lines(label,plans,trajectories,conflicts,params)
    alerts,missed = compute_alerts(trajectories,conflicts,params)
    lines = ["ALERTS "*attributes("plan"=>label,"horizon"=>params.alert,"count"=>length(alerts))]
    leads = Float64[]
    for (i,a) in enumerate(alerts)
        status = isnothing(a.lead) ? "status=false lead=-" : "status=true lead="*decimal(a.lead)
        !isnothing(a.lead) && push!(leads,a.lead)
        push!(
            lines,
            words(
                "ALERT",
                i,
                pair_name(plans,a.pair),
                attributes(
                    "first"=>a.first,
                    "last"=>a.last,
                    "samples"=>a.samples,
                    "predicted"=>decimal(a.predicted),
                    "min_dist"=>decimal(a.min_dist)
                ),
                status
            )
        )
    end
    for c in missed
        push!(
            lines,
            words(
                "MISSED",
                pair_name(plans,c.pair),
                attributes("start"=>decimal(c.start),"end"=>decimal(c.finish))
            )
        )
    end
    push!(
        lines,
        "SUMMARY "*attributes(
            "alerts"=>length(alerts),
            "true"=>length(leads),
            "false"=>length(alerts)-length(leads),
            "missed"=>length(missed),
            "mean_lead"=>(isempty(leads) ? "-" : decimal(ordered_total(leads)/length(leads)))
        )
    )
    lines
end
function radar_cell(point,params)
    x,y,_ = point
    x0,y0,x1,y1,width,height = params.radar
    col = floor(Int,(10*x-x0)*width/(x1-x0))
    row = floor(Int,(10*y-y0)*height/(y1-y0))
    0<=col<width && 0<=row<height ? (col,height-1-row) : nothing
end
function radar_snapshot_lines(label,plans,trajectories,conflicts,time,params)
    width,height = params.radar[5:6]
    grid = fill('.',height,width)
    observations = Dict{Int,NamedTuple}()
    cells = Dict{Tuple{Int,Int},Vector{Int}}()
    for (i,t) in enumerate(trajectories)
        observed = current_position(t,time)
        isnothing(observed) && continue
        cell = radar_cell(observed.point,params)
        observations[i] = (;observed...,cell)
        !isnothing(cell) && push!(get!(cells,cell,Int[]),i)
    end
    active = active_conflicts(conflicts,time)
    for ((col,row),indices) in cells
        character = length(indices)>1 ? Char(Int('0')+length(indices)) : plans[indices[1]].callsign[1]
        length(indices)==1 && any(c->indices[1] in c.pair,active) && (character=lowercase(character))
        grid[row+1,col+1] = character
    end
    for i in sort!(collect(keys(observations)))
        predicted = current_position(trajectories[i],time+params.leader)
        isnothing(predicted) && continue
        cell = radar_cell(predicted.point,params)
        if !isnothing(cell)
            col,row = cell
            grid[row+1,col+1]=='.' && (grid[row+1,col+1]='*')
        end
    end
    lines = ["RADAR "*attributes(
        "plan"=>label,
        "t"=>time,
        "aircraft"=>length(observations),
        "conflicts"=>length(active)
    )]
    append!(lines,chart([join(grid[r,:]) for r in 1:height]))
    for i in sort!(collect(keys(observations)))
        entry = observations[i]
        x,y,z = entry.point
        cell = isnothing(entry.cell) ? "outside" : join(entry.cell,',')
        push!(
            lines,
            words(
                plans[i].callsign,
                attributes(
                    "x"=>decimal(x),
                    "y"=>decimal(y),
                    "fl"=>decimal(z/100,2),
                    "track"=>decimal(segment_track(entry.segment),1),
                    "phase"=>entry.segment.phase,
                    "cell"=>cell
                )
            )
        )
    end
    for c in active
        a,b = c.pair
        pa,pb = observations[a].point,observations[b].point
        dx,dy = pa[1]-pb[1],pa[2]-pb[2]
        push!(
            lines,
            words(
                "CONFLICT",
                pair_name(plans,c.pair),
                attributes("dist"=>decimal(sqrt(dx*dx+dy*dy)),"vert"=>decimal(abs(pa[3]-pb[3]),1))
            )
        )
    end
    lines
end
function radar_density_lines(label,trajectories,params)
    width,height = params.radar[5:6]
    density = zeros(Int,height,width)
    for time in sample_times(params),t in trajectories
        observed = current_position(t,time)
        isnothing(observed) && continue
        cell = radar_cell(observed.point,params)
        isnothing(cell) && continue
        col,row = cell
        density[row+1,col+1] += 1
    end
    lines = ["DENSITY "*attributes(
        "plan"=>label,
        "from"=>params.sample_start,
        "to"=>params.sample_end,
        "step"=>60,
        "max"=>maximum(density)
    )]
    rows = [join([v==0 ? '.' : v<10 ? Char(Int('0')+v) : '#' for v in density[r,:]]) for r in 1:height]
    append!(lines,chart(rows))
    lines
end
function flight_strips(plans,ti,tf,transits,sectors)
    lines = String[]
    for (i,p) in enumerate(plans)
        push!(
            lines,
            words(
                "STRIP",
                p.callsign,
                attributes(
                    "type"=>p.type,
                    "waypoints"=>length(p.waypoints),
                    "length"=>decimal(tf[i].length),
                    "manoeuvres"=>history_text(p)
                )
            )
        )
        for (k,w) in enumerate(p.waypoints)
            old,new = ti[i].waypoint_times[k],tf[i].waypoint_times[k]
            push!(
                lines,
                words(
                    "WPT",
                    k-1,
                    attributes(
                        "at"=>"$(w.x):$(w.y)",
                        "eta"=>"$(decimal(old[1]))->$(decimal(new[1]))",
                        "fl"=>"$(old[2])->$(new[2])"
                    )
                )
            )
        end
        entries = ["$(sectors[t.sector].name)@$(decimal(t.entry))" for t in transits if t.aircraft==i]
        push!(lines,"SECTORS "*(isempty(entries) ? "-" : join(entries,',')))
    end
    lines
end
function main()
    initial,types,sectors,params = load_all()
    ti = [build_trajectory(p,types) for p in initial]
    ci = all_conflicts(ti,params.dh,params.dv)
    resolution = resolve_conflicts(initial,types,params)
    final,tf = resolution.plans,resolution.trajectories
    cf = all_conflicts(tf,params.dh,params.dv)
    final_pairs = Set(c.pair for c in cf)
    ci = classify_conflicts(ci,sectors,final_pairs,resolution.resolved,params.dh)
    cf = classify_conflicts(cf,sectors,final_pairs,resolution.resolved,params.dh,true)
    transits_initial,transits_final = sector_transits(ti,sectors),sector_transits(tf,sectors)
    times = sample_times(params)
    oi,of = occupancy_table(ti,sectors,times),occupancy_table(tf,sectors,times)
    periods = period_table(sectors,times,oi,of,transits_initial,transits_final)
    write_lines("trajectories.csv",trajectories_csv(final,tf))
    write_lines(
        "conflicts.txt",
        [conflict_lines("initial",initial,ci,ti,params);conflict_lines("final",final,cf,tf,params)]
    )
    write_lines("resolutions.txt",resolution_lines(initial,final,ti,tf,ci,cf,resolution))
    write_lines("sector_transits.csv",transit_lines(final,sectors,transits_final))
    write_lines("sector_load.csv",sector_load_lines(sectors,periods))
    write_lines(
        "sector_report.txt",
        sector_report(sectors,times,oi,of,transits_initial,transits_final,ci,cf,ti,tf)
    )
    write_lines(
        "alerts.txt",
        [alert_lines("initial",initial,ti,ci,params);alert_lines("final",final,tf,cf,params)]
    )
    radar = String[]
    for time in params.snapshots
        append!(radar,radar_snapshot_lines("initial",initial,ti,ci,time,params))
        append!(radar,radar_snapshot_lines("final",final,tf,cf,time,params))
    end
    append!(radar,radar_density_lines("initial",ti,params))
    append!(radar,radar_density_lines("final",tf,params))
    write_lines("radar.txt",radar)
    write_lines("strips.txt",flight_strips(final,ti,tf,transits_final,sectors))
end
main()
