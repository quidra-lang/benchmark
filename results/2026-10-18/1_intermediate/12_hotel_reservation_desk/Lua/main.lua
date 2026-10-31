local ROOM_TYPES = {"SINGLE", "DOUBLE", "SUITE"}
local WEEKDAYS = {"SAT", "SUN", "MON", "TUE", "WED", "THU", "FRI"}

local function fail(reason)
    error({message = reason}, 0)
end

local function leap(year)
    return year % 4 == 0 and (year % 100 ~= 0 or year % 400 == 0)
end

local function month_lengths(year)
    return {31, leap(year) and 29 or 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31}
end

local function day_number(text)
    local year, month, day = text:match("^(%d+)%-(%d+)%-(%d+)$")
    year, month, day = tonumber(year), tonumber(month), tonumber(day)
    if year < 2000 or year > 2099 or month < 1 or month > 12 then
        fail("invalid date " .. text)
    end
    local lengths = month_lengths(year)
    if day < 1 or day > lengths[month] then fail("invalid date " .. text) end
    local number = day - 1
    for previous = 2000, year - 1 do
        number = number + (leap(previous) and 366 or 365)
    end
    for previous = 1, month - 1 do
        number = number + lengths[previous]
    end
    return number
end

local function date_text(number)
    local year = 2000
    while true do
        local days = leap(year) and 366 or 365
        if number < days then break end
        number, year = number - days, year + 1
    end
    local month = 1
    for _, days in ipairs(month_lengths(year)) do
        if number < days then break end
        number, month = number - days, month + 1
    end
    return string.format("%04d-%02d-%02d", year, month, number + 1)
end

local function date_weekday(day)
    return date_text(day) .. " " .. WEEKDAYS[day % 7 + 1]
end

local function cents(text)
    local whole, fraction = text:match("^(%d+)%.(%d%d)$")
    return tonumber(whole) * 100 + tonumber(fraction)
end

local function money(value)
    return string.format("%d.%02d", value // 100, value % 100)
end

local rooms = {}
local seasons = {}
local blocks = {}
local reservations = {}
local reservation_order = {}
local waitlist = {}
local used_ids = {}
local occupied = {}
local output = {}
local today = day_number("2026-01-01")

local function line(parts)
    for i, item in ipairs(parts) do parts[i] = tostring(item) end
    return table.concat(parts, " ")
end

local function emit(...)
    output[#output + 1] = line({...})
end

local function emit_indented(...)
    output[#output + 1] = "  " .. line({...})
end

local function require_room(number)
    local room = rooms[tonumber(number)]
    if not room then fail("unknown room " .. number) end
    return room
end

local function require_type(kind)
    for _, value in ipairs(ROOM_TYPES) do
        if kind == value then return end
    end
    fail("invalid type " .. kind)
end

local function require_unused(id)
    if used_ids[id] then fail("duplicate reservation " .. id) end
end

local function reservation(id, status)
    local item = reservations[id]
    if not item then fail("unknown reservation " .. id) end
    if status and item.status ~= status then
        fail("invalid status " .. id .. " " .. item.status)
    end
    return item
end

local function stay(first, last)
    local arrival, departure = day_number(first), day_number(last)
    if arrival < today then fail("past date " .. first) end
    if departure <= arrival then fail("invalid range " .. first .. " " .. last) end
    if departure - arrival > 30 then fail("too long " .. (departure - arrival)) end
    return arrival, departure
end

local function period(first, last, past_restricted, limited)
    local start, finish = day_number(first), day_number(last)
    if past_restricted and start < today then fail("past date " .. first) end
    if finish < start then fail("invalid range " .. first .. " " .. last) end
    if limited ~= false and finish - start + 1 > 31 then
        fail("too long " .. (finish - start + 1))
    end
    return start, finish
end

local function room_numbers()
    local result = {}
    for number in pairs(rooms) do result[#result + 1] = number end
    table.sort(result)
    return result
end

local function night_rate(room, day)
    local percentage = 100
    for i = #seasons, 1, -1 do
        local entry = seasons[i]
        if entry[1] <= day and day <= entry[2] then
            percentage = entry[3]
            break
        end
    end
    return room.rate * percentage // 100
end

local function price(room, arrival, departure)
    local nights = {}
    for day = arrival, departure - 1 do
        nights[#nights + 1] = {day, room.number, night_rate(room, day)}
    end
    return nights
end

local function night_key(day, number)
    return day .. ":" .. number
end

local function first_unavailable(room, arrival, departure, except_for)
    for day = arrival, departure - 1 do
        local key = night_key(day, room.number)
        if blocks[key] then return day end
        local existing = occupied[key]
        if existing and existing[1] ~= except_for then return day end
    end
    return nil
end

local function free_room(kind, arrival, departure, except_for)
    for _, number in ipairs(room_numbers()) do
        local room = rooms[number]
        if room.kind == kind and
           not first_unavailable(room, arrival, departure, except_for) then
            return room
        end
    end
    return nil
end

local function inhouse(room)
    for _, id in ipairs(reservation_order) do
        local item = reservations[id]
        if item.status == "inhouse" and item.room == room then return item end
    end
    return nil
end

local function occupy(item, nights)
    for _, night in ipairs(nights) do
        occupied[night_key(night[1], night[2])] = {item, night[3]}
    end
end

local function release(item, first)
    for _, night in ipairs(item.nights) do
        if not first or night[1] >= first then
            occupied[night_key(night[1], night[2])] = nil
        end
    end
end

local function lodging(item)
    local amount = 0
    for _, night in ipairs(item.nights) do amount = amount + night[3] end
    return amount
end

local function first_rate(item)
    return item.nights[1][3]
end

local function create_reservation(id, guest, room, arrival, departure, indent)
    local nights = price(room, arrival, departure)
    local item = {
        id = id, guest = guest, room = room, arrival = arrival, departure = departure,
        nights = nights, status = "booked", extras = {}, deposit = 0, paid = 0,
        posting = nil, fee = 0, penalty = nil, bill = nil
    }
    reservations[id] = item
    reservation_order[#reservation_order + 1] = id
    used_ids[id] = true
    occupy(item, nights)
    local parts = {
        "BOOK", id, guest, "room", room.number, room.kind,
        date_text(arrival), "->", date_text(departure),
        "nights", departure - arrival, "total", money(lodging(item))
    }
    if indent then emit_indented(table.unpack(parts)) else emit(table.unpack(parts)) end
end

local function guest_total(guest)
    local amount = 0
    for _, id in ipairs(reservation_order) do
        local item = reservations[id]
        if item.guest == guest then amount = amount + item.paid end
    end
    return amount
end

local function tier(guest)
    local points = guest_total(guest) // 100
    if points >= 2000 then return "GOLD" end
    if points >= 500 then return "SILVER" end
    return "BRONZE"
end

local function calculate_bill(item)
    local charge = lodging(item)
    local level = tier(item.guest)
    local percentage = level == "GOLD" and 10 or level == "SILVER" and 5 or 0
    local discount = charge * percentage // 100
    local penalty = item.penalty and item.penalty[3] or 0
    local extras = 0
    for _, extra in ipairs(item.extras) do extras = extras + extra[2] end
    local subtotal = charge - discount + penalty + extras
    local tax = subtotal // 10
    return {charge, discount, penalty, extras, tax, subtotal + tax}
end

local function deposit_parts(item, amount)
    if amount >= item.deposit then
        return {"deposit", money(item.deposit), "due", money(amount - item.deposit)}
    end
    return {"deposit", money(item.deposit), "refund", money(item.deposit - amount)}
end

local function check_out(item, day, indent)
    if day < item.departure then
        for _, night in ipairs(item.nights) do
            if night[1] == day then
                item.penalty = night
                break
            end
        end
        release(item, day)
        local remaining = {}
        for _, night in ipairs(item.nights) do
            if night[1] < day then remaining[#remaining + 1] = night end
        end
        item.nights = remaining
        item.departure = day
    end
    local bill = calculate_bill(item)
    item.bill = bill
    item.paid = bill[6]
    item.status = "checkedout"
    item.posting = day
    item.room.clean = false
    local parts = {
        "CHECKOUT", item.id, "nights", #item.nights,
        "lodging", money(bill[1]), "discount", money(bill[2]),
        "penalty", money(bill[3]), "extras", money(bill[4]),
        "tax", money(bill[5]), "total", money(bill[6])
    }
    for _, part in ipairs(deposit_parts(item, bill[6])) do
        parts[#parts + 1] = part
    end
    if indent then emit_indented(table.unpack(parts)) else emit(table.unpack(parts)) end
end

local function process_waitlist()
    local remaining = {}
    for _, entry in ipairs(waitlist) do
        if entry.arrival < today then
            emit_indented("WAITLIST", entry.id, "expired")
        else
            local room = free_room(entry.kind, entry.arrival, entry.departure)
            if not room then
                remaining[#remaining + 1] = entry
            else
                create_reservation(entry.id, entry.guest, room, entry.arrival, entry.departure, true)
            end
        end
    end
    waitlist = remaining
end

local function cmd_room(a)
    local number = tonumber(a[1])
    if rooms[number] then fail("duplicate room " .. a[1]) end
    require_type(a[2])
    rooms[number] = {number = number, kind = a[2], rate = cents(a[3]), clean = true}
    emit("ROOM", a[1], a[2], a[3])
end

local function cmd_rate(a)
    local room = require_room(a[1])
    local previous = room.rate
    room.rate = cents(a[2])
    emit("RATE", a[1], money(previous), "->", a[2])
end

local function cmd_season(a)
    local start, finish = period(a[1], a[2], false, false)
    seasons[#seasons + 1] = {start, finish, tonumber(a[3])}
    emit("SEASON", #seasons, a[1], "->", a[2], a[3] .. "%")
end

local function cmd_block(a)
    local room = require_room(a[1])
    local start, finish = period(a[2], a[3], true)
    for day = start, finish do
        if occupied[night_key(day, room.number)] then
            fail("room unavailable " .. a[1] .. " " .. date_text(day))
        end
    end
    local added = 0
    for day = start, finish do
        local key = night_key(day, room.number)
        if not blocks[key] then
            blocks[key] = true
            added = added + 1
        end
    end
    emit("BLOCK", a[1], a[2], "->", a[3], "added", added)
end

local function cmd_unblock(a)
    local room = require_room(a[1])
    local start, finish = period(a[2], a[3], true)
    local removed = 0
    for day = start, finish do
        local key = night_key(day, room.number)
        if blocks[key] then
            blocks[key] = nil
            removed = removed + 1
        end
    end
    emit("UNBLOCK", a[1], a[2], "->", a[3], "removed", removed)
end

local function cmd_clean(a)
    local room = require_room(a[1])
    if room.clean then fail("already clean " .. a[1]) end
    room.clean = true
    emit("CLEAN", a[1])
end

local function cmd_today(a)
    local day = day_number(a[1])
    if day < today then fail("past date " .. a[1]) end
    emit("TODAY", date_weekday(day))
    local departing, absent = {}, {}
    for _, id in ipairs(reservation_order) do
        local item = reservations[id]
        if item.status == "inhouse" and item.departure < day then
            departing[#departing + 1] = item
        end
    end
    table.sort(departing, function(x, y)
        if x.departure ~= y.departure then return x.departure < y.departure end
        return x.id < y.id
    end)
    for _, item in ipairs(departing) do
        check_out(item, item.departure, true)
    end
    for _, id in ipairs(reservation_order) do
        local item = reservations[id]
        if item.status == "booked" and item.arrival < day then
            absent[#absent + 1] = item
        end
    end
    table.sort(absent, function(x, y)
        if x.arrival ~= y.arrival then return x.arrival < y.arrival end
        return x.id < y.id
    end)
    for _, item in ipairs(absent) do
        release(item)
        item.fee = first_rate(item)
        item.paid = item.fee
        item.status = "noshow"
        item.posting = item.arrival
        local parts = {"NOSHOW", item.id, item.guest, "fee", money(item.fee)}
        for _, part in ipairs(deposit_parts(item, item.fee)) do
            parts[#parts + 1] = part
        end
        emit_indented(table.unpack(parts))
    end
    today = day
end

local function cmd_book(a)
    require_unused(a[1])
    require_type(a[3])
    local arrival, departure = stay(a[4], a[5])
    local room = free_room(a[3], arrival, departure)
    if not room then
        fail("no availability " .. a[3] .. " " .. a[4] .. " " .. a[5])
    end
    create_reservation(a[1], a[2], room, arrival, departure)
end

local function cmd_bookroom(a)
    require_unused(a[1])
    local room = require_room(a[3])
    local arrival, departure = stay(a[4], a[5])
    local unavailable = first_unavailable(room, arrival, departure)
    if unavailable then fail("room unavailable " .. a[3] .. " " .. date_text(unavailable)) end
    create_reservation(a[1], a[2], room, arrival, departure)
end

local function cmd_waitlist(a)
    require_unused(a[1])
    require_type(a[3])
    local arrival, departure = stay(a[4], a[5])
    local room = free_room(a[3], arrival, departure)
    if room then
        create_reservation(a[1], a[2], room, arrival, departure)
    else
        waitlist[#waitlist + 1] = {
            id = a[1], guest = a[2], kind = a[3], arrival = arrival, departure = departure
        }
        used_ids[a[1]] = true
        emit("WAITLIST", a[1], "queued position", #waitlist)
    end
end

local function cmd_modify(a)
    local item = reservation(a[1], "booked")
    local arrival, departure = stay(a[2], a[3])
    local room = item.room
    local choice = "kept"
    if first_unavailable(room, arrival, departure, item) then
        room = free_room(room.kind, arrival, departure, item)
        if not room then
            fail("no availability " .. item.room.kind .. " " .. a[2] .. " " .. a[3])
        end
        choice = "reassigned"
    end
    local nights = price(room, arrival, departure)
    release(item)
    item.room = room
    item.arrival = arrival
    item.departure = departure
    item.nights = nights
    occupy(item, nights)
    emit("MODIFY", a[1], "room", room.number, choice, a[2], "->", a[3],
         "nights", departure - arrival, "total", money(lodging(item)))
end

local function cmd_cancel(a)
    for i, entry in ipairs(waitlist) do
        if entry.id == a[1] then
            table.remove(waitlist, i)
            emit("CANCEL", a[1], "waitlist removed")
            return
        end
    end
    local item = reservation(a[1], "booked")
    local days = item.arrival - today
    local first = first_rate(item)
    local fee = days >= 7 and 0 or days >= 1 and first // 2 or first
    release(item)
    item.fee = fee
    item.paid = fee
    item.status = "cancelled"
    item.posting = today
    local parts = {"CANCEL", a[1], "days", days, "fee", money(fee)}
    for _, part in ipairs(deposit_parts(item, fee)) do parts[#parts + 1] = part end
    emit(table.unpack(parts))
end

local function cmd_checkin(a)
    local item = reservation(a[1], "booked")
    if item.arrival ~= today then
        fail("not arrival date " .. a[1] .. " " .. date_text(item.arrival))
    end
    local occupant = inhouse(item.room)
    if occupant then
        fail("room occupied " .. item.room.number .. " " .. occupant.id)
    end
    if not item.room.clean then fail("room dirty " .. item.room.number) end
    item.status = "inhouse"
    emit("CHECKIN", a[1], item.guest, "room", item.room.number,
         "until", date_text(item.departure))
end

local function cmd_move(a)
    local item = reservation(a[1], "inhouse")
    local room = require_room(a[2])
    local previous = item.room
    if room == previous then fail("same room " .. a[2]) end
    local remaining = {}
    for _, night in ipairs(item.nights) do
        if night[1] >= today then remaining[#remaining + 1] = night end
    end
    if #remaining == 0 then fail("no remaining nights " .. a[1]) end
    local unavailable = first_unavailable(room, remaining[1][1], item.departure, item)
    if unavailable then fail("room unavailable " .. a[2] .. " " .. date_text(unavailable)) end
    local occupant = inhouse(room)
    if occupant then fail("room occupied " .. a[2] .. " " .. occupant.id) end
    if not room.clean then fail("room dirty " .. a[2]) end
    release(item, today)
    local future = {}
    for _, night in ipairs(item.nights) do
        if night[1] >= today then
            night[2] = room.number
            future[#future + 1] = night
        end
    end
    occupy(item, future)
    previous.clean = false
    item.room = room
    emit("MOVE", a[1], previous.number, "->", a[2], "nights", #remaining)
end

local function cmd_extend(a)
    local item = reservation(a[1], "inhouse")
    local departure = day_number(a[2])
    if departure <= item.departure then
        fail("invalid range " .. date_text(item.departure) .. " " .. a[2])
    end
    if departure - item.arrival > 30 then fail("too long " .. (departure - item.arrival)) end
    local unavailable = first_unavailable(item.room, item.departure, departure, item)
    if unavailable then
        fail("room unavailable " .. item.room.number .. " " .. date_text(unavailable))
    end
    local nights = price(item.room, item.departure, departure)
    for _, night in ipairs(nights) do item.nights[#item.nights + 1] = night end
    occupy(item, nights)
    item.departure = departure
    emit("EXTEND", a[1], "until", a[2], "nights", #item.nights,
         "total", money(lodging(item)))
end

local function cmd_charge(a)
    local item = reservation(a[1], "inhouse")
    local amount = cents(a[2])
    if amount == 0 then fail("invalid amount") end
    item.extras[#item.extras + 1] = {a[3], amount}
    local extras = 0
    for _, entry in ipairs(item.extras) do extras = extras + entry[2] end
    emit("CHARGE", a[1], a[3], a[2], "extras", money(extras))
end

local function cmd_pay(a)
    local item = reservation(a[1])
    if item.status ~= "booked" and item.status ~= "inhouse" then
        fail("invalid status " .. a[1] .. " " .. item.status)
    end
    local amount = cents(a[2])
    if amount == 0 then fail("invalid amount") end
    item.deposit = item.deposit + amount
    emit("PAY", a[1], a[2], "deposit", money(item.deposit))
end

local function cmd_checkout(a)
    check_out(reservation(a[1], "inhouse"), today)
end

local function cmd_invoice(a)
    local item = reservation(a[1])
    local room = item.room
    emit("INVOICE", a[1], item.guest, "room", room.number, room.kind, item.status)
    if item.status == "cancelled" or item.status == "noshow" then
        local label = item.status == "cancelled" and "cancellation" or "noshow"
        emit_indented(label, "fee", money(item.fee))
        emit_indented("total", money(item.fee))
        emit_indented(table.unpack(deposit_parts(item, item.fee)))
        return
    end
    for _, night in ipairs(item.nights) do
        emit_indented(date_weekday(night[1]), "room", night[2], money(night[3]))
    end
    local bill = item.bill or calculate_bill(item)
    emit_indented("lodging", money(bill[1]))
    emit_indented("discount", money(bill[2]))
    if item.penalty then
        emit_indented("penalty", date_weekday(item.penalty[1]), money(bill[3]))
    end
    for _, extra in ipairs(item.extras) do
        emit_indented("extra", extra[1], money(extra[2]))
    end
    emit_indented("tax", money(bill[5]))
    emit_indented("total", money(bill[6]))
    emit_indented(table.unpack(deposit_parts(item, bill[6])))
end

local function cmd_avail(a)
    require_type(a[1])
    local start, finish = period(a[2], a[3])
    local numbers = {}
    for _, number in ipairs(room_numbers()) do
        if rooms[number].kind == a[1] then numbers[#numbers + 1] = number end
    end
    emit("AVAIL", a[1], a[2], "->", a[3])
    for day = start, finish do
        local free = {}
        for _, number in ipairs(numbers) do
            local key = night_key(day, number)
            if not blocks[key] and not occupied[key] then free[#free + 1] = number end
        end
        local parts = {date_weekday(day), "free", #free}
        for _, number in ipairs(free) do parts[#parts + 1] = number end
        emit_indented(table.unpack(parts))
    end
end

local function occupancy_parts(numbers, day)
    local blocked, used = 0, 0
    for _, number in ipairs(numbers) do
        local key = night_key(day, number)
        if blocks[key] then blocked = blocked + 1 end
        if occupied[key] then used = used + 1 end
    end
    local available = #numbers - blocked
    local rate = available > 0 and used * 100 // available .. "%" or "n/a"
    return {"rooms", #numbers, "blocked", blocked, "occupied", used, "rate", rate}
end

local function cmd_occupancy(a)
    local day = day_number(a[1])
    local parts = {"OCCUPANCY", date_weekday(day)}
    for _, value in ipairs(occupancy_parts(room_numbers(), day)) do
        parts[#parts + 1] = value
    end
    emit(table.unpack(parts))
    for _, kind in ipairs(ROOM_TYPES) do
        local numbers = {}
        for number, room in pairs(rooms) do
            if room.kind == kind then numbers[#numbers + 1] = number end
        end
        if #numbers > 0 then
            local row = {kind}
            for _, value in ipairs(occupancy_parts(numbers, day)) do
                row[#row + 1] = value
            end
            emit_indented(table.unpack(row))
        end
    end
end

local function daily_values(day)
    local available = 0
    local used = 0
    local revenue = 0
    for number in pairs(rooms) do
        local key = night_key(day, number)
        if not blocks[key] then available = available + 1 end
        if occupied[key] then
            used = used + 1
            revenue = revenue + occupied[key][2]
        end
    end
    return available, used, revenue
end

local function metrics_parts(available, used, revenue)
    local rate = available > 0 and used * 100 // available .. "%" or "n/a"
    local average = used > 0 and money(revenue // used) or "n/a"
    local revpar = available > 0 and money(revenue // available) or "n/a"
    return {"sold", used .. "/" .. available, "rate", rate, "revenue", money(revenue),
            "adr", average, "revpar", revpar}
end

local function cmd_stats(a)
    local start, finish = period(a[1], a[2])
    local total_available, total_used, total_revenue = 0, 0, 0
    emit("STATS", a[1], "->", a[2])
    for day = start, finish do
        local available, used, revenue = daily_values(day)
        total_available = total_available + available
        total_used = total_used + used
        total_revenue = total_revenue + revenue
        local parts = {date_weekday(day)}
        for _, value in ipairs(metrics_parts(available, used, revenue)) do
            parts[#parts + 1] = value
        end
        emit_indented(table.unpack(parts))
    end
    local parts = {"total"}
    for _, value in ipairs(metrics_parts(total_available, total_used, total_revenue)) do
        parts[#parts + 1] = value
    end
    emit_indented(table.unpack(parts))
end

local function cmd_rooms(a)
    local numbers = room_numbers()
    emit("ROOMS", date_weekday(today), "rooms", #numbers)
    for _, number in ipairs(numbers) do
        local room = rooms[number]
        local parts = {
            number, room.kind, "base", money(room.rate), "tonight", money(night_rate(room, today)),
            room.clean and "clean" or "dirty"
        }
        local occupant = inhouse(room)
        if occupant then
            parts[#parts + 1] = "occupied"
            parts[#parts + 1] = occupant.id
        elseif blocks[night_key(today, number)] then
            parts[#parts + 1] = "blocked"
        else
            parts[#parts + 1] = "vacant"
        end
        local upcoming
        for _, id in ipairs(reservation_order) do
            local item = reservations[id]
            if item.status == "booked" and item.room == room and
               (not upcoming or item.arrival < upcoming.arrival) then
                upcoming = item
            end
        end
        if upcoming then
            parts[#parts + 1] = "next"
            parts[#parts + 1] = upcoming.id
            parts[#parts + 1] = date_text(upcoming.arrival)
        end
        emit_indented(table.unpack(parts))
    end
end

local function cmd_list(a)
    local chosen = {}
    for _, id in ipairs(reservation_order) do
        local item = reservations[id]
        if item.status == a[1] then chosen[#chosen + 1] = item end
    end
    table.sort(chosen, function(x, y)
        if x.arrival ~= y.arrival then return x.arrival < y.arrival end
        return x.id < y.id
    end)
    emit("LIST", a[1], #chosen)
    for _, item in ipairs(chosen) do
        emit_indented(item.id, item.guest, "room", item.room.number,
                      date_text(item.arrival), "->", date_text(item.departure))
    end
end

local function cmd_queue(a)
    emit("QUEUE", #waitlist)
    for position, entry in ipairs(waitlist) do
        emit_indented(position, entry.id, entry.guest, entry.kind,
                      date_text(entry.arrival), "->", date_text(entry.departure))
    end
end

local function cmd_schedule(a)
    local day = day_number(a[1])
    local arrivals, departures = {}, {}
    for _, id in ipairs(reservation_order) do
        local item = reservations[id]
        if item.arrival == day and item.status ~= "cancelled" then
            arrivals[#arrivals + 1] = item
        end
        if item.departure == day and
           (item.status == "booked" or item.status == "inhouse" or
            item.status == "checkedout") then
            departures[#departures + 1] = item
        end
    end
    table.sort(arrivals, function(x, y) return x.id < y.id end)
    table.sort(departures, function(x, y) return x.id < y.id end)
    emit("SCHEDULE", date_weekday(day), "arrivals", #arrivals, "departures", #departures)
    for _, item in ipairs(arrivals) do
        emit_indented("arrival", item.id, item.guest, "room", item.room.number, item.status)
    end
    for _, item in ipairs(departures) do
        emit_indented("departure", item.id, item.guest, "room", item.room.number, item.status)
    end
end

local function cmd_guest(a)
    local chosen = {}
    for _, id in ipairs(reservation_order) do
        local item = reservations[id]
        if item.guest == a[1] then chosen[#chosen + 1] = item end
    end
    if #chosen == 0 then fail("unknown guest " .. a[1]) end
    emit("GUEST", a[1])
    for _, item in ipairs(chosen) do
        local deposit = item.status == "booked" or item.status == "inhouse"
        emit_indented(item.id, "room", item.room.number, item.room.kind,
                      date_text(item.arrival), "->", date_text(item.departure), item.status,
                      deposit and "deposit" or "paid", money(deposit and item.deposit or item.paid))
    end
    local total = guest_total(a[1])
    emit_indented("total paid", money(total), "points", total // 100, "tier", tier(a[1]))
end

local function cmd_revenue(a)
    local start, finish = period(a[1], a[2], false, false)
    local lodging, discount, penalty, extras, tax = 0, 0, 0, 0, 0
    local cancellations, noshows, checkouts, cancelled, absent = 0, 0, 0, 0, 0
    for _, id in ipairs(reservation_order) do
        local item = reservations[id]
        if item.posting and start <= item.posting and item.posting <= finish then
            if item.status == "checkedout" then
                checkouts = checkouts + 1
                lodging = lodging + item.bill[1]
                discount = discount + item.bill[2]
                penalty = penalty + item.bill[3]
                extras = extras + item.bill[4]
                tax = tax + item.bill[5]
            elseif item.status == "cancelled" then
                cancelled = cancelled + 1
                cancellations = cancellations + item.fee
            elseif item.status == "noshow" then
                absent = absent + 1
                noshows = noshows + item.fee
            end
        end
    end
    emit("REVENUE", a[1], "->", a[2])
    emit_indented("lodging", money(lodging))
    emit_indented("discount", money(discount))
    emit_indented("penalty", money(penalty))
    emit_indented("extras", money(extras))
    emit_indented("tax", money(tax))
    emit_indented("cancellation", money(cancellations))
    emit_indented("noshow", money(noshows))
    emit_indented("total", money(lodging - discount + penalty + extras + tax + cancellations + noshows))
    emit_indented("checkouts", checkouts, "cancellations", cancelled, "noshows", absent)
end

local handlers = {
    ROOM = cmd_room, RATE = cmd_rate, SEASON = cmd_season,
    BLOCK = cmd_block, UNBLOCK = cmd_unblock, CLEAN = cmd_clean,
    TODAY = cmd_today, BOOK = cmd_book, BOOKROOM = cmd_bookroom,
    WAITLIST = cmd_waitlist, MODIFY = cmd_modify, CANCEL = cmd_cancel,
    CHECKIN = cmd_checkin, MOVE = cmd_move, EXTEND = cmd_extend,
    CHARGE = cmd_charge, PAY = cmd_pay, CHECKOUT = cmd_checkout,
    INVOICE = cmd_invoice, AVAIL = cmd_avail, OCCUPANCY = cmd_occupancy,
    STATS = cmd_stats, ROOMS = cmd_rooms, LIST = cmd_list,
    QUEUE = cmd_queue, SCHEDULE = cmd_schedule, GUEST = cmd_guest,
    REVENUE = cmd_revenue
}

local function execute(line)
    local fields = {}
    for token in line:gmatch("[^ ]+") do fields[#fields + 1] = token end
    local command = fields[1]
    local arguments = {}
    for i = 2, #fields do arguments[#arguments + 1] = fields[i] end
    local ok, reason = pcall(function()
        handlers[command](arguments)
    end)
    if not ok then
        if type(reason) == "table" and reason.message then
            emit("ERROR", reason.message)
        else
            error(reason)
        end
    end
    process_waitlist()
end

local count = tonumber(io.read("*l"))
for _ = 1, count do
    execute(io.read("*l"))
end
if #output > 0 then
    io.write(table.concat(output, "\n"), "\n")
end
