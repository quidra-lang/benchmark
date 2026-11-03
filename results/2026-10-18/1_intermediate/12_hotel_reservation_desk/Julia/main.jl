using Printf

const ROOM_TYPES = ("SINGLE", "DOUBLE", "SUITE")
const WEEKDAYS = ("SAT", "SUN", "MON", "TUE", "WED", "THU", "FRI")

struct CommandError <: Exception
    message::String
end
Base.showerror(io::IO, error::CommandError) = print(io, error.message)
fail(message::String) = throw(CommandError(message))

leap(year::Int) = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)

month_lengths(year::Int) = [
    31, leap(year) ? 29 : 28, 31, 30, 31, 30,
    31, 31, 30, 31, 30, 31
]

function day_number(text::String)
    pieces = split(text, '-')
    year, month, day = parse.(Int, pieces)
    if !(2000 <= year <= 2099 && 1 <= month <= 12)
        fail("invalid date $text")
    end
    lengths = month_lengths(year)
    1 <= day <= lengths[month] || fail("invalid date $text")
    number = day - 1
    for previous in 2000:(year-1)
        number += leap(previous) ? 366 : 365
    end
    number += sum(lengths[1:month-1])
    number
end

function date_text(number::Int)
    year = 2000
    while true
        days = leap(year) ? 366 : 365
        number < days && break
        number -= days
        year += 1
    end
    month = 1
    for days in month_lengths(year)
        number < days && break
        number -= days
        month += 1
    end
    @sprintf("%04d-%02d-%02d", year, month, number + 1)
end

date_weekday(day::Int) = date_text(day) * " " * WEEKDAYS[day % 7 + 1]

function cents(text::String)
    whole, fraction = split(text, '.')
    parse(Int, whole) * 100 + parse(Int, fraction)
end

money(value::Int) = @sprintf("%d.%02d", div(value, 100), mod(value, 100))

mutable struct Room
    number::Int
    kind::String
    rate::Int
    clean::Bool
end

struct Night
    day::Int
    room::Int
    rate::Int
end

mutable struct Reservation
    id::String
    guest::String
    room::Room
    arrival::Int
    departure::Int
    nights::Vector{Night}
    status::String
    extras::Vector{Tuple{String,Int}}
    deposit::Int
    paid::Int
    posting::Union{Nothing,Int}
    fee::Int
    penalty::Union{Nothing,Night}
    bill::Union{Nothing,NTuple{6,Int}}
end

struct WaitingEntry
    id::String
    guest::String
    kind::String
    arrival::Int
    departure::Int
end

mutable struct HotelDesk
    today::Int
    rooms::Dict{Int,Room}
    seasons::Vector{Tuple{Int,Int,Int}}
    blocks::Set{Tuple{Int,Int}}
    reservations::Dict{String,Reservation}
    reservation_order::Vector{String}
    waitlist::Vector{WaitingEntry}
    used_ids::Set{String}
    occupied::Dict{Tuple{Int,Int},Tuple{Reservation,Int}}
    output::Vector{String}
end

HotelDesk() = HotelDesk(
    day_number("2026-01-01"),
    Dict{Int,Room}(),
    Tuple{Int,Int,Int}[],
    Set{Tuple{Int,Int}}(),
    Dict{String,Reservation}(),
    String[],
    WaitingEntry[],
    Set{String}(),
    Dict{Tuple{Int,Int},Tuple{Reservation,Int}}(),
    String[]
)

emit!(desk::HotelDesk, parts...) = push!(desk.output, join(string.(parts), " "))
emit_indented!(desk::HotelDesk, parts...) = push!(desk.output, "  " * join(string.(parts), " "))

function require_room(desk::HotelDesk, text::String)
    number = parse(Int, text)
    haskey(desk.rooms, number) || fail("unknown room $text")
    desk.rooms[number]
end

function require_type(kind::String)
    kind in ROOM_TYPES || fail("invalid type $kind")
end

function require_unused(desk::HotelDesk, id::String)
    id in desk.used_ids && fail("duplicate reservation $id")
end

function require_reservation(desk::HotelDesk, id::String, status::Union{Nothing,String}=nothing)
    haskey(desk.reservations, id) || fail("unknown reservation $id")
    reservation = desk.reservations[id]
    if status !== nothing && reservation.status != status
        fail("invalid status $id $(reservation.status)")
    end
    reservation
end

function stay(desk::HotelDesk, first::String, last::String)
    arrival = day_number(first)
    departure = day_number(last)
    arrival < desk.today && fail("past date $first")
    departure <= arrival && fail("invalid range $first $last")
    departure - arrival > 30 && fail("too long $(departure - arrival)")
    arrival, departure
end

function period(desk::HotelDesk, first::String, last::String;
                past_restricted::Bool=false, limited::Bool=true)
    start = day_number(first)
    last_day = day_number(last)
    past_restricted && start < desk.today && fail("past date $first")
    last_day < start && fail("invalid range $first $last")
    limited && last_day - start + 1 > 31 && fail("too long $(last_day - start + 1)")
    start, last_day
end

function night_rate(desk::HotelDesk, room::Room, day::Int)
    percentage = 100
    for (start, last, value) in Iterators.reverse(desk.seasons)
        if start <= day <= last
            percentage = value
            break
        end
    end
    room.rate * percentage ÷ 100
end

function price(desk::HotelDesk, room::Room, arrival::Int, departure::Int)
    [Night(day, room.number, night_rate(desk, room, day))
     for day in arrival:(departure-1)]
end

function first_unavailable(desk::HotelDesk, room::Room, arrival::Int,
                           departure::Int, except_for::Union{Nothing,Reservation}=nothing)
    for day in arrival:(departure-1)
        key = (day, room.number)
        key in desk.blocks && return day
        occupied = get(desk.occupied, key, nothing)
        if occupied !== nothing && occupied[1] !== except_for
            return day
        end
    end
    nothing
end

function free_room(desk::HotelDesk, kind::String, arrival::Int, departure::Int,
                   except_for::Union{Nothing,Reservation}=nothing)
    for number in sort!(collect(keys(desk.rooms)))
        room = desk.rooms[number]
        if room.kind == kind &&
           first_unavailable(desk, room, arrival, departure, except_for) === nothing
            return room
        end
    end
    nothing
end

function inhouse(desk::HotelDesk, room::Room)
    for id in desk.reservation_order
        reservation = desk.reservations[id]
        if reservation.status == "inhouse" && reservation.room === room
            return reservation
        end
    end
    nothing
end

function occupy!(desk::HotelDesk, reservation::Reservation, nights::Vector{Night})
    for night in nights
        desk.occupied[(night.day, night.room)] = (reservation, night.rate)
    end
end

function release!(desk::HotelDesk, reservation::Reservation, first::Union{Nothing,Int}=nothing)
    for night in reservation.nights
        if first === nothing || night.day >= first
            delete!(desk.occupied, (night.day, night.room))
        end
    end
end

lodging(reservation::Reservation) = sum(night.rate for night in reservation.nights; init=0)
first_rate(reservation::Reservation) = first(reservation.nights).rate

function create_reservation!(desk::HotelDesk, id::String, guest::String, room::Room,
                             arrival::Int, departure::Int, indent::Bool=false)
    nights = price(desk, room, arrival, departure)
    reservation = Reservation(
        id, guest, room, arrival, departure, nights, "booked",
        Tuple{String,Int}[], 0, 0, nothing, 0, nothing, nothing
    )
    desk.reservations[id] = reservation
    push!(desk.reservation_order, id)
    push!(desk.used_ids, id)
    occupy!(desk, reservation, nights)
    parts = (
        "BOOK", id, guest, "room", room.number, room.kind,
        date_text(arrival), "->", date_text(departure),
        "nights", departure - arrival, "total", money(lodging(reservation))
    )
    if indent
        emit_indented!(desk, parts...)
    else
        emit!(desk, parts...)
    end
end

function guest_total(desk::HotelDesk, guest::String)
    sum((reservation.paid for reservation in values(desk.reservations)
         if reservation.guest == guest); init=0)
end

function tier(desk::HotelDesk, guest::String)
    points = guest_total(desk, guest) ÷ 100
    points >= 2000 ? "GOLD" : points >= 500 ? "SILVER" : "BRONZE"
end

function calculate_bill(desk::HotelDesk, reservation::Reservation)::NTuple{6,Int}
    charge = lodging(reservation)
    percentage = tier(desk, reservation.guest) == "GOLD" ? 10 :
                 tier(desk, reservation.guest) == "SILVER" ? 5 : 0
    discount = charge * percentage ÷ 100
    penalty = reservation.penalty === nothing ? 0 : reservation.penalty.rate
    extras = sum((extra[2] for extra in reservation.extras); init=0)
    subtotal = charge - discount + penalty + extras
    tax = subtotal ÷ 10
    (charge, discount, penalty, extras, tax, subtotal + tax)
end

function deposit_parts(reservation::Reservation, amount::Int)
    if amount >= reservation.deposit
        return ("deposit", money(reservation.deposit), "due", money(amount - reservation.deposit))
    end
    ("deposit", money(reservation.deposit), "refund", money(reservation.deposit - amount))
end

function check_out!(desk::HotelDesk, reservation::Reservation, day::Int, indent::Bool=false)
    if day < reservation.departure
        reservation.penalty = first(night for night in reservation.nights if night.day == day)
        release!(desk, reservation, day)
        filter!(night -> night.day < day, reservation.nights)
        reservation.departure = day
    end
    bill = calculate_bill(desk, reservation)
    reservation.bill = bill
    reservation.paid = bill[6]
    reservation.status = "checkedout"
    reservation.posting = day
    reservation.room.clean = false
    parts = (
        "CHECKOUT", reservation.id, "nights", length(reservation.nights),
        "lodging", money(bill[1]), "discount", money(bill[2]),
        "penalty", money(bill[3]), "extras", money(bill[4]),
        "tax", money(bill[5]), "total", money(bill[6]),
        deposit_parts(reservation, bill[6])...
    )
    if indent
        emit_indented!(desk, parts...)
    else
        emit!(desk, parts...)
    end
end

function process_waitlist!(desk::HotelDesk)
    remaining = WaitingEntry[]
    for entry in desk.waitlist
        if entry.arrival < desk.today
            emit_indented!(desk, "WAITLIST", entry.id, "expired")
            continue
        end
        room = free_room(desk, entry.kind, entry.arrival, entry.departure)
        if room === nothing
            push!(remaining, entry)
        else
            create_reservation!(desk, entry.id, entry.guest, room,
                                entry.arrival, entry.departure, true)
        end
    end
    desk.waitlist = remaining
end

function cmd_room!(desk::HotelDesk, a::Vector{String})
    number = parse(Int, a[1])
    haskey(desk.rooms, number) && fail("duplicate room $(a[1])")
    require_type(a[2])
    desk.rooms[number] = Room(number, a[2], cents(a[3]), true)
    emit!(desk, "ROOM", a[1], a[2], a[3])
end

function cmd_rate!(desk::HotelDesk, a::Vector{String})
    room = require_room(desk, a[1])
    previous = room.rate
    room.rate = cents(a[2])
    emit!(desk, "RATE", a[1], money(previous), "->", a[2])
end

function cmd_season!(desk::HotelDesk, a::Vector{String})
    start, last = period(desk, a[1], a[2]; limited=false)
    push!(desk.seasons, (start, last, parse(Int, a[3])))
    emit!(desk, "SEASON", length(desk.seasons), a[1], "->", a[2], a[3] * "%")
end

function cmd_block!(desk::HotelDesk, a::Vector{String})
    room = require_room(desk, a[1])
    start, last = period(desk, a[2], a[3]; past_restricted=true)
    for day in start:last
        haskey(desk.occupied, (day, room.number)) &&
            fail("room unavailable $(a[1]) $(date_text(day))")
    end
    added = 0
    for day in start:last
        key = (day, room.number)
        if !(key in desk.blocks)
            push!(desk.blocks, key)
            added += 1
        end
    end
    emit!(desk, "BLOCK", a[1], a[2], "->", a[3], "added", added)
end

function cmd_unblock!(desk::HotelDesk, a::Vector{String})
    room = require_room(desk, a[1])
    start, last = period(desk, a[2], a[3]; past_restricted=true)
    removed = 0
    for day in start:last
        key = (day, room.number)
        if key in desk.blocks
            delete!(desk.blocks, key)
            removed += 1
        end
    end
    emit!(desk, "UNBLOCK", a[1], a[2], "->", a[3], "removed", removed)
end

function cmd_clean!(desk::HotelDesk, a::Vector{String})
    room = require_room(desk, a[1])
    room.clean && fail("already clean $(a[1])")
    room.clean = true
    emit!(desk, "CLEAN", a[1])
end

function cmd_today!(desk::HotelDesk, a::Vector{String})
    day = day_number(a[1])
    day < desk.today && fail("past date $(a[1])")
    emit!(desk, "TODAY", date_weekday(day))
    departing = [r for r in values(desk.reservations)
                 if r.status == "inhouse" && r.departure < day]
    sort!(departing; by=r -> (r.departure, r.id))
    for reservation in departing
        check_out!(desk, reservation, reservation.departure, true)
    end
    absent = [r for r in values(desk.reservations)
              if r.status == "booked" && r.arrival < day]
    sort!(absent; by=r -> (r.arrival, r.id))
    for reservation in absent
        release!(desk, reservation)
        reservation.fee = first_rate(reservation)
        reservation.paid = reservation.fee
        reservation.status = "noshow"
        reservation.posting = reservation.arrival
        emit_indented!(desk, "NOSHOW", reservation.id, reservation.guest, "fee",
                       money(reservation.fee), deposit_parts(reservation, reservation.fee)...)
    end
    desk.today = day
end

function cmd_book!(desk::HotelDesk, a::Vector{String})
    require_unused(desk, a[1])
    require_type(a[3])
    arrival, departure = stay(desk, a[4], a[5])
    room = free_room(desk, a[3], arrival, departure)
    room === nothing && fail("no availability $(a[3]) $(a[4]) $(a[5])")
    create_reservation!(desk, a[1], a[2], room, arrival, departure)
end

function cmd_bookroom!(desk::HotelDesk, a::Vector{String})
    require_unused(desk, a[1])
    room = require_room(desk, a[3])
    arrival, departure = stay(desk, a[4], a[5])
    unavailable = first_unavailable(desk, room, arrival, departure)
    unavailable !== nothing && fail("room unavailable $(a[3]) $(date_text(unavailable))")
    create_reservation!(desk, a[1], a[2], room, arrival, departure)
end

function cmd_waitlist!(desk::HotelDesk, a::Vector{String})
    require_unused(desk, a[1])
    require_type(a[3])
    arrival, departure = stay(desk, a[4], a[5])
    room = free_room(desk, a[3], arrival, departure)
    if room !== nothing
        create_reservation!(desk, a[1], a[2], room, arrival, departure)
    else
        push!(desk.waitlist, WaitingEntry(a[1], a[2], a[3], arrival, departure))
        push!(desk.used_ids, a[1])
        emit!(desk, "WAITLIST", a[1], "queued position", length(desk.waitlist))
    end
end

function cmd_modify!(desk::HotelDesk, a::Vector{String})
    reservation = require_reservation(desk, a[1], "booked")
    arrival, departure = stay(desk, a[2], a[3])
    room = reservation.room
    choice = "kept"
    if first_unavailable(desk, room, arrival, departure, reservation) !== nothing
        room = free_room(desk, room.kind, arrival, departure, reservation)
        room === nothing &&
            fail("no availability $(reservation.room.kind) $(a[2]) $(a[3])")
        choice = "reassigned"
    end
    nights = price(desk, room, arrival, departure)
    release!(desk, reservation)
    reservation.room = room
    reservation.arrival = arrival
    reservation.departure = departure
    reservation.nights = nights
    occupy!(desk, reservation, nights)
    emit!(desk, "MODIFY", a[1], "room", room.number, choice, a[2], "->", a[3],
          "nights", departure - arrival, "total", money(lodging(reservation)))
end

function cmd_cancel!(desk::HotelDesk, a::Vector{String})
    position = findfirst(entry -> entry.id == a[1], desk.waitlist)
    if position !== nothing
        deleteat!(desk.waitlist, position)
        emit!(desk, "CANCEL", a[1], "waitlist removed")
        return
    end
    reservation = require_reservation(desk, a[1], "booked")
    days = reservation.arrival - desk.today
    first = first_rate(reservation)
    fee = days >= 7 ? 0 : days >= 1 ? first ÷ 2 : first
    release!(desk, reservation)
    reservation.fee = fee
    reservation.paid = fee
    reservation.status = "cancelled"
    reservation.posting = desk.today
    emit!(desk, "CANCEL", a[1], "days", days, "fee", money(fee),
          deposit_parts(reservation, fee)...)
end

function cmd_checkin!(desk::HotelDesk, a::Vector{String})
    reservation = require_reservation(desk, a[1], "booked")
    reservation.arrival != desk.today &&
        fail("not arrival date $(a[1]) $(date_text(reservation.arrival))")
    occupant = inhouse(desk, reservation.room)
    occupant !== nothing &&
        fail("room occupied $(reservation.room.number) $(occupant.id)")
    !reservation.room.clean && fail("room dirty $(reservation.room.number)")
    reservation.status = "inhouse"
    emit!(desk, "CHECKIN", a[1], reservation.guest, "room", reservation.room.number,
          "until", date_text(reservation.departure))
end

function cmd_move!(desk::HotelDesk, a::Vector{String})
    reservation = require_reservation(desk, a[1], "inhouse")
    room = require_room(desk, a[2])
    previous = reservation.room
    room === previous && fail("same room $(a[2])")
    remaining = [night for night in reservation.nights if night.day >= desk.today]
    isempty(remaining) && fail("no remaining nights $(a[1])")
    unavailable = first_unavailable(desk, room, first(remaining).day,
                                    reservation.departure, reservation)
    unavailable !== nothing && fail("room unavailable $(a[2]) $(date_text(unavailable))")
    occupant = inhouse(desk, room)
    occupant !== nothing && fail("room occupied $(a[2]) $(occupant.id)")
    !room.clean && fail("room dirty $(a[2])")
    release!(desk, reservation, desk.today)
    reservation.nights = [
        night.day >= desk.today ? Night(night.day, room.number, night.rate) : night
        for night in reservation.nights
    ]
    occupy!(desk, reservation,
            [night for night in reservation.nights if night.day >= desk.today])
    previous.clean = false
    reservation.room = room
    emit!(desk, "MOVE", a[1], previous.number, "->", a[2], "nights", length(remaining))
end

function cmd_extend!(desk::HotelDesk, a::Vector{String})
    reservation = require_reservation(desk, a[1], "inhouse")
    departure = day_number(a[2])
    departure <= reservation.departure &&
        fail("invalid range $(date_text(reservation.departure)) $(a[2])")
    departure - reservation.arrival > 30 &&
        fail("too long $(departure - reservation.arrival)")
    unavailable = first_unavailable(desk, reservation.room,
                                    reservation.departure, departure, reservation)
    unavailable !== nothing &&
        fail("room unavailable $(reservation.room.number) $(date_text(unavailable))")
    nights = price(desk, reservation.room, reservation.departure, departure)
    append!(reservation.nights, nights)
    occupy!(desk, reservation, nights)
    reservation.departure = departure
    emit!(desk, "EXTEND", a[1], "until", a[2], "nights", length(reservation.nights),
          "total", money(lodging(reservation)))
end

function cmd_charge!(desk::HotelDesk, a::Vector{String})
    reservation = require_reservation(desk, a[1], "inhouse")
    amount = cents(a[2])
    amount == 0 && fail("invalid amount")
    push!(reservation.extras, (a[3], amount))
    emit!(desk, "CHARGE", a[1], a[3], a[2], "extras",
          money(sum(extra[2] for extra in reservation.extras; init=0)))
end

function cmd_pay!(desk::HotelDesk, a::Vector{String})
    reservation = require_reservation(desk, a[1])
    reservation.status in ("booked", "inhouse") ||
        fail("invalid status $(a[1]) $(reservation.status)")
    amount = cents(a[2])
    amount == 0 && fail("invalid amount")
    reservation.deposit += amount
    emit!(desk, "PAY", a[1], a[2], "deposit", money(reservation.deposit))
end

function cmd_checkout!(desk::HotelDesk, a::Vector{String})
    check_out!(desk, require_reservation(desk, a[1], "inhouse"), desk.today)
end

function cmd_invoice!(desk::HotelDesk, a::Vector{String})
    reservation = require_reservation(desk, a[1])
    room = reservation.room
    emit!(desk, "INVOICE", a[1], reservation.guest, "room", room.number,
          room.kind, reservation.status)
    if reservation.status in ("cancelled", "noshow")
        label = reservation.status == "cancelled" ? "cancellation" : "noshow"
        emit_indented!(desk, label, "fee", money(reservation.fee))
        emit_indented!(desk, "total", money(reservation.fee))
        emit_indented!(desk, deposit_parts(reservation, reservation.fee)...)
        return
    end
    for night in reservation.nights
        emit_indented!(desk, date_weekday(night.day), "room", night.room, money(night.rate))
    end
    bill = reservation.bill === nothing ? calculate_bill(desk, reservation) : reservation.bill
    emit_indented!(desk, "lodging", money(bill[1]))
    emit_indented!(desk, "discount", money(bill[2]))
    if reservation.penalty !== nothing
        emit_indented!(desk, "penalty", date_weekday(reservation.penalty.day), money(bill[3]))
    end
    for (item, amount) in reservation.extras
        emit_indented!(desk, "extra", item, money(amount))
    end
    emit_indented!(desk, "tax", money(bill[5]))
    emit_indented!(desk, "total", money(bill[6]))
    emit_indented!(desk, deposit_parts(reservation, bill[6])...)
end

function cmd_avail!(desk::HotelDesk, a::Vector{String})
    require_type(a[1])
    start, last = period(desk, a[2], a[3])
    numbers = sort([room.number for room in values(desk.rooms) if room.kind == a[1]])
    emit!(desk, "AVAIL", a[1], a[2], "->", a[3])
    for day in start:last
        free = [number for number in numbers
                if !((day, number) in desk.blocks) && !haskey(desk.occupied, (day, number))]
        emit_indented!(desk, date_weekday(day), "free", length(free), free...)
    end
end

function occupancy_parts(desk::HotelDesk, numbers::Vector{Int}, day::Int)
    blocked = count(number -> (day, number) in desk.blocks, numbers)
    occupied = count(number -> haskey(desk.occupied, (day, number)), numbers)
    available = length(numbers) - blocked
    rate = available > 0 ? "$(occupied * 100 ÷ available)%" : "n/a"
    ("rooms", length(numbers), "blocked", blocked, "occupied", occupied, "rate", rate)
end

function cmd_occupancy!(desk::HotelDesk, a::Vector{String})
    day = day_number(a[1])
    emit!(desk, "OCCUPANCY", date_weekday(day),
          occupancy_parts(desk, collect(keys(desk.rooms)), day)...)
    for kind in ROOM_TYPES
        numbers = [room.number for room in values(desk.rooms) if room.kind == kind]
        if !isempty(numbers)
            emit_indented!(desk, kind, occupancy_parts(desk, numbers, day)...)
        end
    end
end

function daily_values(desk::HotelDesk, day::Int)
    numbers = keys(desk.rooms)
    available = length(desk.rooms) - count(number -> (day, number) in desk.blocks, numbers)
    occupied = count(number -> haskey(desk.occupied, (day, number)), numbers)
    revenue = sum((desk.occupied[(day, number)][2] for number in numbers
                   if haskey(desk.occupied, (day, number))); init=0)
    (available, occupied, revenue)
end

function metrics_parts(available::Int, occupied::Int, revenue::Int)
    rate = available > 0 ? "$(occupied * 100 ÷ available)%" : "n/a"
    average = occupied > 0 ? money(revenue ÷ occupied) : "n/a"
    revpar = available > 0 ? money(revenue ÷ available) : "n/a"
    ("sold", "$occupied/$available", "rate", rate, "revenue", money(revenue),
     "adr", average, "revpar", revpar)
end

function cmd_stats!(desk::HotelDesk, a::Vector{String})
    start, last = period(desk, a[1], a[2])
    totals = [0, 0, 0]
    emit!(desk, "STATS", a[1], "->", a[2])
    for day in start:last
        values = daily_values(desk, day)
        for i in 1:3
            totals[i] += values[i]
        end
        emit_indented!(desk, date_weekday(day), metrics_parts(values...)...)
    end
    emit_indented!(desk, "total", metrics_parts(totals...)...)
end

function cmd_rooms!(desk::HotelDesk, a::Vector{String})
    emit!(desk, "ROOMS", date_weekday(desk.today), "rooms", length(desk.rooms))
    for number in sort(collect(keys(desk.rooms)))
        room = desk.rooms[number]
        parts = String[
            string(number), room.kind, "base", money(room.rate),
            "tonight", money(night_rate(desk, room, desk.today)),
            room.clean ? "clean" : "dirty"
        ]
        occupant = inhouse(desk, room)
        if occupant !== nothing
            append!(parts, ["occupied", occupant.id])
        elseif (desk.today, number) in desk.blocks
            push!(parts, "blocked")
        else
            push!(parts, "vacant")
        end
        upcoming = nothing
        for id in desk.reservation_order
            reservation = desk.reservations[id]
            if reservation.status == "booked" && reservation.room === room &&
               (upcoming === nothing || reservation.arrival < upcoming.arrival)
                upcoming = reservation
            end
        end
        if upcoming !== nothing
            append!(parts, ["next", upcoming.id, date_text(upcoming.arrival)])
        end
        emit_indented!(desk, parts...)
    end
end

function cmd_list!(desk::HotelDesk, a::Vector{String})
    selected = [r for r in values(desk.reservations) if r.status == a[1]]
    sort!(selected; by=r -> (r.arrival, r.id))
    emit!(desk, "LIST", a[1], length(selected))
    for reservation in selected
        emit_indented!(desk, reservation.id, reservation.guest, "room", reservation.room.number,
                       date_text(reservation.arrival), "->", date_text(reservation.departure))
    end
end

function cmd_queue!(desk::HotelDesk, a::Vector{String})
    emit!(desk, "QUEUE", length(desk.waitlist))
    for (i, entry) in enumerate(desk.waitlist)
        emit_indented!(desk, i, entry.id, entry.guest, entry.kind,
                       date_text(entry.arrival), "->", date_text(entry.departure))
    end
end

function cmd_schedule!(desk::HotelDesk, a::Vector{String})
    day = day_number(a[1])
    arrivals = sort([r for r in values(desk.reservations)
                     if r.arrival == day && r.status != "cancelled"]; by=r -> r.id)
    departures = sort([r for r in values(desk.reservations)
                       if r.departure == day &&
                          r.status in ("booked", "inhouse", "checkedout")]; by=r -> r.id)
    emit!(desk, "SCHEDULE", date_weekday(day), "arrivals", length(arrivals),
          "departures", length(departures))
    for reservation in arrivals
        emit_indented!(desk, "arrival", reservation.id, reservation.guest,
                       "room", reservation.room.number, reservation.status)
    end
    for reservation in departures
        emit_indented!(desk, "departure", reservation.id, reservation.guest,
                       "room", reservation.room.number, reservation.status)
    end
end

function cmd_guest!(desk::HotelDesk, a::Vector{String})
    selected = [desk.reservations[id] for id in desk.reservation_order
                if desk.reservations[id].guest == a[1]]
    isempty(selected) && fail("unknown guest $(a[1])")
    emit!(desk, "GUEST", a[1])
    for reservation in selected
        deposit = reservation.status in ("booked", "inhouse")
        emit_indented!(
            desk, reservation.id, "room", reservation.room.number,
            reservation.room.kind, date_text(reservation.arrival), "->",
            date_text(reservation.departure), reservation.status,
            deposit ? "deposit" : "paid",
            money(deposit ? reservation.deposit : reservation.paid)
        )
    end
    total = guest_total(desk, a[1])
    emit_indented!(desk, "total paid", money(total), "points", total ÷ 100,
                   "tier", tier(desk, a[1]))
end

function cmd_revenue!(desk::HotelDesk, a::Vector{String})
    start, last = period(desk, a[1], a[2]; limited=false)
    totals = [0, 0, 0, 0, 0]
    cancellations = 0
    noshows = 0
    checkouts = 0
    cancelled = 0
    absent = 0
    for reservation in values(desk.reservations)
        if reservation.posting === nothing ||
           !(start <= reservation.posting <= last)
            continue
        end
        if reservation.status == "checkedout"
            for i in 1:5
                totals[i] += reservation.bill[i]
            end
            checkouts += 1
        elseif reservation.status == "cancelled"
            cancellations += reservation.fee
            cancelled += 1
        elseif reservation.status == "noshow"
            noshows += reservation.fee
            absent += 1
        end
    end
    emit!(desk, "REVENUE", a[1], "->", a[2])
    for (i, label) in enumerate(("lodging", "discount", "penalty", "extras", "tax"))
        emit_indented!(desk, label, money(totals[i]))
    end
    emit_indented!(desk, "cancellation", money(cancellations))
    emit_indented!(desk, "noshow", money(noshows))
    total = totals[1] - totals[2] + sum(totals[3:5]) + cancellations + noshows
    emit_indented!(desk, "total", money(total))
    emit_indented!(desk, "checkouts", checkouts, "cancellations", cancelled,
                   "noshows", absent)
end

const HANDLERS = Dict{String,Function}(
    "ROOM" => cmd_room!, "RATE" => cmd_rate!, "SEASON" => cmd_season!,
    "BLOCK" => cmd_block!, "UNBLOCK" => cmd_unblock!, "CLEAN" => cmd_clean!,
    "TODAY" => cmd_today!, "BOOK" => cmd_book!, "BOOKROOM" => cmd_bookroom!,
    "WAITLIST" => cmd_waitlist!, "MODIFY" => cmd_modify!, "CANCEL" => cmd_cancel!,
    "CHECKIN" => cmd_checkin!, "MOVE" => cmd_move!, "EXTEND" => cmd_extend!,
    "CHARGE" => cmd_charge!, "PAY" => cmd_pay!, "CHECKOUT" => cmd_checkout!,
    "INVOICE" => cmd_invoice!, "AVAIL" => cmd_avail!, "OCCUPANCY" => cmd_occupancy!,
    "STATS" => cmd_stats!, "ROOMS" => cmd_rooms!, "LIST" => cmd_list!,
    "QUEUE" => cmd_queue!, "SCHEDULE" => cmd_schedule!, "GUEST" => cmd_guest!,
    "REVENUE" => cmd_revenue!
)

function execute!(desk::HotelDesk, line::String)
    parts = String.(split(line, ' '))
    command, arguments = parts[1], parts[2:end]
    try
        HANDLERS[command](desk, arguments)
    catch error
        if error isa CommandError
            emit!(desk, "ERROR", error.message)
        else
            rethrow()
        end
    end
    process_waitlist!(desk)
end

function main()
    count = parse(Int, readline(stdin))
    desk = HotelDesk()
    for _ in 1:count
        execute!(desk, readline(stdin))
    end
    for text in desk.output
        println(text)
    end
end

main()
