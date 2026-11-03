function make_segment(leg,phase,ts,te,start,velocity,finish,number)
    (;leg,phase,ts,te,start,velocity,finish,number)
end
function build_trajectory(plan,types)
    current,level = Float64(plan.departure+plan.delay),plan.level+plan.offset
    segments,times,route_length = NamedTuple[],[(current,level)],0.0
    aircraft = types[plan.type]
    for leg in 1:length(plan.waypoints)-1
        first,last = plan.waypoints[leg],plan.waypoints[leg+1]
        dx,dy = last.x-first.x,last.y-first.y
        distance = sqrt(dx*dx+dy*dy)/10
        duration = distance*3600/plan.speed
        vx,vy = (dx/10)/duration,(dy/10)/duration
        route_length += distance
        target = isnothing(last.level) ? level : last.level+plan.offset
        x,y = first.x/10,first.y/10
        finish = (last.x/10,last.y/10,Float64(target*100))
        if target==level
            push!(
                segments,
                make_segment(
                    leg,
                    "LVL",
                    current,
                    current+duration,
                    (x,y,Float64(level*100)),
                    (vx,vy,0.0),
                    finish,
                    length(segments)+1
                )
            )
        else
            climbing = target>level
            rate = climbing ? aircraft.climb : aircraft.descent
            vz = climbing ? rate/60 : -(rate/60)
            change_time = abs(target-level)*6000/rate
            changed = (x+vx*change_time,y+vy*change_time,Float64(target*100))
            push!(
                segments,
                make_segment(
                    leg,
                    climbing ? "CLB" : "DES",
                    current,
                    current+change_time,
                    (x,y,Float64(level*100)),
                    (vx,vy,vz),
                    changed,
                    length(segments)+1
                )
            )
            push!(
                segments,
                make_segment(
                    leg,
                    "LVL",
                    current+change_time,
                    current+duration,
                    changed,
                    (vx,vy,0.0),
                    finish,
                    length(segments)+1
                )
            )
        end
        current += duration
        level = target
        push!(times,(current,level))
    end
    (segments=segments,arrival=current,length=route_length,waypoint_times=times)
end
segment_position(segment,time) = ntuple(i->segment.start[i]+segment.velocity[i]*(time-segment.ts),3)
function active_segment(trajectory,time)
    segments = trajectory.segments
    segments[1].ts<=time<segments[end].te || return nothing
    for segment in segments
        segment.ts<=time<segment.te && return segment
    end
    nothing
end
function current_position(trajectory,time)
    segment = active_segment(trajectory,time)
    isnothing(segment) ? nothing : (point=segment_position(segment,time),segment=segment)
end
