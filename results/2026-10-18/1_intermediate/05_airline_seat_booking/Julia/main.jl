using Printf
const CLASSES = ("F", "J", "Y")
const TIERS = Dict("PLATINUM"=>0, "GOLD"=>1, "SILVER"=>2, "NONE"=>3)
struct Seat
    row::Int
    letter::String
    cabin::String
    block::Int
    kind::String
end
Base.@kwdef mutable struct Cabin
    firstrow::Int
    lastrow::Int
    blocks::Vector{String}
    seats::Vector{String} = String[]
    capacity::Int = 0
end
Base.@kwdef mutable struct Aircraft
    id::String
    base::Int
    limit::Int
    cabins::Dict{String,Cabin} = Dict{String,Cabin}()
    seats::Dict{String,Seat} = Dict{String,Seat}()
    exits::Set{Int} = Set{Int}()
    blocked::Set{String} = Set{String}()
end
Base.@kwdef mutable struct Flight
    id::String
    model::Aircraft
    blocked::Set{String}
    occupied::Dict{String,Int} = Dict{String,Int}()
    limits::Dict{String,Int} = Dict{String,Int}()
    closed::Bool = false
    bookings::Vector{String} = String[]
    people::Vector{Int} = Int[]
    volunteers::Vector{Int} = Int[]
end
Base.@kwdef mutable struct Booking
    pnr::String
    flight::String
    people::Vector{Int} = Int[]
    checked::Bool = false
end
Base.@kwdef mutable struct Passenger
    id::Int
    pnr::String
    name::String
    kind::String
    preference::String
    cabin::String
    seat::String = ""
    active::Bool = true
    infant::Int = 0
    adult::Int = 0
    volunteer::Bool = false
end
const AIRCRAFT = Dict{String,Aircraft}()
const FLIGHTS = Dict{String,Flight}()
const FLIGHT_ORDER = String[]
const BOOKINGS = Dict{String,Booking}()
const USED_PNR = Set{String}()
const PEOPLE = Dict{Int,Passenger}()
const STATUSES = Dict{String,String}()
const DEFINITION = Ref{Union{Nothing,Aircraft}}(nothing)
fail(message) = throw(ArgumentError(message))
tier(p) = get(STATUSES,p.name,"NONE")
members(b) = filter(id -> PEOPLE[id].active,b.people)
passengers(f) = filter(id -> PEOPLE[id].active,f.people)
passenger_result(p) = p.kind == "INFANT" ? "LAP" : (isempty(p.seat) ? "UNASSIGNED" : p.seat)
function get_flight(id,open=false)
    haskey(FLIGHTS,id) || fail("unknown flight $id")
    f = FLIGHTS[id]
    open && f.closed && fail("flight $id is closed")
    return f
end
function get_booking(pnr,open=false)
    haskey(BOOKINGS,pnr) && !isempty(members(BOOKINGS[pnr])) || fail("unknown PNR $pnr")
    b = BOOKINGS[pnr]
    get_flight(b.flight,open)
    return b
end
function get_person(b,name)
    for id in members(b)
        PEOPLE[id].name == name && return PEOPLE[id]
    end
    fail("no passenger $name in $(b.pnr)")
end
function cabin(f,class)
    haskey(f.model.cabins,class) || fail("no cabin $class on $(f.id)")
    return f.model.cabins[class]
end
booked(f,class) = count(id -> PEOPLE[id].kind != "INFANT" && PEOPLE[id].cabin == class,passengers(f))
function allowed(f,p,seat,class,vacated=Set{Int}(),assignments=Dict{Int,String}())
    s = get(f.model.seats,seat,nothing)
    (s === nothing || s.cabin != class || seat in f.blocked) && return false
    haskey(f.occupied,seat) && !(f.occupied[seat] in vacated) && return false
    (p.kind == "CHILD" || p.infant != 0) && s.row in f.model.exits && return false
    if p.infant != 0
        for (otherseat,id) in f.occupied
            (id == p.id || id in vacated || PEOPLE[id].infant == 0) && continue
            t = f.model.seats[otherseat]
            t.row == s.row && t.block == s.block && return false
        end
        for (id,otherseat) in assignments
            if id != p.id && PEOPLE[id].infant != 0
                t = f.model.seats[otherseat]
                t.row == s.row && t.block == s.block && return false
            end
        end
    end
    return true
end
function select_seat(f,p,class=p.cabin)
    firstseat = ""
    for seat in f.model.cabins[class].seats
        if allowed(f,p,seat,class)
            isempty(firstseat) && (firstseat = seat)
            !isempty(p.preference) && f.model.seats[seat].kind == p.preference && return seat
        end
    end
    return firstseat
end
function move_to!(f,p,seat)
    !isempty(p.seat) && delete!(f.occupied,p.seat)
    p.seat = seat
    !isempty(seat) && (f.occupied[seat] = p.id)
end
function reassign!(f,output)
    for id in passengers(f)
        p = PEOPLE[id]
        if p.kind != "INFANT" && isempty(p.seat)
            seat = select_seat(f,p)
            if !isempty(seat)
                move_to!(f,p,seat)
                push!(output,"REASSIGNED $(p.pnr) $(p.name) $seat")
            end
        end
    end
end
function fits(f,ids,seats,class)
    assignments = Dict(zip(ids,seats))
    return all(allowed(f,PEOPLE[id],seats[index],class,Set{Int}(),assignments) for (index,id) in enumerate(ids))
end
function group_seats(f,ids,class)
    c = f.model.cabins[class]
    total = length(ids)
    for method in ("BLOCK","ROW")
        for row in c.firstrow:c.lastrow
            blocks = method == "BLOCK" ? c.blocks : [join(c.blocks)]
            for block in blocks
                for x in 1:length(block)-total+1
                    seats = [string(row,block[x+j]) for j in 0:total-1]
                    fits(f,ids,seats,class) && return method,seats
                end
            end
        end
    end
    for height in 2:total
        width = cld(total,height)
        rows = cld(total,width)
        for row in c.firstrow:c.lastrow-rows+1
            for block in c.blocks
                for x in 1:length(block)-width+1
                    seats = [string(row+div(j,width),block[x+mod(j,width)]) for j in 0:total-1]
                    fits(f,ids,seats,class) && return "STACK",seats
                end
            end
        end
    end
    return "SPLIT",String[]
end
removal_targets(p) = p.infant == 0 ? [p.id] : [p.id,p.infant]
function remove_people!(f,ids)
    for id in ids
        p = PEOPLE[id]
        p.active || continue
        move_to!(f,p,"")
        p.active = false
        p.volunteer = false
        p.kind == "INFANT" && (PEOPLE[p.adult].infant = 0)
    end
end
function load_text(seated,seats)
    q = div(seated*1000,seats)
    return string(div(q,10),'.',mod(q,10),'%')
end
seat_key(f,p) = (f.model.seats[p.seat].row,f.model.seats[p.seat].letter)
function execute(line)
    t = String.(split(line,' '))
    command = t[1]
    output = String[]
    if command == "AIRCRAFT"
        DEFINITION[] = Aircraft(id=t[2],base=parse(Int,t[3]),limit=parse(Int,t[4]))
    elseif command == "CABIN"
        model = DEFINITION[]
        class = t[2]
        blocks = t[5:end]
        c = Cabin(firstrow=parse(Int,t[3]),lastrow=parse(Int,t[4]),blocks=blocks)
        for row in c.firstrow:c.lastrow
            for (b,block) in enumerate(blocks)
                for x in eachindex(block)
                    letter = string(block[x])
                    if (b == 1 && x == 1) || (b == length(blocks) && x == length(block))
                        kind = "W"
                    elseif x == 1 || x == length(block)
                        kind = "A"
                    else
                        kind = "M"
                    end
                    seat = string(row,letter)
                    model.seats[seat] = Seat(row,letter,class,b,kind)
                    push!(c.seats,seat)
                end
            end
        end
        model.cabins[class] = c
    elseif command == "EXIT"
        union!(DEFINITION[].exits,parse.(Int,t[2:end]))
    elseif command == "BLOCKED"
        union!(DEFINITION[].blocked,t[2:end])
    elseif command == "END"
        model = DEFINITION[]
        parts = ["AIRCRAFT",model.id]
        for class in CLASSES
            if haskey(model.cabins,class)
                c = model.cabins[class]
                c.capacity = count(seat -> !(seat in model.blocked),c.seats)
                append!(parts,[class,string(c.capacity)])
            end
        end
        AIRCRAFT[model.id] = model
        push!(output,join(parts," "))
        DEFINITION[] = nothing
    elseif command == "FLIGHT"
        haskey(FLIGHTS,t[2]) && fail("duplicate flight $(t[2])")
        haskey(AIRCRAFT,t[3]) || fail("unknown aircraft $(t[3])")
        model = AIRCRAFT[t[3]]
        f = Flight(id=t[2],model=model,blocked=copy(model.blocked))
        parts = ["FLIGHT",f.id,model.id]
        for class in CLASSES
            if haskey(model.cabins,class)
                capacity = model.cabins[class].capacity
                f.limits[class] = div(capacity*(100+parse(Int,t[4])),100)
                append!(parts,[class,"$capacity/$(f.limits[class])"])
            end
        end
        FLIGHTS[f.id] = f
        push!(FLIGHT_ORDER,f.id)
        push!(output,join(parts," "))
    elseif command == "STATUS"
        STATUSES[t[2]] = t[3]
        push!(output,"STATUS $(t[2]) $(t[3])")
    elseif command == "BOOK"
        pnr,flight,class = t[2:4]
        pnr in USED_PNR && fail("duplicate PNR $pnr")
        f = get_flight(flight,true)
        cabin(f,class)
        parsed = [String.(split(token,':')) for token in t[5:end]]
        names = Set{String}()
        for parts in parsed
            parts[1] in names && fail("duplicate name $(parts[1]) in $pnr")
            push!(names,parts[1])
        end
        aboard = Set(PEOPLE[id].name for id in passengers(f))
        for parts in parsed
            parts[1] in aboard && fail("$(parts[1]) already on $flight")
        end
        adults = count(parts -> parts[2] == "ADULT",parsed)
        infants = count(parts -> parts[2] == "INFANT",parsed)
        adults > 0 || fail("no adult in $pnr")
        infants <= adults || fail("too many infants in $pnr")
        booked(f,class)+length(parsed)-infants <= f.limits[class] || fail("limit exceeded for $flight $class")
        b = Booking(pnr=pnr,flight=flight)
        adultids,infantids,seatids = Int[],Int[],Int[]
        for parts in parsed
            id = length(PEOPLE)+1
            preference = length(parts) == 3 ? parts[3] : ""
            p = Passenger(id=id,pnr=pnr,name=parts[1],kind=parts[2],preference=preference,cabin=class)
            PEOPLE[id] = p
            push!(b.people,id)
            push!(f.people,id)
            p.kind == "ADULT" && push!(adultids,id)
            if p.kind == "INFANT"
                push!(infantids,id)
            else
                push!(seatids,id)
            end
        end
        for (index,id) in enumerate(infantids)
            PEOPLE[id].adult = adultids[index]
            PEOPLE[adultids[index]].infant = id
        end
        BOOKINGS[pnr] = b
        push!(USED_PNR,pnr)
        push!(f.bookings,pnr)
        if length(seatids) == 1
            method = "SINGLE"
            p = PEOPLE[seatids[1]]
            move_to!(f,p,select_seat(f,p))
        else
            method,seats = group_seats(f,seatids,class)
            for (index,id) in enumerate(seatids)
                seat = method == "SPLIT" ? select_seat(f,PEOPLE[id]) : seats[index]
                move_to!(f,PEOPLE[id],seat)
            end
        end
        parts = ["BOOKED",pnr,flight,class,method]
        append!(parts,[PEOPLE[id].name*":"*passenger_result(PEOPLE[id]) for id in b.people])
        push!(output,join(parts," "))
    elseif command == "FIND"
        lines = String[]
        for flight in FLIGHT_ORDER
            f = FLIGHTS[flight]
            for id in passengers(f)
                p = PEOPLE[id]
                if p.name == t[2]
                    state = f.closed ? "CLOSED" : "OPEN"
                    push!(lines,"$flight $(p.pnr) $(p.cabin) $(passenger_result(p)) $state")
                end
            end
        end
        push!(output,"FIND $(t[2]) $(get(STATUSES,t[2],"NONE")) $(length(lines))")
        append!(output,lines)
    elseif command in ("SEAT","SWAP","CANCEL","CHECKIN","VOLUNTEER","INFO")
        b = get_booking(t[2],command != "INFO")
        f = FLIGHTS[b.flight]
        if command == "INFO"
            state = b.checked ? "CHECKED" : "NOT-CHECKED"
            push!(output,"INFO $(b.pnr) $(b.flight) $(length(members(b))) $state")
            for id in members(b)
                p = PEOPLE[id]
                push!(output,"$(p.name) $(p.kind) $(p.cabin) $(passenger_result(p))")
            end
        elseif command == "CHECKIN"
            b.checked && fail("$(b.pnr) already checked in")
            b.checked = true
            push!(output,"CHECKIN $(b.pnr) $(length(members(b)))")
        elseif command == "CANCEL"
            targets = members(b)
            if length(t) == 3
                p = get_person(b,t[3])
                targetset = Set(removal_targets(p))
                remaining = filter(id -> !(id in targetset),members(b))
                !isempty(remaining) && !any(PEOPLE[id].kind == "ADULT" for id in remaining) && fail("$(b.pnr) would have no adult")
                targets = filter(id -> id in targetset,members(b))
            end
            names = [PEOPLE[id].name for id in targets]
            remove_people!(f,targets)
            push!(output,"CANCELLED $(b.pnr) "*join(names," "))
            reassign!(f,output)
        else
            p = get_person(b,t[3])
            if command == "SWAP"
                b2 = get_booking(t[4],true)
                q = get_person(b2,t[5])
                p.id == q.id && fail("cannot swap $(p.name) with itself")
                for person in (p,q)
                    person.kind == "INFANT" && fail("infant $(person.name) has no seat")
                end
                b.flight == b2.flight || fail("$(b.pnr) and $(b2.pnr) are on different flights")
                p.cabin == q.cabin || fail("$(p.name) and $(q.name) are in different cabins")
                for person in (p,q)
                    isempty(person.seat) && fail("$(person.name) has no seat")
                end
                vacated = Set([p.id,q.id])
                assignments = Dict(p.id=>q.seat,q.id=>p.seat)
                if !allowed(f,p,q.seat,p.cabin,vacated,assignments) || !allowed(f,q,p.seat,q.cabin,vacated,assignments)
                    fail("swap of $(p.name) and $(q.name) breaks seating rules")
                end
                oldp,oldq = p.seat,q.seat
                move_to!(f,p,"")
                move_to!(f,q,"")
                move_to!(f,p,oldq)
                move_to!(f,q,oldp)
                push!(output,"SWAPPED $(b.pnr) $(p.name) $(p.seat) $(b2.pnr) $(q.name) $(q.seat)")
                reassign!(f,output)
            elseif command == "VOLUNTEER"
                p.kind == "ADULT" && p.infant == 0 || fail("$(p.name) cannot volunteer")
                isempty(p.seat) && fail("$(p.name) has no seat")
                p.volunteer && fail("$(p.name) already volunteered")
                p.volunteer = true
                push!(f.volunteers,p.id)
                push!(output,"VOLUNTEER $(p.pnr) $(p.name) $(p.seat)")
            else
                seat = t[4]
                p.kind == "INFANT" && fail("infant $(p.name) has no seat")
                s = get(f.model.seats,seat,nothing)
                s !== nothing && s.cabin == p.cabin || fail("no seat $seat in cabin $(p.cabin)")
                seat in f.blocked && fail("seat $seat is blocked")
                haskey(f.occupied,seat) && fail("seat $seat is occupied")
                (p.kind == "CHILD" || p.infant != 0) && s.row in f.model.exits && fail("exit row $(s.row) not allowed for $(p.name)")
                allowed(f,p,seat,p.cabin) || fail("infant limit reached at $seat")
                old = p.seat
                move_to!(f,p,seat)
                push!(output,"MOVED $(p.pnr) $(p.name) $old -> $seat")
                reassign!(f,output)
            end
        end
    else
        f = get_flight(t[2],command in ("UPGRADE","CLOSE","BLOCK","UNBLOCK"))
        classes = filter(class -> haskey(f.model.cabins,class),collect(CLASSES))
        if command == "UPGRADE"
            total = 0
            for index in 1:length(classes)-1
                higher,lower = classes[index:index+1]
                targets = filter(id -> PEOPLE[id].cabin == lower && PEOPLE[id].kind == "ADULT" && PEOPLE[id].infant == 0 && tier(PEOPLE[id]) != "NONE",passengers(f))
                sort!(targets;by=id -> (TIERS[tier(PEOPLE[id])],id))
                for id in targets
                    booked(f,higher) >= f.limits[higher] && break
                    p = PEOPLE[id]
                    seat = select_seat(f,p,higher)
                    isempty(seat) && break
                    old = passenger_result(p)
                    move_to!(f,p,seat)
                    p.cabin = higher
                    total += 1
                    push!(output,"UPGRADED $(p.pnr) $(p.name) $lower $old -> $higher $seat")
                end
            end
            reassign!(f,output)
            push!(output,"UPGRADE $(f.id) $total")
        elseif command == "CLOSE"
            for pnr in f.bookings
                b = BOOKINGS[pnr]
                ids = members(b)
                if !isempty(ids) && !b.checked
                    push!(output,"NOSHOW $pnr $(length(ids))")
                    remove_people!(f,ids)
                end
            end
            reassign!(f,output)
            denied,total = 0,0
            rates = Dict("F"=>500,"J"=>300,"Y"=>150)
            for class in classes
                targets = filter(id -> PEOPLE[id].active && PEOPLE[id].volunteer && !isempty(PEOPLE[id].seat) && PEOPLE[id].cabin == class,f.volunteers)
                for id in targets
                    p = PEOPLE[id]
                    useful = any(passengers(f)) do waitingid
                        waiting = PEOPLE[waitingid]
                        waiting.kind != "INFANT" && waiting.cabin == class && isempty(waiting.seat) && allowed(f,waiting,p.seat,class,Set([id]))
                    end
                    if useful
                        amount = rates[class]
                        push!(output,"DENIED VOLUNTARY $(p.pnr) $(p.name) $class $amount")
                        remove_people!(f,[id])
                        denied += 1
                        total += amount
                        reassign!(f,output)
                    end
                end
            end
            for id in passengers(f)
                p = PEOPLE[id]
                if p.active && p.kind != "INFANT" && isempty(p.seat)
                    amount = rates[p.cabin]*2
                    p.kind == "CHILD" && (amount = div(amount,2))
                    push!(output,"DENIED INVOLUNTARY $(p.pnr) $(p.name) $(p.cabin) $amount")
                    remove_people!(f,removal_targets(p))
                    denied += 1
                    total += amount
                end
            end
            f.closed = true
            push!(output,"CLOSED $(f.id) denied $denied compensation $total")
        elseif command in ("BLOCK","UNBLOCK")
            seat = t[3]
            haskey(f.model.seats,seat) || fail("no seat $seat on $(f.id)")
            blocked = seat in f.blocked
            command == "BLOCK" && blocked && fail("seat $seat is blocked")
            command == "UNBLOCK" && !blocked && fail("seat $seat is not blocked")
            push!(output,"$command $(f.id) $seat")
            if command == "BLOCK"
                push!(f.blocked,seat)
                if haskey(f.occupied,seat)
                    p = PEOPLE[f.occupied[seat]]
                    move_to!(f,p,"")
                    move_to!(f,p,select_seat(f,p))
                    push!(output,"DISPLACED $(p.pnr) $(p.name) $seat -> $(passenger_result(p))")
                end
            else
                delete!(f.blocked,seat)
            end
            reassign!(f,output)
        elseif command == "MAP"
            push!(output,"MAP $(f.id)")
            for class in classes
                c = f.model.cabins[class]
                push!(output,"CABIN $class")
                push!(output,"   "*join(c.blocks," "))
                for row in c.firstrow:c.lastrow
                    blocks = String[]
                    for block in c.blocks
                        text = ""
                        for letter in block
                            seat = string(row,letter)
                            if seat in f.blocked
                                text *= "#"
                            elseif haskey(f.occupied,seat)
                                text *= "X"
                            else
                                text *= row in f.model.exits ? "E" : "."
                            end
                        end
                        push!(blocks,text)
                    end
                    push!(output,@sprintf("%2d ",row)*join(blocks," "))
                end
            end
        elseif command in ("MANIFEST","BOARDING")
            seated,unassigned = Int[],Int[]
            infants = 0
            for id in passengers(f)
                p = PEOPLE[id]
                if p.kind == "INFANT"
                    infants += 1
                elseif isempty(p.seat)
                    push!(unassigned,id)
                else
                    push!(seated,id)
                end
            end
            if command == "MANIFEST"
                sort!(seated;by=id -> seat_key(f,PEOPLE[id]))
                push!(output,"MANIFEST $(f.id) seated $(length(seated)) unassigned $(length(unassigned)) infants $infants")
                for id in vcat(seated,unassigned)
                    p = PEOPLE[id]
                    parts = [isempty(p.seat) ? "---" : p.seat,p.cabin,p.pnr,p.name,p.kind]
                    p.infant != 0 && push!(parts,"+"*PEOPLE[p.infant].name)
                    tier(p) != "NONE" && push!(parts,tier(p))
                    BOOKINGS[p.pnr].checked && push!(parts,"CHECKED")
                    p.volunteer && push!(parts,"VOL")
                    push!(output,join(parts," "))
                end
            else
                groups = Dict{Int,String}()
                sortkeys = Dict{Int,Tuple}()
                for id in seated
                    p = PEOPLE[id]
                    s = f.model.seats[p.seat]
                    hasinfant = any(PEOPLE[member].kind == "INFANT" for member in members(BOOKINGS[p.pnr]))
                    if hasinfant
                        group,key = "PRE",(0,s.row,s.letter)
                    elseif p.cabin != "Y"
                        group,key = "CABIN",(1,s.row,s.letter)
                    elseif TIERS[tier(p)] <= 1
                        group,key = "TIER",(2,s.row,s.letter)
                    else
                        zone = div(s.row-f.model.cabins["Y"].firstrow,5)+1
                        group = "ZONE$zone"
                        key = (3,-zone,findfirst(==(s.kind),["W","M","A"]),-s.row,s.letter)
                    end
                    groups[id],sortkeys[id] = group,key
                end
                sort!(seated;by=id -> sortkeys[id])
                push!(output,"BOARDING $(f.id) $(length(seated))")
                for (index,id) in enumerate(seated)
                    p = PEOPLE[id]
                    push!(output,"$index $(groups[id]) $(p.seat) $(p.pnr) $(p.name)")
                end
            end
        elseif command == "LOADFACTOR"
            push!(output,"LOADFACTOR $(f.id)")
            totalseated,totalseats = 0,0
            for class in classes
                seats = count(seat -> !(seat in f.blocked),f.model.cabins[class].seats)
                seated = count(id -> PEOPLE[id].cabin == class && !isempty(PEOPLE[id].seat),passengers(f))
                push!(output,"$class $seated/$seats $(load_text(seated,seats)) booked $(booked(f,class))/$(f.limits[class])")
                totalseated += seated
                totalseats += seats
            end
            push!(output,"ALL $totalseated/$totalseats $(load_text(totalseated,totalseats))")
        elseif command == "BALANCE"
            weight,moment = 0,0
            for id in passengers(f)
                p = PEOPLE[id]
                if !isempty(p.seat)
                    w = p.kind == "ADULT" ? 80 : 40
                    p.infant != 0 && (w += 10)
                    weight += w
                    moment += w*(f.model.seats[p.seat].row-f.model.base)
                end
            end
            limit = f.model.limit
            if moment < -limit
                verdict = "NOSE-HEAVY"
            elseif moment > limit
                verdict = "TAIL-HEAVY"
            else
                verdict = "OK"
            end
            push!(output,"BALANCE $(f.id) weight $weight moment $moment limit $limit $verdict")
        elseif command == "AVAIL"
            class = t[3]
            c = cabin(f,class)
            counts = Dict("W"=>0,"M"=>0,"A"=>0,"EXIT"=>0)
            free = 0
            for seat in c.seats
                if !(seat in f.blocked) && !haskey(f.occupied,seat)
                    s = f.model.seats[seat]
                    free += 1
                    counts[s.kind] += 1
                    s.row in f.model.exits && (counts["EXIT"] += 1)
                end
            end
            push!(output,"AVAIL $(f.id) $class free $free W $(counts["W"]) M $(counts["M"]) A $(counts["A"]) EXIT $(counts["EXIT"])")
        end
    end
    return output
end
function main()
    total = parse(Int,readline())
    for index in 1:total
        line = readline()
        try
            foreach(println,execute(line))
        catch exception
            exception isa ArgumentError || rethrow()
            println("ERROR ",exception.msg)
        end
    end
end
main()
