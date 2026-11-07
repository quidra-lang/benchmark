function load_all()
    types = Dict{String,NamedTuple}()
    for line in readlines("input/aircraft.txt")
        f = split(line)
        types[f[1]] = (climb=parse(Int,f[2]),descent=parse(Int,f[3]),minimum=parse(Int,f[4]))
    end
    sectors = NamedTuple[]
    for line in readlines("input/sectors.txt")
        f = split(line)
        v = parse.(Int,f[2:end])
        push!(sectors,(name=String(f[1]),x1=v[1],y1=v[2],x2=v[3],y2=v[4],lower=v[5],upper=v[6],capacity=v[7]))
    end
    settings = [parse.(Int,split(line)[2:end]) for line in readlines("input/params.txt")]
    params = (dh=settings[1][1],dv=settings[1][2],lookahead=settings[2][1],max_delay=settings[3][1],level_min=settings[4][1],
        level_max=settings[4][2],sample_start=settings[5][1],sample_end=settings[5][2],radar=settings[6],snapshots=settings[7],leader=settings[8][1],alert=settings[9][1])
    plans = NamedTuple[]
    for line in readlines("input/flights.csv")[2:end]
        f = split(line,',')
        waypoints = [begin
            v = parse.(Int,split(text,':'))
            (x=v[1],y=v[2],level=length(v)==3 ? v[3] : nothing)
        end for text in split(f[6])]
        speed = parse(Int,f[5])
        push!(plans,(callsign=String(f[1]),type=String(f[2]),departure=parse(Int,f[3]),level=parse(Int,f[4]),speed_initial=speed,
            speed=speed,waypoints=waypoints,delay=0,offset=0,history=String[]))
    end
    sort!(plans;by=p->p.callsign),types,sectors,params
end
level_list(p) = [p.level+p.offset;[w.level+p.offset for w in p.waypoints[2:end] if !isnothing(w.level)]]
