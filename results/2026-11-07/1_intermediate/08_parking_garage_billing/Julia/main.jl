using Printf
const TYPES = ("MOTORCYCLE","CAR","ECAR","VAN","BUS")
const KINDS = ("MOTO","COMPACT","LARGE","EV")
const PREFS = Dict("MOTORCYCLE"=>["MOTO","COMPACT","LARGE"],"CAR"=>["COMPACT","LARGE"],"ECAR"=>["EV","COMPACT","LARGE"],"VAN"=>["LARGE"])
Base.@kwdef mutable struct GarageSpot
    id::String
    level::Int
    number::Int
    kind::String
    closed::Bool = false
    plate::String = ""
end
struct Payment
    time::Int
    parking::Int
    night::Int
end
Base.@kwdef mutable struct Vehicle
    plate::String
    kind::String
    spots::Vector{GarageSpot}
    entry::Int
    kwh::Int = 0
    cost::Int = 0
    validation::Int = 0
    payment::Union{Nothing,Payment} = nothing
end
struct WaitEntry
    plate::String
    kind::String
    time::Int
end
struct ExitRecord
    entry::Int
    exit::Int
    location::String
    kind::String
    total::Int
    lost::Bool
end
const RATES = Dict("MOTORCYCLE"=>(100,800),"CAR"=>(200,1600),"ECAR"=>(200,1600),"VAN"=>(300,2400),"BUS"=>(600,4800))
const FEES = Dict("NIGHT"=>300,"LOST"=>2000,"KWH"=>30)
const LEVELS = Vector{GarageSpot}[]
const SPOTS = Dict{String,GarageSpot}()
const VEHICLES = Dict{String,Vehicle}()
const QUEUE = WaitEntry[]
const PASSES = Dict{String,Int}()
const HISTORY = Dict{String,Vector{ExitRecord}}()
const STATS = Dict(kind=>Dict(field=>0 for field in ("entries","exits","refused","stay","parking","night","lost","charge","total")) for kind in TYPES)
const DAILY = Dict{Int,Dict{String,Dict{String,Int}}}()
const NOW = Ref(0)
const PEAK = Ref(0)
const PEAK_TIME = Ref(0)
fail(message) = throw(ArgumentError(message))
date_of(time) = div(time,1440)+1
time_text(time) = string(date_of(time),'-',@sprintf("%02d:%02d",div(mod(time,1440),60),mod(time,60)))
duration(minutes) = @sprintf("%d:%02d",div(minutes,60),mod(minutes,60))
one_decimal(q) = string(div(q,10),'.',mod(q,10))
valid_pass(plate,time) = haskey(PASSES,plate) && date_of(time) <= PASSES[plate]
function get_spot(id)
    haskey(SPOTS,id) || fail("unknown spot $id")
    return SPOTS[id]
end
function get_vehicle(plate)
    haskey(VEHICLES,plate) || fail("$plate is not parked")
    return VEHICLES[plate]
end
function location(v)
    s = v.spots[1]
    return v.kind == "BUS" ? "L$(s.level)-$(s.number)..$(s.number+2)" : s.id
end
location_key(v) = (v.spots[1].level,v.spots[1].number)
free_spot(s) = !s.closed && isempty(s.plate)
function assignment(kind)
    if kind == "BUS"
        for level in LEVELS
            for i in 1:length(level)-2
                triple = level[i:i+2]
                all(s -> s.kind == "LARGE" && free_spot(s),triple) && return triple
            end
        end
    else
        for preferred in PREFS[kind]
            for level in LEVELS
                for s in level
                    s.kind == preferred && free_spot(s) && return [s]
                end
            end
        end
    end
    return GarageSpot[]
end
function add_stat!(kind,field,amount,date)
    STATS[kind][field] += amount
    if field in ("entries","exits","refused","total")
        if !haskey(DAILY,date)
            DAILY[date] = Dict(k=>Dict(f=>0 for f in ("entries","exits","refused","revenue")) for k in TYPES)
        end
        dailyfield = field == "total" ? "revenue" : field
        DAILY[date][kind][dailyfield] += amount
    end
end
function park_vehicle!(plate,kind,chosen)
    v = Vehicle(plate=plate,kind=kind,spots=chosen,entry=NOW[])
    for s in chosen
        s.plate = plate
    end
    VEHICLES[plate] = v
    add_stat!(kind,"entries",1,date_of(NOW[]))
    if length(VEHICLES) > PEAK[]
        PEAK[],PEAK_TIME[] = length(VEHICLES),NOW[]
    end
    return v
end
function process_queue!(out)
    remaining = WaitEntry[]
    for waiting in QUEUE
        chosen = assignment(waiting.kind)
        if isempty(chosen)
            push!(remaining,waiting)
        else
            v = park_vehicle!(waiting.plate,waiting.kind,chosen)
            push!(out,"ADMIT $(v.plate) $(v.kind) $(location(v)) waited $(duration(NOW[]-waiting.time))")
        end
    end
    empty!(QUEUE)
    append!(QUEUE,remaining)
end
function giveups!()
    out = String[]
    remaining = WaitEntry[]
    for waiting in QUEUE
        if NOW[]-waiting.time >= 30
            time = waiting.time+30
            push!(out,"GIVEUP $(waiting.plate) $(waiting.kind) $(time_text(time))")
            add_stat!(waiting.kind,"refused",1,date_of(time))
        else
            push!(remaining,waiting)
        end
    end
    empty!(QUEUE)
    append!(QUEUE,remaining)
    return out
end
function interval_fee(v,a,b,free)
    total = b-a
    (valid_pass(v.plate,b) || total <= free) && return (0,0)
    rate,cap = RATES[v.kind]
    parking,i = 0,0
    while total > 0
        minutes = min(total,1440)
        billable = minutes-(i == 0 ? free : 0)
        parking += min(cld(billable,30)*rate,cap)
        total -= minutes
        i += 1
    end
    return parking,(date_of(b)-date_of(a))*FEES["NIGHT"]
end
function charges(v,lost=false)
    if v.payment === nothing
        parking,night = interval_fee(v,v.entry,NOW[],15+v.validation)
        loss = lost ? FEES["LOST"] : 0
        total = parking+night+loss+v.cost
        return (parking,night,loss,v.cost,total,total)
    end
    extra,extranight = interval_fee(v,v.payment.time,NOW[],15)
    parking,night = v.payment.parking+extra,v.payment.night+extranight
    return (parking,night,0,v.cost,parking+night+v.cost,extra+extranight)
end
fee_line(label,v,f) = "$label $(v.plate) $(location(v)) stay $(duration(NOW[]-v.entry)) parking $(f[1]) night $(f[2]) lost $(f[3]) charge $(f[4]) total $(f[5]) due $(f[6])"
function annotation(v)
    text = valid_pass(v.plate,NOW[]) ? " PASS" : ""
    v.validation != 0 && (text *= " VAL $(v.validation)")
    v.kwh != 0 && (text *= " KWH $(v.kwh)")
    v.payment !== nothing && (text *= " PAID")
    return text
end
function move_vehicle!(v,spot)
    old = location(v)
    v.spots[1].plate = ""
    spot.plate = v.plate
    v.spots = [spot]
    return "MOVE $(v.plate) $old -> $(spot.id)"
end
function occupancy_line(label,used,available,closed)
    parts = [label]
    for kind in KINDS
        append!(parts,[kind,"$(used[kind])/$(available[kind])"])
    end
    return join(parts," ")*" closed $closed"
end
function execute(t)
    cmd = t[1]
    out = String[]
    if cmd == "LEVEL"
        levelno = length(LEVELS)+1
        level = GarageSpot[]
        for (index,kind) in enumerate(KINDS)
            for i in 1:parse(Int,t[index+1])
                number = length(level)+1
                id = "L$levelno-$number"
                s = GarageSpot(id=id,level=levelno,number=number,kind=kind)
                SPOTS[id] = s
                push!(level,s)
            end
        end
        push!(LEVELS,level)
        push!(out,"LEVEL $levelno spots $(length(level)) MOTO $(t[2]) COMPACT $(t[3]) LARGE $(t[4]) EV $(t[5])")
    elseif cmd in ("CLOSE","OPEN")
        s = get_spot(t[2])
        if cmd == "CLOSE"
            s.closed && fail("spot $(t[2]) is already closed")
            !isempty(s.plate) && fail("spot $(t[2]) is occupied by $(s.plate)")
            s.closed = true
        else
            s.closed || fail("spot $(t[2]) is not closed")
            s.closed = false
        end
        push!(out,"$cmd $(s.id) $(s.kind)")
    elseif cmd == "RATE"
        haskey(RATES,t[2]) || fail("unknown type $(t[2])")
        rate,cap = parse.(Int,t[3:4])
        cap >= rate || fail("cap below rate for $(t[2])")
        RATES[t[2]] = (rate,cap)
        push!(out,"RATE $(t[2]) $(t[3]) $(t[4])")
    elseif cmd == "FEE"
        haskey(FEES,t[2]) || fail("unknown fee $(t[2])")
        FEES[t[2]] = parse(Int,t[3])
        push!(out,"FEE $(t[2]) $(t[3])")
    elseif cmd == "ENTER"
        plate,kind = t[2:3]
        haskey(RATES,kind) || fail("unknown type $kind")
        haskey(VEHICLES,plate) && fail("$plate is already parked at $(location(VEHICLES[plate]))")
        any(w -> w.plate == plate,QUEUE) && fail("$plate is already waiting")
        chosen = assignment(kind)
        if !isempty(chosen)
            v = park_vehicle!(plate,kind,chosen)
            push!(out,"ENTER $plate $kind $(location(v))")
        elseif length(QUEUE) < 3
            push!(QUEUE,WaitEntry(plate,kind,NOW[]))
            push!(out,"WAIT $plate $kind $(length(QUEUE))")
        else
            add_stat!(kind,"refused",1,date_of(NOW[]))
            push!(out,"FULL $plate $kind")
        end
    elseif cmd == "LEAVE"
        index = findfirst(w -> w.plate == t[2],QUEUE)
        index === nothing && fail("$(t[2]) is not waiting")
        w = QUEUE[index]
        deleteat!(QUEUE,index)
        push!(out,"LEAVE $(w.plate) $(w.kind)")
    elseif cmd in ("EXIT","PAY","QUOTE","CHARGE","VALIDATE","MOVE")
        v = get_vehicle(t[2])
        if cmd == "EXIT"
            lost = length(t) == 3
            lost && v.payment !== nothing && fail("$(v.plate) has already paid")
            f = charges(v,lost)
            push!(out,fee_line("EXIT",v,f))
            record = ExitRecord(v.entry,NOW[],location(v),v.kind,f[5],lost)
            push!(get!(HISTORY,v.plate,ExitRecord[]),record)
            for s in v.spots
                s.plate = ""
            end
            delete!(VEHICLES,v.plate)
            add_stat!(v.kind,"exits",1,date_of(NOW[]))
            add_stat!(v.kind,"stay",NOW[]-v.entry,date_of(NOW[]))
            for (index,field) in enumerate(("parking","night","lost","charge","total"))
                add_stat!(v.kind,field,f[index],date_of(NOW[]))
            end
        elseif cmd == "PAY"
            v.payment !== nothing && fail("$(v.plate) has already paid")
            f = charges(v)
            v.payment = Payment(NOW[],f[1],f[2])
            push!(out,"PAY $(v.plate) parking $(f[1]) night $(f[2]) charge $(f[4]) total $(f[5])")
        elseif cmd == "QUOTE"
            push!(out,fee_line("QUOTE",v,charges(v)))
        elseif cmd == "CHARGE"
            v.kind == "ECAR" || fail("$(v.plate) is not an electric car")
            v.spots[1].kind == "EV" || fail("$(v.plate) is not at a charger")
            v.payment !== nothing && fail("$(v.plate) has already paid")
            kwh = parse(Int,t[3])
            v.kwh+kwh <= 100 || fail("charge limit exceeded for $(v.plate)")
            cost = kwh*FEES["KWH"]
            v.kwh += kwh
            v.cost += cost
            push!(out,"CHARGE $(v.plate) kwh $kwh cost $cost stay_kwh $(v.kwh) stay_cost $(v.cost)")
        elseif cmd == "VALIDATE"
            v.payment !== nothing && fail("$(v.plate) has already paid")
            minutes = parse(Int,t[3])
            v.validation+minutes <= 180 || fail("validation limit exceeded for $(v.plate)")
            v.validation += minutes
            push!(out,"VALIDATE $(v.plate) $minutes total $(v.validation)")
        else
            v.kind == "BUS" && fail("bus $(v.plate) cannot be moved")
            s = get_spot(t[3])
            v.spots[1].id == s.id && fail("$(v.plate) is already at $(s.id)")
            s.closed && fail("spot $(s.id) is closed")
            !isempty(s.plate) && fail("spot $(s.id) is occupied by $(s.plate)")
            s.kind in PREFS[v.kind] || fail("$(v.kind) cannot use $(s.kind) spot $(s.id)")
            push!(out,move_vehicle!(v,s))
        end
    elseif cmd == "PASS"
        plate,days = t[2],parse(Int,t[3])
        PASSES[plate] = valid_pass(plate,NOW[]) ? PASSES[plate]+days : date_of(NOW[])+days-1
        push!(out,"PASS $plate until $(PASSES[plate])")
    elseif cmd == "UNPASS"
        valid_pass(t[2],NOW[]) || fail("$(t[2]) has no pass")
        delete!(PASSES,t[2])
        push!(out,"UNPASS $(t[2])")
    elseif cmd == "REBALANCE"
        targets = sort(filter(v -> v.kind != "BUS",collect(values(VEHICLES)));by=location_key)
        moved = 0
        for v in targets
            current = findfirst(==(v.spots[1].kind),PREFS[v.kind])
            current == 1 && continue
            chosen = assignment(v.kind)
            if !isempty(chosen) && findfirst(==(chosen[1].kind),PREFS[v.kind]) < current
                push!(out,move_vehicle!(v,chosen[1]))
                moved += 1
            end
        end
        push!(out,"REBALANCE $moved")
    elseif cmd == "WHERE"
        plate = t[2]
        if haskey(VEHICLES,plate)
            v = VEHICLES[plate]
            push!(out,"WHERE $plate $(location(v)) $(v.kind) $(time_text(v.entry)) stay $(duration(NOW[]-v.entry))$(annotation(v))")
        else
            index = findfirst(w -> w.plate == plate,QUEUE)
            if index !== nothing
                push!(out,"WHERE $plate waiting $index")
            elseif haskey(HISTORY,plate)
                push!(out,"WHERE $plate gone $(time_text(HISTORY[plate][end].exit))")
            else
                fail("unknown plate $plate")
            end
        end
    elseif cmd in ("LIST","OVERSTAY")
        if cmd == "LIST" && length(t) == 2
            1 <= parse(Int,t[2]) <= length(LEVELS) || fail("unknown level $(t[2])")
        end
        targets = collect(values(VEHICLES))
        if cmd == "LIST" && length(t) == 2
            filter!(v -> v.spots[1].level == parse(Int,t[2]),targets)
        elseif cmd == "OVERSTAY"
            filter!(v -> NOW[]-v.entry >= 60parse(Int,t[2]),targets)
        end
        sort!(targets;by=v -> cmd == "OVERSTAY" ? (v.entry,location_key(v)...) : location_key(v))
        header = cmd == "OVERSTAY" ? "$cmd $(t[2])" : cmd
        push!(out,"$header $(length(targets))")
        for v in targets
            text = "$(location(v)) $(v.plate) $(v.kind) $(time_text(v.entry))"
            text *= cmd == "LIST" ? annotation(v) : " stay $(duration(NOW[]-v.entry))"
            push!(out,text)
        end
    elseif cmd == "MAP"
        push!(out,"MAP $(length(LEVELS))")
        for (index,level) in enumerate(LEVELS)
            symbols = String[]
            for s in level
                if s.closed
                    push!(symbols,"#")
                else
                    initial = string(first(s.kind))
                    push!(symbols,isempty(s.plate) ? lowercase(initial) : initial)
                end
            end
            chunks = (join(chunk) for chunk in Iterators.partition(symbols,10))
            push!(out,"L$index "*join(chunks," "))
        end
    elseif cmd == "OCCUPANCY"
        push!(out,"OCCUPANCY vehicles $(length(VEHICLES)) waiting $(length(QUEUE))")
        totalused,totalavailable = Dict(k=>0 for k in KINDS),Dict(k=>0 for k in KINDS)
        totalclosed = 0
        for (index,level) in enumerate(LEVELS)
            used,available = Dict(k=>0 for k in KINDS),Dict(k=>0 for k in KINDS)
            closedcount = 0
            for s in level
                if s.closed
                    closedcount += 1
                else
                    available[s.kind] += 1
                end
                !isempty(s.plate) && (used[s.kind] += 1)
            end
            push!(out,occupancy_line("L$index",used,available,closedcount))
            for kind in KINDS
                totalused[kind] += used[kind]
                totalavailable[kind] += available[kind]
            end
            totalclosed += closedcount
        end
        capacity = sum(values(totalavailable))
        usage = capacity == 0 ? 0 : div(sum(values(totalused))*1000,capacity)
        push!(out,occupancy_line("TOTAL",totalused,totalavailable,totalclosed)*" rate $(one_decimal(usage))%")
    elseif cmd == "SIGN"
        parts = ["SIGN"]
        for kind in TYPES
            total = 0
            for level in LEVELS
                run = 0
                for s in level
                    if kind == "BUS"
                        if s.kind == "LARGE" && free_spot(s)
                            run += 1
                        else
                            total += div(run,3)
                            run = 0
                        end
                    elseif s.kind in PREFS[kind] && free_spot(s)
                        total += 1
                    end
                end
                kind == "BUS" && (total += div(run,3))
            end
            append!(parts,[kind,total == 0 ? "FULL" : string(total)])
        end
        push!(out,join(parts," "))
    elseif cmd == "RATES"
        push!(out,"RATES")
        for kind in TYPES
            push!(out,"$kind $(RATES[kind][1]) $(RATES[kind][2])")
        end
        push!(out,"NIGHT $(FEES["NIGHT"]) LOST $(FEES["LOST"]) KWH $(FEES["KWH"])")
    elseif cmd == "PASSES"
        plates = sort(filter(plate -> valid_pass(plate,NOW[]),collect(keys(PASSES))))
        push!(out,"PASSES $(length(plates))")
        for plate in plates
            push!(out,"$plate until $(PASSES[plate])"*(haskey(VEHICLES,plate) ? " IN" : ""))
        end
    elseif cmd == "HISTORY"
        haskey(HISTORY,t[2]) || fail("no history for $(t[2])")
        records = HISTORY[t[2]]
        paid = sum(r.total for r in records)
        push!(out,"HISTORY $(t[2]) visits $(length(records)) paid $paid")
        for r in records
            push!(out,"$(time_text(r.entry)) $(time_text(r.exit)) $(r.location) $(r.kind) $(r.total)"*(r.lost ? " LOST" : ""))
        end
    elseif cmd == "REVENUE"
        push!(out,"REVENUE")
        total = Dict(key=>0 for key in keys(STATS[TYPES[1]]))
        for kind in TYPES
            s = STATS[kind]
            push!(out,"$kind exits $(s["exits"]) parking $(s["parking"]) night $(s["night"]) lost $(s["lost"]) charge $(s["charge"]) total $(s["total"])")
            for (key,value) in s
                total[key] += value
            end
        end
        push!(out,"TOTAL exits $(total["exits"]) parking $(total["parking"]) night $(total["night"]) lost $(total["lost"]) charge $(total["charge"]) total $(total["total"])")
    elseif cmd == "DAILY"
        date = parse(Int,t[2])
        rows = get(DAILY,date,Dict(k=>Dict(f=>0 for f in ("entries","exits","refused","revenue")) for k in TYPES))
        total = Dict(f=>0 for f in ("entries","exits","refused","revenue"))
        lines = String[]
        for kind in TYPES
            s = rows[kind]
            for (key,value) in s
                total[key] += value
            end
            push!(lines,"$kind entries $(s["entries"]) exits $(s["exits"]) refused $(s["refused"]) revenue $(s["revenue"])")
        end
        push!(out,"DAILY $date entries $(total["entries"]) exits $(total["exits"]) refused $(total["refused"]) revenue $(total["revenue"])")
        append!(out,lines)
    elseif cmd == "STATS"
        peaktext = PEAK[] == 0 ? "-" : time_text(PEAK_TIME[])
        push!(out,"STATS parked $(length(VEHICLES)) peak $(PEAK[]) at $peaktext")
        total = Dict(f=>0 for f in ("entries","exits","refused","stay"))
        for kind in (TYPES...,"ALL")
            s = kind == "ALL" ? total : STATS[kind]
            if kind != "ALL"
                for key in keys(total)
                    total[key] += s[key]
                end
            end
            average = s["exits"] == 0 ? 0 : div(s["stay"]*10,s["exits"])
            push!(out,"$kind entries $(s["entries"]) exits $(s["exits"]) refused $(s["refused"]) avg_stay $(one_decimal(average))")
        end
    end
    cmd in ("LEVEL","OPEN","EXIT","MOVE","REBALANCE") && process_queue!(out)
    return out
end
function main()
    for i in 1:parse(Int,readline())
        t = String.(split(readline(),' '))
        hour,minute = parse.(Int,split(t[2],':'))
        NOW[] = (parse(Int,t[1])-1)*1440+60hour+minute
        foreach(println,giveups!())
        try
            foreach(println,execute(t[3:end]))
        catch exception
            exception isa ArgumentError || rethrow()
            println("ERROR ",exception.msg)
        end
    end
end
main()
