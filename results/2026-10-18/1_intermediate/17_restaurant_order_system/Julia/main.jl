using Printf

const STATIONS = ("GRILL", "FRY", "COLD", "BAR")
const COURSES = ("DRINK", "STARTER", "MAIN", "DESSERT")

struct CommandError <: Exception
    reason::String
end
Base.showerror(io::IO, error::CommandError) = print(io, error.reason)
fail(reason::String) = throw(CommandError(reason))

cents(text::String) = parse(Int, replace(text, "." => ""))
money(value::Int) = @sprintf("%d.%02d", fld(value, 100), mod(value, 100))
clock(time::Int) = @sprintf("%02d:%02d", fld(660 + time, 60), mod(660 + time, 60))
rounded(value::Int, rate::Int) = fld(value * rate + 50, 100)

mutable struct OrderLine
    id::Int
    check::Any
    seat::Int
    item::String
    quantity::Int
    station::String
    prep::Int
    price::Int
    course::String
    status::String
    reason::Union{Nothing, String}
    fire::Int
    ready::Int
    started::Bool
end

mutable struct ServerInfo
    name::String
    parties::Int
    sales::Int
    tips::Int
end

mutable struct TableInfo
    number::Int
    seats::Int
    check::Any
end

mutable struct Check
    party::String
    size::Int
    table::TableInfo
    server::ServerInfo
    seated::Int
    lines::Vector{OrderLine}
    paid::Int
    discount::Int
    closed::Bool
end

mutable struct MenuItem
    name::String
    station::String
    prep::Int
    price::Int
    course::String
    stock::Union{Nothing, Int}
end

mutable struct StationState
    capacity::Int
    up::Bool
    queue::Vector{OrderLine}
    cooking::Vector{OrderLine}
    tickets::Vector{Int}
    remakes::Int
end

struct WaitingEntry
    party::String
    size::Int
    joined::Int
end

mutable struct Restaurant
    now::Int
    tables::Dict{Int, TableInfo}
    servers::Vector{ServerInfo}
    waiting::Vector{WaitingEntry}
    menu::Dict{String, MenuItem}
    lines::Vector{OrderLine}
    stations::Dict{String, StationState}
    happy_rate::Int
    happy_end::Int
    covers::Int
    parties::Int
    turns::Int
    stay::Int
    sales::Dict{String, Int}
    totals::Dict{String, Int}
    payments::Dict{String, Int}
    tips::Int
    comps::Int
    comp_amount::Int
    voids::Int
    served::Dict{String, Int}
    output::Vector{String}
end

function Restaurant()
    stations = Dict(
        name => StationState(name == "BAR" ? 2 : 1, true,
                             OrderLine[], OrderLine[], Int[], 0)
        for name in STATIONS
    )
    Restaurant(
        0, Dict{Int, TableInfo}(), ServerInfo[], WaitingEntry[],
        Dict{String, MenuItem}(), OrderLine[], stations,
        0, 0, 0, 0, 0, 0,
        Dict(name => 0 for name in COURSES),
        Dict(key => 0 for key in ("subtotal", "discount", "service", "tax", "total")),
        Dict("CASH" => 0, "CARD" => 0),
        0, 0, 0, 0, Dict{String, Int}(), String[]
    )
end

emit!(r::Restaurant, args...) = push!(r.output, join(string.(args), " "))

function table_info(r::Restaurant, text::String)
    number = parse(Int, text)
    haskey(r.tables, number) || fail("unknown table $text")
    r.tables[number]
end

function check_info(r::Restaurant, text::String)
    item = table_info(r, text)
    item.check === nothing && fail("table $text is free")
    item.check::Check
end

function unlocked(check::Check)
    check.paid > 0 && fail("check for table $(check.table.number) is locked")
end

function line_info(r::Restaurant, text::String)
    number = parse(Int, text)
    1 <= number <= length(r.lines) || fail("unknown line $text")
    r.lines[number]
end

function modifiable(line::OrderLine)
    line.status == "VOID" && fail("#$(line.id) is void")
    line.check.closed && fail("#$(line.id) is on a closed check")
    unlocked(line.check)
end

active_lines(check::Check) = [line for line in check.lines if line.status != "VOID"]

function unserved(check::Check)
    quantity = count(line -> line.status != "SERVED", active_lines(check))
    quantity > 0 && fail("table $(check.table.number) has $quantity unserved items")
end

function station_info(r::Restaurant, name::String)
    haskey(r.stations, name) || fail("unknown station $name")
    r.stations[name]
end

function require_course(name::String)
    name in COURSES || fail("unknown course $name")
end

function menu_item(r::Restaurant, name::String)
    haskey(r.menu, name) || fail("unknown item $name")
    r.menu[name]
end

function server_load(r::Restaurant, server::ServerInfo)
    count(item -> item.check !== nothing && item.check.server === server, values(r.tables))
end

function select_table(r::Restaurant, size::Int)
    candidates = [item for item in values(r.tables)
                  if item.check === nothing && item.seats >= size]
    isempty(candidates) && return nothing
    sort!(candidates; by=item -> (item.seats, item.number))
    first(candidates)
end

function seat_party!(r::Restaurant, party::String, size::Int, item::TableInfo)
    index = argmin([server_load(r, server) for server in r.servers])
    server = r.servers[index]
    check = Check(party, size, item, server, r.now, OrderLine[], 0, 0, false)
    item.check = check
    server.parties += 1
    r.covers += size
    r.parties += 1
    check
end

function process_waiting!(r::Restaurant)
    remaining = WaitingEntry[]
    for entry in r.waiting
        item = select_table(r, entry.size)
        if item === nothing
            push!(remaining, entry)
        else
            check = seat_party!(r, entry.party, entry.size, item)
            emit!(r, "SEATED", entry.party, entry.size, "table", item.number,
                  "server", check.server.name, "waited", r.now - entry.joined)
        end
    end
    r.waiting = remaining
end

line_amount(line::OrderLine) = line.reason === nothing ? line.price * line.quantity : 0

function check_amounts(check::Check)
    subtotal = sum(line_amount, active_lines(check); init=0)
    discount = rounded(subtotal, check.discount)
    after = subtotal - discount
    service = check.size >= 6 ? rounded(after, 18) : 0
    tax = rounded(after, 8)
    total = after + service + tax
    (subtotal=subtotal, discount=discount, service=service,
     tax=tax, total=total, due=total-check.paid)
end

function close_check!(r::Restaurant, check::Check)
    amounts = check_amounts(check)
    r.turns += 1
    r.stay += r.now - check.seated
    for line in active_lines(check)
        r.sales[line.course] += line_amount(line)
    end
    for field in ("subtotal", "discount", "service", "tax", "total")
        r.totals[field] += getproperty(amounts, Symbol(field))
    end
    check.server.sales += amounts.total
    check.closed = true
    check.table.check = nothing
    emit!(r, "FREE", "table", check.table.number, check.party,
          "stayed", r.now - check.seated)
    process_waiting!(r)
end

function start_station!(station::StationState, time::Int)
    while station.up && !isempty(station.queue) &&
          length(station.cooking) < station.capacity
        line = popfirst!(station.queue)
        line.status = "COOKING"
        line.ready = time + line.prep
        line.started = true
        push!(station.cooking, line)
    end
end

function tick!(r::Restaurant, minutes::Int)
    finish = r.now + minutes
    emit!(r, "TICK", clock(finish))
    while true
        cooking = [line for name in STATIONS for line in r.stations[name].cooking]
        isempty(cooking) && break
        time = minimum(line.ready for line in cooking)
        time > finish && break
        for name in STATIONS
            station = r.stations[name]
            completed = [line for line in station.cooking if line.ready == time]
            filter!(line -> line.ready != time, station.cooking)
            sort!(completed; by=line -> line.id)
            for line in completed
                line.status = "READY"
                push!(station.tickets, time - line.fire)
                emit!(r, "READY", clock(time), name, "#" * string(line.id), line.item,
                      "x" * string(line.quantity), "table", line.check.table.number,
                      "seat", line.seat)
            end
        end
        for name in STATIONS
            start_station!(r.stations[name], time)
        end
    end
    r.now = finish
end

function seat_totals(check::Check)
    totals = Dict{Int, Int}()
    for line in active_lines(check)
        totals[line.seat] = get(totals, line.seat, 0) + line_amount(line)
    end
    totals
end

function allocate(values::Dict{Int, Int}, rate::Int)
    result = Dict(seat => fld(value * rate, 100) for (seat, value) in values)
    left = rounded(sum(Base.values(values); init=0), rate) -
           sum(Base.values(result); init=0)
    order = sort(collect(keys(values)); by=seat -> (-mod(values[seat] * rate, 100), seat))
    for seat in order[1:left]
        result[seat] += 1
    end
    result
end

function show_bill!(r::Restaurant, check::Check)
    emit!(r, "BILL", "table", check.table.number, check.party, "guests", check.size)
    totals = seat_totals(check)
    for seat in sort(collect(keys(totals)))
        emit!(r, "SEAT", seat, money(totals[seat]))
        for line in active_lines(check)
            line.seat == seat || continue
            if line.reason === nothing
                emit!(r, "#" * string(line.id), line.item, "x" * string(line.quantity),
                      money(line_amount(line)))
            else
                emit!(r, "#" * string(line.id), line.item, "x" * string(line.quantity),
                      money(line_amount(line)), "COMP", line.reason)
            end
        end
    end
    amounts = check_amounts(check)
    emit!(r, "SUBTOTAL", money(amounts.subtotal))
    if check.discount != 0
        emit!(r, "DISCOUNT", "$(check.discount)%", money(amounts.discount))
    end
    check.size >= 6 && emit!(r, "SERVICE", money(amounts.service))
    emit!(r, "TAX", money(amounts.tax))
    emit!(r, "TOTAL", money(amounts.total))
    if check.paid > 0
        emit!(r, "PAID", money(check.paid))
        emit!(r, "DUE", money(amounts.due))
    end
end

function show_report!(r::Restaurant)
    emit!(r, "REPORT", clock(r.now))
    emit!(r, "COVERS", r.covers, "parties", r.parties)
    emit!(r, "TURNS", r.turns, "avg_stay",
          r.turns > 0 ? fld(r.stay, r.turns) : "-")
    sales = Any["SALES"]
    for course in COURSES
        append!(sales, (course, money(r.sales[course])))
    end
    emit!(r, sales...)
    fields = Any["TOTALS"]
    for field in ("subtotal", "discount", "service", "tax", "total")
        append!(fields, (field, money(r.totals[field])))
    end
    emit!(r, fields...)
    emit!(r, "PAYMENTS", "cash", money(r.payments["CASH"]),
          "card", money(r.payments["CARD"]), "tips", money(r.tips))
    emit!(r, "COMPS", r.comps, money(r.comp_amount), "VOIDS", r.voids)
    top = sort(collect(r.served); by=kv -> (-kv.second, kv.first))
    for (rank, entry) in enumerate(top[1:min(3, length(top))])
        emit!(r, "TOP", rank, entry.first, entry.second)
    end
    for name in STATIONS
        station = r.stations[name]
        tickets = station.tickets
        emit!(r, name, "tickets", length(tickets),
              "avg", isempty(tickets) ? "-" : fld(sum(tickets), length(tickets)),
              "max", isempty(tickets) ? "-" : maximum(tickets),
              "remakes", station.remakes)
    end
    for server in r.servers
        emit!(r, "SERVER", server.name, "tables", server_load(r, server),
              "parties", server.parties, "sales", money(server.sales),
              "tips", money(server.tips))
    end
end

function run_command!(r::Restaurant, command::String, a::Vector{String})
    if command == "TABLE"
        number = parse(Int, a[1])
        haskey(r.tables, number) && fail("table $(a[1]) already exists")
        item = TableInfo(number, parse(Int, a[2]), nothing)
        r.tables[number] = item
        emit!(r, "TABLE", number, "seats", item.seats)
        process_waiting!(r)
    elseif command == "STAFF"
        any(server.name == a[1] for server in r.servers) &&
            fail("$(a[1]) is already on duty")
        push!(r.servers, ServerInfo(a[1], 0, 0, 0))
        emit!(r, "STAFF", a[1])
    elseif command == "SEAT"
        for item in values(r.tables)
            if item.check !== nothing && item.check.party == a[1]
                fail("$(a[1]) is already seated at table $(item.number)")
            end
        end
        any(entry.party == a[1] for entry in r.waiting) &&
            fail("$(a[1]) is already waiting")
        size = parse(Int, a[2])
        any(item.seats >= size for item in values(r.tables)) ||
            fail("no table for party of $size")
        isempty(r.servers) && fail("no server on duty")
        item = select_table(r, size)
        if item === nothing
            push!(r.waiting, WaitingEntry(a[1], size, r.now))
            emit!(r, "WAIT", a[1], size, "position", length(r.waiting))
        else
            check = seat_party!(r, a[1], size, item)
            emit!(r, "SEAT", a[1], size, "table", item.number,
                  "server", check.server.name)
        end
    elseif command == "CANCEL"
        index = findfirst(entry -> entry.party == a[1], r.waiting)
        index === nothing && fail("$(a[1]) is not waiting")
        entry = r.waiting[index]
        deleteat!(r.waiting, index)
        emit!(r, "CANCEL", entry.party, entry.size, "waited", r.now - entry.joined)
    elseif command == "MOVE"
        source = table_info(r, a[1])
        destination = table_info(r, a[2])
        source.check === nothing && fail("table $(a[1]) is free")
        destination.check !== nothing && fail("table $(a[2]) is occupied")
        check = source.check::Check
        destination.seats < check.size &&
            fail("table $(a[2]) is too small for $(check.party)")
        source.check = nothing
        destination.check = check
        check.table = destination
        emit!(r, "MOVE", check.party, "table", source.number, "->", destination.number)
        process_waiting!(r)
    elseif command == "MENU"
        station_info(r, a[2])
        require_course(a[5])
        previous = get(r.menu, a[1], nothing)
        item = MenuItem(a[1], a[2], parse(Int, a[3]), cents(a[4]), a[5],
                        previous === nothing ? nothing : previous.stock)
        r.menu[a[1]] = item
        emit!(r, "MENU", previous === nothing ? "ADD" : "UPDATE",
              item.name, item.station, item.prep, money(item.price), item.course)
    elseif command == "STOCK"
        item = menu_item(r, a[1])
        item.stock = parse(Int, a[2])
        emit!(r, "STOCK", item.name, item.stock)
    elseif command == "HAPPY"
        r.happy_rate = parse(Int, a[1])
        r.happy_end = r.now + parse(Int, a[2])
        emit!(r, "HAPPY", "$(r.happy_rate)%", "until", clock(r.happy_end))
    elseif command == "ITEMS"
        items = sort(collect(values(r.menu)); by=item ->
            (findfirst(==(item.course), COURSES), item.name))
        emit!(r, "ITEMS", length(items))
        for item in items
            emit!(r, item.course, item.name, item.station, item.prep,
                  money(item.price), item.stock === nothing ? "-" : item.stock)
        end
    elseif command == "ORDER"
        check = check_info(r, a[1])
        unlocked(check)
        seat = parse(Int, a[2])
        seat > check.size && fail("seat $seat out of range for table $(a[1])")
        item = menu_item(r, a[3])
        quantity = parse(Int, a[4])
        if item.stock !== nothing && item.stock < quantity
            fail("only $(item.stock) $(item.name) left")
        end
        happy = item.course == "DRINK" && r.now < r.happy_end
        price = item.price - (happy ? rounded(item.price, r.happy_rate) : 0)
        line = OrderLine(length(r.lines)+1, check, seat, item.name, quantity,
                         item.station, item.prep, price, item.course,
                         "ORDERED", nothing, 0, 0, false)
        push!(r.lines, line)
        push!(check.lines, line)
        entry = Any["ORDER", "#" * string(line.id), "table", check.table.number,
                    "seat", seat, item.name, "x" * string(quantity), money(line_amount(line))]
        happy && push!(entry, "HAPPY")
        emit!(r, entry...)
        if item.stock !== nothing
            item.stock -= quantity
            item.stock == 0 && emit!(r, "SOLDOUT", item.name)
        end
    elseif command == "FIRE"
        check = check_info(r, a[1])
        require_course(a[2])
        lines = [line for line in check.lines
                 if line.course == a[2] && line.status == "ORDERED"]
        isempty(lines) && fail("nothing to fire for $(a[2]) at table $(a[1])")
        if a[2] in ("MAIN", "DESSERT")
            earlier = a[2] == "MAIN" ? ("STARTER",) : ("STARTER", "MAIN")
            for before in earlier
                any(line.course == before && line.status == "ORDERED"
                    for line in check.lines) && fail("fire $before first")
            end
        end
        for line in lines
            line.status = "QUEUED"
            line.fire = r.now
            push!(r.stations[line.station].queue, line)
        end
        emit!(r, "FIRE", "table", check.table.number, a[2],
              ["#" * string(line.id) for line in lines]...)
        for name in STATIONS
            start_station!(r.stations[name], r.now)
        end
    elseif command == "TICK"
        tick!(r, parse(Int, a[1]))
    elseif command == "SERVE"
        check = check_info(r, a[1])
        lines = [line for line in check.lines if line.status == "READY"]
        isempty(lines) && fail("nothing ready for table $(a[1])")
        for line in lines
            line.status = "SERVED"
            r.served[line.item] = get(r.served, line.item, 0) + line.quantity
        end
        emit!(r, "SERVE", "table", check.table.number,
              ["#" * string(line.id) for line in lines]...)
    elseif command == "RUSH"
        line = line_info(r, a[1])
        line.status == "QUEUED" || fail("#$(line.id) is not queued")
        queue = r.stations[line.station].queue
        filter!(other -> other !== line, queue)
        pushfirst!(queue, line)
        emit!(r, "RUSH", "#" * string(line.id), line.station)
    elseif command == "REMAKE"
        line = line_info(r, a[1])
        line.check.closed && fail("#$(line.id) is on a closed check")
        line.status in ("READY", "SERVED") ||
            fail("#$(line.id) is not ready or served")
        line.status = "QUEUED"
        line.fire = r.now
        station = r.stations[line.station]
        pushfirst!(station.queue, line)
        station.remakes += 1
        emit!(r, "REMAKE", "#" * string(line.id), line.item, line.station)
        start_station!(station, r.now)
    elseif command == "VOID"
        line = line_info(r, a[1])
        line.status == "VOID" && fail("#$(line.id) is already void")
        line.started && fail("#$(line.id) has already started")
        if line.status == "QUEUED"
            filter!(other -> other !== line, r.stations[line.station].queue)
        end
        line.status = "VOID"
        item = r.menu[line.item]
        if item.stock !== nothing
            item.stock += line.quantity
        end
        r.voids += 1
        emit!(r, "VOID", "#" * string(line.id), line.item, "x" * string(line.quantity))
    elseif command == "STATION"
        station = station_info(r, a[1])
        a[2] == "DOWN" && !station.up && fail("station $(a[1]) is already down")
        a[2] == "UP" && station.up && fail("station $(a[1]) is not down")
        station.up = a[2] == "UP"
        station.up && start_station!(station, r.now)
        emit!(r, "STATION", a[1], a[2])
    elseif command in ("COMP", "TRANSFER")
        line = line_info(r, a[1])
        modifiable(line)
        if command == "COMP"
            line.reason !== nothing && fail("#$(line.id) is already comped")
            amount = line_amount(line)
            emit!(r, "COMP", "#" * string(line.id), line.item, money(amount), a[2])
            r.comps += 1
            r.comp_amount += amount
            line.reason = a[2]
        else
            seat = parse(Int, a[2])
            seat > line.check.size &&
                fail("seat $seat out of range for table $(line.check.table.number)")
            seat == line.seat && fail("#$(line.id) is already on seat $seat")
            emit!(r, "TRANSFER", "#" * string(line.id), "seat", line.seat, "->", seat)
            line.seat = seat
        end
    elseif command == "DISCOUNT"
        check = check_info(r, a[1])
        unlocked(check)
        check.discount = parse(Int, a[2])
        emit!(r, "DISCOUNT", "table", check.table.number, "$(check.discount)%")
    elseif command == "BILL"
        show_bill!(r, check_info(r, a[1]))
    elseif command == "SPLIT"
        check = check_info(r, a[1])
        amounts = check_amounts(check)
        amounts.due == 0 && fail("nothing to split for table $(a[1])")
        if a[2] == "EVEN"
            ways = parse(Int, a[3])
            ways > check.size && fail("cannot split table $(a[1]) $ways ways")
            emit!(r, "SPLIT", "table", check.table.number, "EVEN", ways,
                  "due", money(amounts.due))
            quotient, remainder = divrem(amounts.due, ways)
            for index in 1:ways
                emit!(r, "PAYER", index, money(quotient + (index <= remainder ? 1 : 0)))
            end
        else
            check.paid > 0 && fail("table $(a[1]) has payments")
            seatValues = seat_totals(check)
            discounts = allocate(seatValues, check.discount)
            after = Dict(seat => subtotal - discounts[seat] for (seat, subtotal) in seatValues)
            services = allocate(after, check.size >= 6 ? 18 : 0)
            taxes = allocate(after, 8)
            emit!(r, "SPLIT", "table", check.table.number, "BYSEAT",
                  "total", money(amounts.total))
            for seat in sort(collect(keys(seatValues)))
                emit!(r, "SEAT", seat, "subtotal", money(seatValues[seat]),
                      "discount", money(discounts[seat]), "service", money(services[seat]),
                      "tax", money(taxes[seat]),
                      "total", money(after[seat]+services[seat]+taxes[seat]))
            end
        end
    elseif command == "PAY"
        check = check_info(r, a[1])
        a[2] in ("CASH", "CARD") || fail("unknown method $(a[2])")
        unserved(check)
        due = check_amounts(check).due
        due == 0 && fail("nothing to pay for table $(a[1])")
        amount = cents(a[3])
        applied = min(amount, due)
        check.paid += applied
        r.payments[a[2]] += applied
        if amount < due
            emit!(r, "PAY", "table", check.table.number, a[2], money(amount),
                  "remaining", money(due - amount))
        else
            emit!(r, "PAY", "table", check.table.number, a[2], money(amount),
                  a[2] == "CASH" ? "change" : "tip", money(amount - due))
            if a[2] == "CARD"
                r.tips += amount - due
                check.server.tips += amount - due
            end
            close_check!(r, check)
        end
    elseif command == "CLOSE"
        check = check_info(r, a[1])
        unserved(check)
        due = check_amounts(check).due
        due != 0 && fail("table $(a[1]) still owes $(money(due))")
        close_check!(r, check)
    elseif command == "STATUS"
        check = check_info(r, a[1])
        emit!(r, "STATUS", "table", check.table.number, check.party, "guests",
              check.size, "since", clock(check.seated))
        for line in check.lines
            fields = Any["#" * string(line.id), "seat", line.seat, line.item,
                         "x" * string(line.quantity), line.course, line.status]
            if line.status == "COOKING"
                append!(fields, ("until", clock(line.ready)))
            end
            if line.reason !== nothing
                append!(fields, ("COMP", line.reason))
            end
            emit!(r, fields...)
        end
    elseif command == "KITCHEN"
        emit!(r, "KITCHEN", clock(r.now))
        for name in STATIONS
            station = r.stations[name]
            cooking = sort(station.cooking; by=line -> (line.ready, line.id))
            cooking_text = isempty(cooking) ? "-" :
                           join(["#$(line.id)@$(clock(line.ready))" for line in cooking], " ")
            queue_text = isempty(station.queue) ? "-" :
                         join(["#$(line.id)" for line in station.queue], " ")
            emit!(r, name, station.up ? "up" : "down",
                  "cooking", cooking_text, "queue", queue_text)
        end
    elseif command == "FLOOR"
        tables = sort(collect(values(r.tables)); by=item -> item.number)
        free = count(item -> item.check === nothing, tables)
        emit!(r, "FLOOR", clock(r.now), "free", free,
              "seated", length(tables)-free, "waiting", length(r.waiting))
        for item in tables
            if item.check === nothing
                emit!(r, "table", item.number, "seats", item.seats, "free")
            else
                check = item.check::Check
                fields = Any["table", item.number, "seats", item.seats, check.party,
                             "guests", check.size, "server", check.server.name,
                             "since", clock(check.seated), "items", length(active_lines(check)),
                             "total", money(check_amounts(check).total)]
                check.paid > 0 && append!(fields, ("paid", money(check.paid)))
                emit!(r, fields...)
            end
        end
        for (index, entry) in enumerate(r.waiting)
            emit!(r, "WAITING", index, entry.party, entry.size, "since", clock(entry.joined))
        end
    elseif command == "REPORT"
        show_report!(r)
    end
end

function execute!(r::Restaurant, line::String)
    tokens = String.(split(line))
    command = first(tokens)
    try
        run_command!(r, command, tokens[2:end])
    catch error
        if error isa CommandError
            emit!(r, "ERROR", error.reason)
        else
            rethrow()
        end
    end
end

function main()
    count = parse(Int, readline(stdin))
    restaurant = Restaurant()
    for _ in 1:count
        execute!(restaurant, readline(stdin))
    end
    if !isempty(restaurant.output)
        println(join(restaurant.output, "\n"))
    end
end

main()
