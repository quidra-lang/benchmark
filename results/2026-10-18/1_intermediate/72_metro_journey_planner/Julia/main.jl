struct CommandError <: Exception
    message::String
end
fail(s) = throw(CommandError(s))
check(b, s) = b ? nothing : fail(s)
parsetime(s) = 60*parse(Int, s[1:2])+parse(Int, s[4:5])
clocktext(t) = lpad(string(div(t, 60)), 2, '0')*":"*lpad(string(t%60), 2, '0')
halfprice(n) = cld(n, 20)*10
segmentkey(a, b) = minmax(a, b)
mutable struct Station
    id::String
    zone::Int
    name::String
    transfer::Int
    closed::Bool
    walks::Dict{String,Int}
end
Station(id, zone, name) = Station(id, zone, name, 0, false, Dict{String,Int}())
mutable struct TransitLine
    id::String
    first::Int
    last::Int
    headway::Int
    stops::Vector{String}
    offsets::Vector{Int}
    delay::Int
    suspended::Bool
end
trips(line) = div(line.last-line.first, line.headway)+1
struct Direction
    line::TransitLine
    stops::Vector{String}
    offsets::Vector{Int}
end
directions(line) = (
    Direction(line, line.stops, line.offsets),
    Direction(line, reverse(line.stops), last(line.offsets) .- reverse(line.offsets)),
)
traintime(d, q, j) = d.line.first+d.line.delay+q*d.line.headway+d.offsets[j]
function firsttrain(d, j, ready)
    q=max(0, cld(ready-traintime(d, 0, j), d.line.headway))
    q<trips(d.line) ? q : -1
end
function upcoming(d, j, time, count)
    q=firsttrain(d, j, time)
    q<0 ? Int[] : collect(q:(min(q+count, trips(d.line))-1))
end
abstract type Leg end
struct Ride <: Leg
    line::String
    terminal::String
    board::String
    start::Int
    alight::String
    finish::Int
    stops::Int
end
struct Walk <: Leg
    origin::String
    start::Int
    destination::String
    finish::Int
end
struct Stay <: Leg
    station::String
    start::Int
    finish::Int
end
ride(d, q, i, j) = Ride(
    d.line.id,
    last(d.stops),
    d.stops[i],
    traintime(d, q, i),
    d.stops[j],
    traintime(d, q, j),
    j-i,
)
struct Label
    time::Int
    journey::Vector{Leg}
end
const Labels=Dict{String,Label}
mutable struct Planner
    stations::Dict{String,Station}
    lines::Dict{String,TransitLine}
    closed::Set{Tuple{String,String}}
    tariff::Union{Nothing,Tuple{Int,Int,Vector{Int}}}
end
Planner() = Planner(
    Dict{String,Station}(),
    Dict{String,TransitLine}(),
    Set{Tuple{String,String}}(),
    nothing,
)
function station(p, name)
    check(haskey(p.stations, name), "unknown station $name")
    p.stations[name]
end
function transitline(p, name)
    check(haskey(p.lines, name), "unknown line $name")
    p.lines[name]
end
checkopen(p, name) = check(!p.stations[name].closed, "station $name is closed")
function endpoints(p, origin, destination)
    station(p, origin)
    station(p, destination)
    check(origin!=destination, "origin and destination are the same")
    checkopen(p, origin)
    checkopen(p, destination)
end
function toward(line, terminal)
    check(
        terminal in (first(line.stops), last(line.stops)),
        "$terminal is not a terminal of line $(line.id)",
    )
    directions(line)[terminal==last(line.stops) ? 1 : 2]
end
orderedlines(p; active = false) =
    [p.lines[id] for id in sort!(collect(keys(p.lines))) if !active || !p.lines[id].suspended]
blocked(p, a, b) = segmentkey(a, b) in p.closed
improves(labels, name, time) = !haskey(labels, name) || labels[name].time>time
readytime(p, origin, name, time) = time+(origin==name ? 0 : p.stations[name].transfer)
function walkfrom!(p, labels, name, time, journey)
    changed=Set{String}()
    for neighbor in sort!(collect(keys(p.stations[name].walks)))
        arrival=time+p.stations[name].walks[neighbor]
        if !p.stations[neighbor].closed && arrival<=1440 && improves(labels, neighbor, arrival)
            labels[neighbor]=Label(arrival, [journey; Leg[Walk(name, time, neighbor, arrival)]])
            push!(changed, neighbor)
        end
    end
    changed
end
function ridefrom!(p, labels, d, name, ready, journey)
    i=findfirst(==(name), d.stops)
    (i===nothing || i==length(d.stops)) && return
    q=firsttrain(d, i, ready)
    q<0 && return
    for j in (i+1):length(d.stops)
        stop=d.stops[j]
        blocked(p, d.stops[j-1], stop) && break
        p.stations[stop].closed && continue
        time=traintime(d, q, j)
        improves(labels, stop, time) && (labels[stop]=Label(time, [journey; Leg[ride(d, q, i, j)]]))
    end
end
function earliest(p, origin, departure)
    lines=orderedlines(p; active = true)
    labels=Labels(origin=>Label(departure, Leg[]))
    settled=Set{String}()
    while true
        pending=[(value.time, name) for (name, value) in labels if !(name in settled)]
        isempty(pending) && return labels
        time, name=minimum(pending)
        push!(settled, name)
        journey=labels[name].journey
        ready=readytime(p, origin, name, time)
        for line in lines, d in directions(line)
            ridefrom!(p, labels, d, name, ready, journey)
        end
        walkfrom!(p, labels, name, time, journey)
    end
end
function walkstep!(p, labels, starts, marked)
    recorded=Labels(name=>labels[name] for name in starts)
    for name in sort!(collect(starts))
        value=recorded[name]
        union!(marked, walkfrom!(p, labels, name, value.time, value.journey))
    end
end
function rideround!(p, origin, d, previous, previousmarked, labels, ridden)
    boarded=-1
    board=0
    journey=Leg[]
    for j in eachindex(d.stops)
        name=d.stops[j]
        j>1 && blocked(p, d.stops[j-1], name) && (boarded=-1)
        p.stations[name].closed && continue
        if boarded>=0
            time=traintime(d, boarded, j)
            if improves(labels, name, time)
                labels[name]=Label(time, [journey; Leg[ride(d, boarded, board, j)]])
                push!(ridden, name)
            end
        end
        if j<length(d.stops) && name in previousmarked
            value=previous[name]
            q=firsttrain(d, j, readytime(p, origin, name, value.time))
            if q>=0 && (boarded<0 || q<boarded)
                boarded=q
                board=j
                journey=value.journey
            end
        end
    end
end
function roundsearch(p, origin, departure)
    labels=Labels(origin=>Label(departure, Leg[]))
    marked=Set([origin])
    walkstep!(p, labels, Set([origin]), marked)
    rounds=[labels]
    lines=orderedlines(p; active = true)
    while !isempty(marked)
        previous=labels
        previousmarked=marked
        labels=copy(previous)
        ridden=Set{String}()
        for line in lines, d in directions(line)
            rideround!(p, origin, d, previous, previousmarked, labels, ridden)
        end
        marked=copy(ridden)
        walkstep!(p, labels, ridden, marked)
        push!(rounds, labels)
    end
    rounds
end
function journeyreport(heading, departure, value)
    journey=value.journey
    arrival=value.time
    rides=count(x->x isa Ride, journey)
    walks=count(x->x isa Walk, journey)
    println(
        "$heading $(clocktext(departure)) -> $(clocktext(arrival)) total $(arrival-departure) rides $rides walks $walks",
    )
    previous=departure
    for leg in journey
        if leg isa Ride
            println(
                "RIDE $(leg.line) toward $(leg.terminal) $(leg.board) $(clocktext(leg.start)) -> $(leg.alight) $(clocktext(leg.finish)) wait $(leg.start-previous) stops $(leg.stops)",
            )
        elseif leg isa Walk
            println(
                "WALK $(leg.origin) $(clocktext(leg.start)) -> $(leg.destination) $(clocktext(leg.finish))",
            )
        else
            println("STAY $(leg.station) $(clocktext(leg.start)) -> $(clocktext(leg.finish))")
        end
        previous=leg.finish
    end
end
function stopflags(p, stops, j)
    (p.stations[stops[j]].closed ? " closed" : "")*(
        j>1 && blocked(p, stops[j-1], stops[j]) ? " blocked" : ""
    )
end
function fareitems(p, journey, child)
    cap, window, prices=p.tariff
    child && (cap=halfprice(cap))
    previous=nothing
    items=Tuple{Ride,Int,Int,Int}[]
    for leg in journey
        leg isa Ride || continue
        d=toward(p.lines[leg.line], leg.terminal)
        at=findfirst(==(leg.board), d.stops)
        zones=length(Set(p.stations[name].zone for name in d.stops[at:(at+leg.stops)]))
        price=prices[min(zones, length(prices))]
        child && (price=halfprice(price))
        discount=previous!==nothing && leg.start-previous.finish<=window ? min(cap, price) : 0
        push!(items, (leg, zones, price, discount))
        previous=leg
    end
    items
end
function passing(p, name, time, count, arriving)
    result=Tuple{Int,String,Int,Direction}[]
    for line in orderedlines(p; active = true)
        at=findfirst(==(name), line.stops)
        at===nothing && continue
        for (order, d) in enumerate(directions(line))
            j=findfirst(==(name), d.stops)
            j==(arriving ? 1 : length(d.stops)) && continue
            for q in upcoming(d, j, time, count)
                push!(result, (traintime(d, q, j), line.id, order, d))
            end
        end
    end
    sort!(result; by = x->x[1:3])
    result[1:min(count, length(result))]
end
function execute!(p, line)
    words=String.(split(line, ' '))
    command=words[1]
    a=words[2:end]
    if command=="STATION"
        id=a[1]
        check(!haskey(p.stations, id), "station $id already exists")
        p.stations[id]=Station(id, parse(Int, a[2]), a[3])
        println("STATION $id zone $(a[2]) $(a[3])")
    elseif command=="LINE"
        id=a[1]
        check(!haskey(p.lines, id), "line $id already exists")
        stops=a[5:2:end]
        for name in stops
            station(p, name)
        end
        seen=Set{String}()
        for name in stops
            check(!(name in seen), "station $name appears twice on line $id")
            push!(seen, name)
        end
        firsttime=parsetime(a[2])
        lasttime=parsetime(a[3])
        check(firsttime<=lasttime, "line $id first departure is after last departure")
        offsets=[0; cumsum(parse.(Int, a[6:2:end]))]
        check(lasttime+last(offsets)<=1440, "line $id runs past 24:00")
        value=TransitLine(id, firsttime, lasttime, parse(Int, a[4]), stops, offsets, 0, false)
        p.lines[id]=value
        println("LINE $id stops $(length(stops)) time $(last(offsets)) trips $(trips(value))")
    elseif command=="TRANSFER"
        value=station(p, a[1])
        value.transfer=parse(Int, a[2])
        println("TRANSFER $(a[1]) $(a[2])")
    elseif command=="WALK"
        firststation=station(p, a[1])
        secondstation=station(p, a[2])
        check(a[1]!=a[2], "walk from $(a[1]) to itself")
        minutes=parse(Int, a[3])
        old=get(firststation.walks, a[2], nothing)
        firststation.walks[a[2]]=minutes
        secondstation.walks[a[1]]=minutes
        println("WALK $(a[1]) $(a[2]) $minutes", old===nothing ? "" : " was $old")
    elseif command=="TARIFF"
        tariffvalues=parse.(Int, a)
        prices=tariffvalues[3:end]
        check(
            all(i->prices[i]<=prices[i+1], 1:(length(prices)-1)),
            "tariff prices must not decrease",
        )
        p.tariff=(tariffvalues[1], tariffvalues[2], prices)
        println(
            "TARIFF zones $(length(prices)) discount $(tariffvalues[1]) window $(tariffvalues[2])",
        )
    elseif command in ("CLOSE", "OPEN")
        firststation=station(p, a[1])
        closing=command=="CLOSE"
        if length(a)==1
            check(
                firststation.closed!=closing,
                "station $(a[1]) is "*(closing ? "already closed" : "not closed"),
            )
            firststation.closed=closing
            println(command, " ", a[1])
        else
            station(p, a[2])
            key=segmentkey(a[1], a[2])
            label="$(a[1])-$(a[2])"
            if closing
                lines=[
                    value.id for value in orderedlines(p) if any(
                        i->segmentkey(value.stops[i], value.stops[i+1])==key,
                        1:(length(value.stops)-1),
                    )
                ]
                check(!isempty(lines), "no segment $label")
                check(!(key in p.closed), "segment $label is already closed")
                push!(p.closed, key)
                println("CLOSE $label lines ", join(lines, ' '))
            else
                check(key in p.closed, "segment $label is not closed")
                delete!(p.closed, key)
                println("OPEN $label")
            end
        end
    elseif command in ("DELAY", "SUSPEND", "RESUME")
        value=transitline(p, a[1])
        if command=="DELAY"
            minutes=parse(Int, a[2])
            check(value.last+minutes+last(value.offsets)<=1440, "line $(a[1]) runs past 24:00")
            value.delay=minutes
            println("DELAY $(a[1]) $minutes")
        else
            suspend=command=="SUSPEND"
            check(
                value.suspended!=suspend,
                "line $(a[1]) is "*(suspend ? "already suspended" : "not suspended"),
            )
            value.suspended=suspend
            println(command, " ", a[1])
        end
    elseif command=="VIA"
        origin, via, destination, time=a
        station(p, origin)
        station(p, via)
        station(p, destination)
        check(origin!=destination, "origin and destination are the same")
        check(
            !(via in (origin, destination)),
            "via station $via must differ from origin and destination",
        )
        for name in (origin, via, destination)
            checkopen(p, name)
        end
        departure=parsetime(time)
        heading="VIA $origin $via $destination"
        firstlabels=earliest(p, origin, departure)
        if haskey(firstlabels, via)
            firstvalue=firstlabels[via]
            resume=firstvalue.time+p.stations[via].transfer
            secondlabels=earliest(p, via, resume)
            if haskey(secondlabels, destination)
                value=secondlabels[destination]
                journey=[firstvalue.journey; Leg[Stay(via, firstvalue.time, resume)]; value.journey]
                journeyreport(heading, departure, Label(value.time, journey))
                return
            end
        end
        println("$heading $time unreachable")
    elseif command in ("ROUTE", "FEWEST", "PARETO", "FARE", "LASTTRAIN", "ARRIVEBY", "PROFILE")
        origin=a[1]
        destination=a[2]
        endpoints(p, origin, destination)
        if command=="FARE"
            check(a[4] in ("ADULT", "CHILD"), "unknown fare class $(a[4])")
            check(p.tariff!==nothing, "no tariff")
        end
        if command in ("LASTTRAIN", "ARRIVEBY")
            deadline=command=="LASTTRAIN" ? 1440 : parsetime(a[3])
            heading=command=="LASTTRAIN" ? "LASTTRAIN $origin $destination" :
                    "ARRIVEBY $origin $destination by $(a[3])"
            for departure in (deadline-1):-1:0
                labels=earliest(p, origin, departure)
                if haskey(labels, destination) && labels[destination].time<=deadline
                    journeyreport(heading, departure, labels[destination])
                    return
                end
            end
            println("$heading none")
            return
        end
        departure=parsetime(a[3])
        heading="$command $origin $destination"
        if command=="PROFILE"
            finish=parsetime(a[4])
            check(departure<=finish, "empty interval $(a[3]) $(a[4])")
            arrivals=Dict{Int,Int}()
            for time in departure:finish
                labels=earliest(p, origin, time)
                haskey(labels, destination) && (arrivals[time]=labels[destination].time)
            end
            selected=[
                t for t in departure:finish if haskey(arrivals, t) &&
                    (t==finish || !haskey(arrivals, t+1) || arrivals[t]<arrivals[t+1])
            ]
            println("$heading $(a[3]) $(a[4]) count $(length(selected))")
            for t in selected
                println("$(clocktext(t)) -> $(clocktext(arrivals[t])) total $(arrivals[t]-t)")
            end
        elseif command in ("FEWEST", "PARETO")
            rounds=roundsearch(p, origin, departure)
            options=Tuple{Int,Label}[]
            previous=nothing
            for (i, labels) in enumerate(rounds)
                if haskey(labels, destination)
                    value=labels[destination]
                    if previous===nothing || value.time<previous
                        push!(options, (i-1, value))
                    end
                    previous=value.time
                end
            end
            if command=="PARETO"
                println("$heading $(a[3]) options $(length(options))")
                for (rides, value) in options
                    journeyreport("OPTION trips $rides", departure, value)
                end
            elseif isempty(options)
                println("$heading $(a[3]) unreachable")
            else
                rides, value=first(options)
                journeyreport("$heading trips $rides", departure, value)
            end
        else
            labels=earliest(p, origin, departure)
            if !haskey(labels, destination)
                println("$heading $(a[3])", command=="FARE" ? " $(a[4])" : "", " unreachable")
                return
            end
            value=labels[destination]
            if command=="ROUTE"
                journeyreport(heading, departure, value)
            else
                items=fareitems(p, value.journey, a[4]=="CHILD")
                total=sum(x->x[3]-x[4], items; init = 0)
                println("$heading $(a[3]) $(a[4]) rides $(length(items)) total $total")
                for (leg, zones, price, discount) in items
                    println(
                        "TICKET $(leg.line) $(leg.board) $(leg.alight) zones $zones price $price discount $discount pay $(price-discount)",
                    )
                end
            end
        end
    elseif command=="REACH"
        name=a[1]
        station(p, name)
        checkopen(p, name)
        departure=parsetime(a[2])
        labels=earliest(p, name, departure)
        limit=departure+parse(Int, a[3])
        selected=sort!([(value.time, id) for (id, value) in labels if value.time<=limit])
        println("REACH $name $(a[2]) $(a[3]) count $(length(selected))")
        for (arrival, id) in selected
            println(
                "$id $(p.stations[id].name) $(clocktext(arrival)) $(arrival-departure) rides $(count(x->x isa Ride,labels[id].journey))",
            )
        end
    elseif command=="TIMETABLE"
        name, id, terminal, time, countword=a
        station(p, name)
        value=transitline(p, id)
        check(name in value.stops, "station $name is not on line $id")
        d=toward(value, terminal)
        check(name!=terminal, "no departures from $name toward $terminal")
        check(!value.suspended, "line $id is suspended")
        checkopen(p, name)
        j=findfirst(==(name), d.stops)
        times=[
            clocktext(traintime(d, q, j)) for
            q in upcoming(d, j, parsetime(time), parse(Int, countword))
        ]
        println(
            "TIMETABLE $name $id toward $terminal $time next $(length(times))",
            isempty(times) ? "" : " "*join(times, ' '),
        )
    elseif command in ("DEPARTURES", "ARRIVALS")
        name=a[1]
        station(p, name)
        checkopen(p, name)
        arriving=command=="ARRIVALS"
        trains=passing(p, name, parsetime(a[2]), parse(Int, a[3]), arriving)
        println("$command $name $(a[2]) count $(length(trains))")
        for (time, id, _, d) in trains
            println(
                "$(clocktext(time)) $id ",
                arriving ? "from $(first(d.stops))" : "toward $(last(d.stops))",
            )
        end
    elseif command in ("TRIP", "SHOWLINE")
        value=transitline(p, a[1])
        if command=="SHOWLINE"
            println(
                "SHOWLINE $(value.id) $(value.suspended ? "suspended" : "running") first $(clocktext(value.first)) last $(clocktext(value.last)) headway $(value.headway) delay $(value.delay) trips $(trips(value))",
            )
            for (j, name) in enumerate(value.stops)
                println(
                    "$(value.offsets[j]) $name zone $(p.stations[name].zone)",
                    stopflags(p, value.stops, j),
                )
            end
        else
            d=toward(value, a[2])
            check(!value.suspended, "line $(value.id) is suspended")
            q=firsttrain(d, 1, parsetime(a[3]))
            heading="TRIP $(value.id) toward $(a[2]) $(a[3])"
            if q<0
                println("$heading none")
            else
                println("$heading trip $(q+1) departs $(clocktext(traintime(d,q,1)))")
                for (j, name) in enumerate(d.stops)
                    println("$(clocktext(traintime(d,q,j))) $name", stopflags(p, d.stops, j))
                end
            end
        end
    elseif command=="INFO"
        value=station(p, a[1])
        println(
            "INFO $(value.id) $(value.name) zone $(value.zone) transfer $(value.transfer) $(value.closed ? "closed" : "open")",
        )
        lines=[line.id for line in orderedlines(p) if value.id in line.stops]
        println("LINES ", isempty(lines) ? "none" : join(lines, ' '))
        walks=["$name $(value.walks[name])" for name in sort!(collect(keys(value.walks)))]
        println("WALKS ", isempty(walks) ? "none" : join(walks, ' '))
    elseif command=="STATUS"
        walks=div(sum(x->length(x.walks), values(p.stations); init = 0), 2)
        println("STATUS stations $(length(p.stations)) lines $(length(p.lines)) walks $walks")
        for id in sort!(collect(keys(p.stations)))
            p.stations[id].closed && println("CLOSED $id")
        end
        for (a, b) in sort!(collect(p.closed))
            println("CLOSED $a-$b")
        end
        for line in orderedlines(p)
            line.suspended && println("SUSPENDED $(line.id)")
        end
        for line in orderedlines(p)
            line.delay!=0 && println("DELAYED $(line.id) $(line.delay)")
        end
    end
end
function main()
    planner=Planner()
    n=parse(Int, readline())
    for _ in 1:n
        line=readline()
        try
            execute!(planner, line)
        catch e
            e isa CommandError || rethrow()
            println("ERROR $(e.message)")
        end
    end
end
main()
