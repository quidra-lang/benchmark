local courses = {"DRINK", "STARTER", "MAIN", "DESSERT"}
local station_names = {"GRILL", "FRY", "COLD", "BAR"}

local state = {
    now = 0,
    tables = {}, table_order = {},
    servers = {}, waiting = {},
    menu = {}, lines = {},
    stations = {}, happy_rate = 0, happy_end = 0,
    covers = 0, parties = 0, turns = 0, stay = 0,
    sales = {}, totals = {subtotal = 0, discount = 0, service = 0, tax = 0, total = 0},
    payments = {CASH = 0, CARD = 0}, tips = 0, comps = 0,
    comp_amount = 0, voids = 0, served = {}, output = {}
}

for _, name in ipairs(courses) do state.sales[name] = 0 end
for _, name in ipairs(station_names) do
    state.stations[name] = {
        up = true, capacity = name == "BAR" and 2 or 1,
        queue = {}, cooking = {}, tickets = {}, remakes = 0
    }
end

local function emit(...)
    local parts = {...}
    for i, value in ipairs(parts) do parts[i] = tostring(value) end
    state.output[#state.output + 1] = table.concat(parts, " ")
end

local function fail(message)
    error({command_error = message}, 0)
end

local function cents(text)
    return tonumber((text:gsub("%.", "")))
end

local function money(value)
    return string.format("%d.%02d", math.floor(value / 100), value % 100)
end

local function clock(time)
    local minutes = 660 + time
    return string.format("%02d:%02d", math.floor(minutes / 60), minutes % 60)
end

local function rounded(value, rate)
    return math.floor((value * rate + 50) / 100)
end

local function get_table(text)
    local result = state.tables[tonumber(text)]
    if not result then fail("unknown table " .. text) end
    return result
end

local function get_check(text)
    local item = get_table(text)
    if not item.check then fail("table " .. text .. " is free") end
    return item.check
end

local function unlocked(check)
    if check.paid > 0 then
        fail("check for table " .. check.table.number .. " is locked")
    end
end

local function get_line(text)
    local id = tonumber(text)
    if id < 1 or id > #state.lines then fail("unknown line " .. text) end
    return state.lines[id]
end

local function modifiable(line)
    if line.status == "VOID" then fail("#" .. line.id .. " is void") end
    if line.check.closed then
        fail("#" .. line.id .. " is on a closed check")
    end
    unlocked(line.check)
end

local function active_lines(check)
    local lines = {}
    for _, line in ipairs(check.lines) do
        if line.status ~= "VOID" then lines[#lines + 1] = line end
    end
    return lines
end

local function unserved(check)
    local count = 0
    for _, line in ipairs(active_lines(check)) do
        if line.status ~= "SERVED" then count = count + 1 end
    end
    if count > 0 then
        fail("table " .. check.table.number .. " has " .. count .. " unserved items")
    end
end

local function get_station(name)
    local result = state.stations[name]
    if not result then fail("unknown station " .. name) end
    return result
end

local function require_course(name)
    for _, course in ipairs(courses) do
        if name == course then return end
    end
    fail("unknown course " .. name)
end

local function get_item(name)
    local result = state.menu[name]
    if not result then fail("unknown item " .. name) end
    return result
end

local function server_load(server)
    local count = 0
    for _, item in ipairs(state.table_order) do
        if item.check and item.check.server == server then count = count + 1 end
    end
    return count
end

local function select_table(size)
    local best = nil
    for _, item in ipairs(state.table_order) do
        if not item.check and item.seats >= size and
           (not best or item.seats < best.seats or
           (item.seats == best.seats and item.number < best.number)) then
            best = item
        end
    end
    return best
end

local function seat_party(party, size, item)
    local server = nil
    for _, candidate in ipairs(state.servers) do
        if not server or server_load(candidate) < server_load(server) then
            server = candidate
        end
    end
    local check = {
        party = party, size = size, table = item, server = server,
        seated = state.now, lines = {}, paid = 0, discount = 0, closed = false
    }
    item.check = check
    server.parties = server.parties + 1
    state.covers = state.covers + size
    state.parties = state.parties + 1
    return check
end

local function process_waiting()
    local remaining = {}
    for _, entry in ipairs(state.waiting) do
        local item = select_table(entry.size)
        if not item then
            remaining[#remaining + 1] = entry
        else
            local check = seat_party(entry.party, entry.size, item)
            emit("SEATED", entry.party, entry.size, "table", item.number,
                 "server", check.server.name, "waited", state.now - entry.joined)
        end
    end
    state.waiting = remaining
end

local function line_amount(line)
    if line.reason then return 0 end
    return line.price * line.quantity
end

local function check_amounts(check)
    local subtotal = 0
    for _, line in ipairs(active_lines(check)) do
        subtotal = subtotal + line_amount(line)
    end
    local discount = rounded(subtotal, check.discount)
    local after = subtotal - discount
    local service = check.size >= 6 and rounded(after, 18) or 0
    local tax = rounded(after, 8)
    local total = after + service + tax
    return {
        subtotal = subtotal, discount = discount, service = service,
        tax = tax, total = total, due = total - check.paid
    }
end

local function close_check(check)
    local amounts = check_amounts(check)
    state.turns = state.turns + 1
    state.stay = state.stay + state.now - check.seated
    for _, line in ipairs(active_lines(check)) do
        state.sales[line.course] = state.sales[line.course] + line_amount(line)
    end
    for field in pairs(state.totals) do
        state.totals[field] = state.totals[field] + amounts[field]
    end
    check.server.sales = check.server.sales + amounts.total
    check.closed = true
    check.table.check = nil
    emit("FREE", "table", check.table.number, check.party, "stayed",
         state.now - check.seated)
    process_waiting()
end

local function start_station(station, time)
    while station.up and #station.queue > 0 and
          #station.cooking < station.capacity do
        local line = table.remove(station.queue, 1)
        line.status = "COOKING"
        line.ready = time + line.prep
        line.started = true
        station.cooking[#station.cooking + 1] = line
    end
end

local function tick(minutes)
    local finish = state.now + minutes
    emit("TICK", clock(finish))
    while true do
        local earliest = nil
        for _, name in ipairs(station_names) do
            for _, line in ipairs(state.stations[name].cooking) do
                if not earliest or line.ready < earliest then earliest = line.ready end
            end
        end
        if not earliest or earliest > finish then break end
        for _, name in ipairs(station_names) do
            local station = state.stations[name]
            local ready, remaining = {}, {}
            for _, line in ipairs(station.cooking) do
                if line.ready == earliest then
                    ready[#ready + 1] = line
                else
                    remaining[#remaining + 1] = line
                end
            end
            station.cooking = remaining
            table.sort(ready, function(a, b) return a.id < b.id end)
            for _, line in ipairs(ready) do
                line.status = "READY"
                station.tickets[#station.tickets + 1] = earliest - line.fire
                emit("READY", clock(earliest), name, "#" .. line.id, line.item,
                     "x" .. line.quantity, "table", line.check.table.number,
                     "seat", line.seat)
            end
        end
        for _, name in ipairs(station_names) do
            start_station(state.stations[name], earliest)
        end
    end
    state.now = finish
end

local function seat_totals(check)
    local totals = {}
    local seats = {}
    for _, line in ipairs(active_lines(check)) do
        if totals[line.seat] == nil then
            totals[line.seat] = 0
            seats[#seats + 1] = line.seat
        end
        totals[line.seat] = totals[line.seat] + line_amount(line)
    end
    table.sort(seats)
    return totals, seats
end

local function allocate(values, seats, rate)
    local result = {}
    local subtotal = 0
    local allocated = 0
    for _, seat in ipairs(seats) do
        subtotal = subtotal + values[seat]
        result[seat] = math.floor(values[seat] * rate / 100)
        allocated = allocated + result[seat]
    end
    local extra = rounded(subtotal, rate) - allocated
    local order = {}
    for _, seat in ipairs(seats) do order[#order + 1] = seat end
    table.sort(order, function(a, b)
        local x, y = values[a] * rate % 100, values[b] * rate % 100
        if x ~= y then return x > y end
        return a < b
    end)
    for i = 1, extra do result[order[i]] = result[order[i]] + 1 end
    return result
end

local function show_bill(check)
    emit("BILL", "table", check.table.number, check.party, "guests", check.size)
    local values, seats = seat_totals(check)
    for _, seat in ipairs(seats) do
        emit("SEAT", seat, money(values[seat]))
        for _, line in ipairs(active_lines(check)) do
            if line.seat == seat then
                if line.reason then
                    emit("#" .. line.id, line.item, "x" .. line.quantity,
                         money(line_amount(line)), "COMP", line.reason)
                else
                    emit("#" .. line.id, line.item, "x" .. line.quantity,
                         money(line_amount(line)))
                end
            end
        end
    end
    local amounts = check_amounts(check)
    emit("SUBTOTAL", money(amounts.subtotal))
    if check.discount ~= 0 then
        emit("DISCOUNT", check.discount .. "%", money(amounts.discount))
    end
    if check.size >= 6 then emit("SERVICE", money(amounts.service)) end
    emit("TAX", money(amounts.tax))
    emit("TOTAL", money(amounts.total))
    if check.paid > 0 then
        emit("PAID", money(check.paid))
        emit("DUE", money(amounts.due))
    end
end

local function show_report()
    emit("REPORT", clock(state.now))
    emit("COVERS", state.covers, "parties", state.parties)
    emit("TURNS", state.turns, "avg_stay",
         state.turns > 0 and math.floor(state.stay / state.turns) or "-")
    local sales = {"SALES"}
    for _, course in ipairs(courses) do
        sales[#sales + 1] = course
        sales[#sales + 1] = money(state.sales[course])
    end
    emit(table.unpack(sales))
    local totals = {"TOTALS"}
    for _, field in ipairs({"subtotal", "discount", "service", "tax", "total"}) do
        totals[#totals + 1] = field
        totals[#totals + 1] = money(state.totals[field])
    end
    emit(table.unpack(totals))
    emit("PAYMENTS", "cash", money(state.payments.CASH),
         "card", money(state.payments.CARD), "tips", money(state.tips))
    emit("COMPS", state.comps, money(state.comp_amount), "VOIDS", state.voids)
    local served = {}
    for name, count in pairs(state.served) do
        if count > 0 then served[#served + 1] = {name, count} end
    end
    table.sort(served, function(a, b)
        if a[2] ~= b[2] then return a[2] > b[2] end
        return a[1] < b[1]
    end)
    for i = 1, math.min(3, #served) do
        emit("TOP", i, served[i][1], served[i][2])
    end
    for _, name in ipairs(station_names) do
        local station = state.stations[name]
        local total, maximum = 0, 0
        for _, ticket in ipairs(station.tickets) do
            total = total + ticket
            maximum = math.max(maximum, ticket)
        end
        local average = #station.tickets > 0 and
                        tostring(math.floor(total / #station.tickets)) or "-"
        emit(name, "tickets", #station.tickets, "avg", average,
             "max", #station.tickets > 0 and maximum or "-", "remakes", station.remakes)
    end
    for _, server in ipairs(state.servers) do
        emit("SERVER", server.name, "tables", server_load(server),
             "parties", server.parties, "sales", money(server.sales),
             "tips", money(server.tips))
    end
end

local function run_command(cmd, a)
    if cmd == "TABLE" then
        local number = tonumber(a[1])
        if state.tables[number] then fail("table " .. a[1] .. " already exists") end
        local item = {number = number, seats = tonumber(a[2])}
        state.tables[number] = item
        state.table_order[#state.table_order + 1] = item
        emit("TABLE", number, "seats", item.seats)
        process_waiting()
    elseif cmd == "STAFF" then
        for _, server in ipairs(state.servers) do
            if server.name == a[1] then fail(a[1] .. " is already on duty") end
        end
        state.servers[#state.servers + 1] = {name = a[1], parties = 0, sales = 0, tips = 0}
        emit("STAFF", a[1])
    elseif cmd == "SEAT" then
        for _, item in ipairs(state.table_order) do
            if item.check and item.check.party == a[1] then
                fail(a[1] .. " is already seated at table " .. item.number)
            end
        end
        for _, entry in ipairs(state.waiting) do
            if entry.party == a[1] then fail(a[1] .. " is already waiting") end
        end
        local size = tonumber(a[2])
        local exists = false
        for _, item in ipairs(state.table_order) do
            if item.seats >= size then exists = true end
        end
        if not exists then fail("no table for party of " .. size) end
        if #state.servers == 0 then fail("no server on duty") end
        local item = select_table(size)
        if not item then
            state.waiting[#state.waiting + 1] =
                {party = a[1], size = size, joined = state.now}
            emit("WAIT", a[1], size, "position", #state.waiting)
        else
            local check = seat_party(a[1], size, item)
            emit("SEAT", a[1], size, "table", item.number, "server", check.server.name)
        end
    elseif cmd == "CANCEL" then
        local found = nil
        for i, entry in ipairs(state.waiting) do
            if entry.party == a[1] then found = i; break end
        end
        if not found then fail(a[1] .. " is not waiting") end
        local entry = table.remove(state.waiting, found)
        emit("CANCEL", entry.party, entry.size, "waited", state.now - entry.joined)
    elseif cmd == "MOVE" then
        local source = get_table(a[1])
        local destination = get_table(a[2])
        if not source.check then fail("table " .. a[1] .. " is free") end
        if destination.check then fail("table " .. a[2] .. " is occupied") end
        local check = source.check
        if destination.seats < check.size then
            fail("table " .. a[2] .. " is too small for " .. check.party)
        end
        source.check = nil
        destination.check = check
        check.table = destination
        emit("MOVE", check.party, "table", source.number, "->", destination.number)
        process_waiting()
    elseif cmd == "MENU" then
        get_station(a[2])
        require_course(a[5])
        local old = state.menu[a[1]]
        local item = {
            name = a[1], station = a[2], prep = tonumber(a[3]),
            price = cents(a[4]), course = a[5],
            stock = old and old.stock or nil
        }
        state.menu[item.name] = item
        emit("MENU", old and "UPDATE" or "ADD", item.name, item.station,
             item.prep, money(item.price), item.course)
    elseif cmd == "STOCK" then
        local item = get_item(a[1])
        item.stock = tonumber(a[2])
        emit("STOCK", item.name, item.stock)
    elseif cmd == "HAPPY" then
        state.happy_rate = tonumber(a[1])
        state.happy_end = state.now + tonumber(a[2])
        emit("HAPPY", state.happy_rate .. "%", "until", clock(state.happy_end))
    elseif cmd == "ITEMS" then
        local items = {}
        for _, item in pairs(state.menu) do items[#items + 1] = item end
        local position = {}
        for i, course in ipairs(courses) do position[course] = i end
        table.sort(items, function(a, b)
            if a.course ~= b.course then return position[a.course] < position[b.course] end
            return a.name < b.name
        end)
        emit("ITEMS", #items)
        for _, item in ipairs(items) do
            emit(item.course, item.name, item.station, item.prep,
                 money(item.price), item.stock or "-")
        end
    elseif cmd == "ORDER" then
        local check = get_check(a[1])
        unlocked(check)
        local seat = tonumber(a[2])
        if seat > check.size then
            fail("seat " .. seat .. " out of range for table " .. a[1])
        end
        local item = get_item(a[3])
        local quantity = tonumber(a[4])
        if item.stock and item.stock < quantity then
            fail("only " .. item.stock .. " " .. item.name .. " left")
        end
        local happy = item.course == "DRINK" and state.now < state.happy_end
        local price = item.price - (happy and rounded(item.price, state.happy_rate) or 0)
        local line = {
            id = #state.lines + 1, check = check, seat = seat, item = item.name,
            quantity = quantity, station = item.station, prep = item.prep,
            price = price, course = item.course, status = "ORDERED",
            fire = 0, ready = 0, started = false
        }
        state.lines[#state.lines + 1] = line
        check.lines[#check.lines + 1] = line
        if happy then
            emit("ORDER", "#" .. line.id, "table", check.table.number, "seat",
                 seat, item.name, "x" .. quantity, money(line_amount(line)), "HAPPY")
        else
            emit("ORDER", "#" .. line.id, "table", check.table.number, "seat",
                 seat, item.name, "x" .. quantity, money(line_amount(line)))
        end
        if item.stock then
            item.stock = item.stock - quantity
            if item.stock == 0 then emit("SOLDOUT", item.name) end
        end
    elseif cmd == "FIRE" then
        local check = get_check(a[1])
        require_course(a[2])
        local lines = {}
        for _, line in ipairs(check.lines) do
            if line.course == a[2] and line.status == "ORDERED" then
                lines[#lines + 1] = line
            end
        end
        if #lines == 0 then
            fail("nothing to fire for " .. a[2] .. " at table " .. a[1])
        end
        if a[2] == "MAIN" or a[2] == "DESSERT" then
            local before = a[2] == "MAIN" and {"STARTER"} or {"STARTER", "MAIN"}
            for _, earlier in ipairs(before) do
                for _, line in ipairs(check.lines) do
                    if line.course == earlier and line.status == "ORDERED" then
                        fail("fire " .. earlier .. " first")
                    end
                end
            end
        end
        local ids = {}
        for _, line in ipairs(lines) do
            line.status = "QUEUED"
            line.fire = state.now
            local station = state.stations[line.station]
            station.queue[#station.queue + 1] = line
            ids[#ids + 1] = "#" .. line.id
        end
        emit("FIRE", "table", check.table.number, a[2], table.unpack(ids))
        for _, name in ipairs(station_names) do
            start_station(state.stations[name], state.now)
        end
    elseif cmd == "TICK" then
        tick(tonumber(a[1]))
    elseif cmd == "SERVE" then
        local check = get_check(a[1])
        local lines = {}
        for _, line in ipairs(check.lines) do
            if line.status == "READY" then lines[#lines + 1] = line end
        end
        if #lines == 0 then fail("nothing ready for table " .. a[1]) end
        local ids = {}
        for _, line in ipairs(lines) do
            line.status = "SERVED"
            state.served[line.item] = (state.served[line.item] or 0) + line.quantity
            ids[#ids + 1] = "#" .. line.id
        end
        emit("SERVE", "table", check.table.number, table.unpack(ids))
    elseif cmd == "RUSH" then
        local line = get_line(a[1])
        if line.status ~= "QUEUED" then fail("#" .. line.id .. " is not queued") end
        local station = state.stations[line.station]
        for i, entry in ipairs(station.queue) do
            if entry == line then table.remove(station.queue, i); break end
        end
        table.insert(station.queue, 1, line)
        emit("RUSH", "#" .. line.id, line.station)
    elseif cmd == "REMAKE" then
        local line = get_line(a[1])
        if line.check.closed then fail("#" .. line.id .. " is on a closed check") end
        if line.status ~= "READY" and line.status ~= "SERVED" then
            fail("#" .. line.id .. " is not ready or served")
        end
        line.status = "QUEUED"
        line.fire = state.now
        local station = state.stations[line.station]
        table.insert(station.queue, 1, line)
        station.remakes = station.remakes + 1
        emit("REMAKE", "#" .. line.id, line.item, line.station)
        start_station(station, state.now)
    elseif cmd == "VOID" then
        local line = get_line(a[1])
        if line.status == "VOID" then fail("#" .. line.id .. " is already void") end
        if line.started then fail("#" .. line.id .. " has already started") end
        if line.status == "QUEUED" then
            local queue = state.stations[line.station].queue
            for i, entry in ipairs(queue) do
                if entry == line then table.remove(queue, i); break end
            end
        end
        line.status = "VOID"
        local item = state.menu[line.item]
        if item.stock then item.stock = item.stock + line.quantity end
        state.voids = state.voids + 1
        emit("VOID", "#" .. line.id, line.item, "x" .. line.quantity)
    elseif cmd == "STATION" then
        local station = get_station(a[1])
        if a[2] == "DOWN" and not station.up then
            fail("station " .. a[1] .. " is already down")
        end
        if a[2] == "UP" and station.up then
            fail("station " .. a[1] .. " is not down")
        end
        station.up = a[2] == "UP"
        if station.up then start_station(station, state.now) end
        emit("STATION", a[1], a[2])
    elseif cmd == "COMP" or cmd == "TRANSFER" then
        local line = get_line(a[1])
        modifiable(line)
        if cmd == "COMP" then
            if line.reason then fail("#" .. line.id .. " is already comped") end
            local value = line_amount(line)
            emit("COMP", "#" .. line.id, line.item, money(value), a[2])
            state.comps = state.comps + 1
            state.comp_amount = state.comp_amount + value
            line.reason = a[2]
        else
            local seat = tonumber(a[2])
            if seat > line.check.size then
                fail("seat " .. seat .. " out of range for table " .. line.check.table.number)
            end
            if seat == line.seat then
                fail("#" .. line.id .. " is already on seat " .. seat)
            end
            emit("TRANSFER", "#" .. line.id, "seat", line.seat, "->", seat)
            line.seat = seat
        end
    elseif cmd == "DISCOUNT" then
        local check = get_check(a[1])
        unlocked(check)
        check.discount = tonumber(a[2])
        emit("DISCOUNT", "table", check.table.number, check.discount .. "%")
    elseif cmd == "BILL" then
        show_bill(get_check(a[1]))
    elseif cmd == "SPLIT" then
        local check = get_check(a[1])
        local amounts = check_amounts(check)
        if amounts.due == 0 then fail("nothing to split for table " .. a[1]) end
        if a[2] == "EVEN" then
            local count = tonumber(a[3])
            if count > check.size then
                fail("cannot split table " .. a[1] .. " " .. count .. " ways")
            end
            emit("SPLIT", "table", check.table.number, "EVEN", count,
                 "due", money(amounts.due))
            local quotient = math.floor(amounts.due / count)
            local remainder = amounts.due % count
            for i = 1, count do
                emit("PAYER", i, money(quotient + (i <= remainder and 1 or 0)))
            end
        else
            if check.paid > 0 then fail("table " .. a[1] .. " has payments") end
            local values, seats = seat_totals(check)
            local discounts = allocate(values, seats, check.discount)
            local after = {}
            for _, seat in ipairs(seats) do after[seat] = values[seat] - discounts[seat] end
            local services = allocate(after, seats, check.size >= 6 and 18 or 0)
            local taxes = allocate(after, seats, 8)
            emit("SPLIT", "table", check.table.number, "BYSEAT", "total", money(amounts.total))
            for _, seat in ipairs(seats) do
                emit("SEAT", seat, "subtotal", money(values[seat]),
                     "discount", money(discounts[seat]), "service", money(services[seat]),
                     "tax", money(taxes[seat]),
                     "total", money(after[seat] + services[seat] + taxes[seat]))
            end
        end
    elseif cmd == "PAY" then
        local check = get_check(a[1])
        if a[2] ~= "CASH" and a[2] ~= "CARD" then
            fail("unknown method " .. a[2])
        end
        unserved(check)
        local due = check_amounts(check).due
        if due == 0 then fail("nothing to pay for table " .. a[1]) end
        local value = cents(a[3])
        local applied = math.min(value, due)
        check.paid = check.paid + applied
        state.payments[a[2]] = state.payments[a[2]] + applied
        if value < due then
            emit("PAY", "table", check.table.number, a[2], money(value),
                 "remaining", money(due - value))
        else
            emit("PAY", "table", check.table.number, a[2], money(value),
                 a[2] == "CASH" and "change" or "tip", money(value - due))
            if a[2] == "CARD" then
                state.tips = state.tips + value - due
                check.server.tips = check.server.tips + value - due
            end
            close_check(check)
        end
    elseif cmd == "CLOSE" then
        local check = get_check(a[1])
        unserved(check)
        local due = check_amounts(check).due
        if due ~= 0 then
            fail("table " .. a[1] .. " still owes " .. money(due))
        end
        close_check(check)
    elseif cmd == "STATUS" then
        local check = get_check(a[1])
        emit("STATUS", "table", check.table.number, check.party, "guests",
             check.size, "since", clock(check.seated))
        for _, line in ipairs(check.lines) do
            local parts = {
                "#" .. line.id, "seat", line.seat, line.item, "x" .. line.quantity,
                line.course, line.status
            }
            if line.status == "COOKING" then
                parts[#parts + 1] = "until"
                parts[#parts + 1] = clock(line.ready)
            end
            if line.reason then
                parts[#parts + 1] = "COMP"
                parts[#parts + 1] = line.reason
            end
            emit(table.unpack(parts))
        end
    elseif cmd == "KITCHEN" then
        emit("KITCHEN", clock(state.now))
        for _, name in ipairs(station_names) do
            local station = state.stations[name]
            local cooking = {}
            for _, line in ipairs(station.cooking) do cooking[#cooking + 1] = line end
            table.sort(cooking, function(a, b)
                if a.ready ~= b.ready then return a.ready < b.ready end
                return a.id < b.id
            end)
            local cooking_text, queue_text = {}, {}
            for _, line in ipairs(cooking) do
                cooking_text[#cooking_text + 1] = "#" .. line.id .. "@" .. clock(line.ready)
            end
            for _, line in ipairs(station.queue) do
                queue_text[#queue_text + 1] = "#" .. line.id
            end
            emit(name, station.up and "up" or "down", "cooking",
                 #cooking_text > 0 and table.concat(cooking_text, " ") or "-",
                 "queue", #queue_text > 0 and table.concat(queue_text, " ") or "-")
        end
    elseif cmd == "FLOOR" then
        local tables = {}
        for _, item in ipairs(state.table_order) do tables[#tables + 1] = item end
        table.sort(tables, function(a, b) return a.number < b.number end)
        local free = 0
        for _, item in ipairs(tables) do
            if not item.check then free = free + 1 end
        end
        emit("FLOOR", clock(state.now), "free", free,
             "seated", #tables - free, "waiting", #state.waiting)
        for _, item in ipairs(tables) do
            if not item.check then
                emit("table", item.number, "seats", item.seats, "free")
            else
                local check = item.check
                local parts = {
                    "table", item.number, "seats", item.seats, check.party,
                    "guests", check.size, "server", check.server.name,
                    "since", clock(check.seated), "items", #active_lines(check),
                    "total", money(check_amounts(check).total)
                }
                if check.paid > 0 then
                    parts[#parts + 1] = "paid"
                    parts[#parts + 1] = money(check.paid)
                end
                emit(table.unpack(parts))
            end
        end
        for i, entry in ipairs(state.waiting) do
            emit("WAITING", i, entry.party, entry.size, "since", clock(entry.joined))
        end
    elseif cmd == "REPORT" then
        show_report()
    end
end

local function execute(line)
    local fields = {}
    for token in line:gmatch("[^ ]+") do fields[#fields + 1] = token end
    local name = fields[1]
    local args = {}
    for i = 2, #fields do args[#args + 1] = fields[i] end
    local ok, message = pcall(run_command, name, args)
    if not ok then
        if type(message) == "table" and message.command_error then
            emit("ERROR", message.command_error)
        else
            error(message)
        end
    end
end

local count = tonumber(io.read("*l"))
for _ = 1, count do
    execute(io.read("*l"))
end
io.write(table.concat(state.output, "\n"), "\n")
