local stations, lines, closed = {}, {}, {}
local walk_count, tariff = 0, nil
local output = {}

local function emit(pattern, ...)
    output[#output + 1] = string.format(pattern, ...)
end

local function fail(pattern, ...)
    error(string.format(pattern, ...), 0)
end

local function keys(items)
    local result = {}
    for key in pairs(items) do
        result[#result + 1] = key
    end
    table.sort(result)
    return result
end

local function time_value(text)
    return tonumber(text:sub(1, 2)) * 60 + tonumber(text:sub(4, 5))
end

local function time_text(value)
    return string.format("%02d:%02d", value // 60, value % 60)
end

local function segment(a, b)
    if a > b then
        a, b = b, a
    end
    return a .. "\0" .. b
end

local function get_station(id)
    if not stations[id] then
        fail("unknown station %s", id)
    end
    return stations[id]
end

local function get_line(id)
    if not lines[id] then
        fail("unknown line %s", id)
    end
    return lines[id]
end

local function common(origin, destination)
    local a, b = get_station(origin), get_station(destination)
    if a == b then
        fail("origin and destination are the same")
    end
    if a.closed then
        fail("station %s is closed", origin)
    end
    if b.closed then
        fail("station %s is closed", destination)
    end
    return a, b
end

local function direction(service, which)
    if which == 0 then
        return service.stops, service.cumulative
    end
    local stops, offsets = {}, {}
    for i = #service.stops, 1, -1 do
        stops[#stops + 1] = service.stops[i]
        offsets[#offsets + 1] = service.total - service.cumulative[i]
    end
    return stops, offsets
end

local function index_of(stops, station)
    for i, candidate in ipairs(stops) do
        if candidate == station then
            return i
        end
    end
    return nil
end

local function trains(service)
    return (service.last - service.first) // service.headway + 1
end

local function first_train(service, offset, ready)
    local base = service.first + service.delay + offset
    local q = math.max(0, (ready - base + service.headway - 1) // service.headway)
    if q < trains(service) then
        return q
    end
    return nil
end

local function train_time(service, q, offset)
    return service.first + service.delay + q * service.headway + offset
end

local function extend(journey, leg)
    local result = {}
    for i, part in ipairs(journey) do
        result[i] = part
    end
    result[#result + 1] = leg
    return result
end

local function improves(labels, target, arrival)
    return not labels[target] or arrival < labels[target].arrival
end

local function ride(service, stops, a, b, depart, arrive)
    return {
        kind = "ride", service = service, terminal = stops[#stops],
        from = stops[a], to = stops[b], depart = depart, arrive = arrive,
        stops = b - a,
    }
end

local function walk(a, b, depart, arrive)
    return {kind = "walk", from = a, to = b, depart = depart, arrive = arrive}
end

local function earliest(origin, start)
    local labels = {[origin] = {arrival = start, journey = {}}}
    local settled = {}
    local services = keys(lines)
    while true do
        local selected
        for station, value in pairs(labels) do
            if not settled[station] and (not selected or value.arrival < labels[selected].arrival or
                (value.arrival == labels[selected].arrival and station.id < selected.id)) then
                selected = station
            end
        end
        if not selected then
            return labels
        end
        settled[selected] = true
        local current = labels[selected]
        local ready = current.arrival + (selected == origin and 0 or selected.transfer)
        for _, id in ipairs(services) do
            local service = lines[id]
            if not service.suspended then
                for which = 0, 1 do
                    local stops, offsets = direction(service, which)
                    local i = index_of(stops, selected)
                    if i and i < #stops then
                        local q = first_train(service, offsets[i], ready)
                        if q then
                            local depart = train_time(service, q, offsets[i])
                            for j = i + 1, #stops do
                                local target = stops[j]
                                if closed[segment(stops[j - 1].id, target.id)] then
                                    break
                                end
                                if not target.closed then
                                    local arrival = train_time(service, q, offsets[j])
                                    if improves(labels, target, arrival) then
                                        labels[target] = {arrival = arrival, journey = extend(current.journey,
                                            ride(service, stops, i, j, depart, arrival))}
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
        for _, id in ipairs(keys(selected.walks)) do
            local target = stations[id]
            local arrival = current.arrival + selected.walks[id]
            if not target.closed and arrival <= 1440 and improves(labels, target, arrival) then
                labels[target] = {arrival = arrival, journey = extend(current.journey,
                    walk(selected, target, current.arrival, arrival))}
            end
        end
    end
end

local function station_order(set)
    local result = {}
    for station in pairs(set) do
        result[#result + 1] = station
    end
    table.sort(result, function(a, b) return a.id < b.id end)
    return result
end

local function walk_step(labels, sources, marked)
    local recorded = {}
    for station in pairs(sources) do
        recorded[station] = labels[station]
    end
    for _, source in ipairs(station_order(sources)) do
        local current = recorded[source]
        for _, id in ipairs(keys(source.walks)) do
            local target = stations[id]
            local arrival = current.arrival + source.walks[id]
            if not target.closed and arrival <= 1440 and improves(labels, target, arrival) then
                labels[target] = {arrival = arrival, journey = extend(current.journey,
                    walk(source, target, current.arrival, arrival))}
                marked[target] = true
            end
        end
    end
end

local function rounds(origin, start, stop)
    local current = {[origin] = {arrival = start, journey = {}}}
    local marked = {[origin] = true}
    walk_step(current, {[origin] = true}, marked)
    local result = {current}
    local services = keys(lines)
    while next(marked) do
        if stop and current[stop] then
            break
        end
        local following, updated, walking = {}, {}, {}
        for station, value in pairs(current) do
            following[station] = value
        end
        for _, id in ipairs(services) do
            local service = lines[id]
            if not service.suspended then
                for which = 0, 1 do
                    local stops, offsets = direction(service, which)
                    local q, boarding, depart, prefix
                    for j, target in ipairs(stops) do
                        if j > 1 and closed[segment(stops[j - 1].id, target.id)] then
                            q = nil
                        end
                        if not target.closed then
                            if q then
                                local arrival = train_time(service, q, offsets[j])
                                if improves(following, target, arrival) then
                                    following[target] = {arrival = arrival, journey = extend(prefix,
                                        ride(service, stops, boarding, j, depart, arrival))}
                                    walking[target], updated[target] = true, true
                                end
                            end
                            if j < #stops and marked[target] then
                                local previous = current[target]
                                local ready = previous.arrival + (target == origin and 0 or target.transfer)
                                local candidate = first_train(service, offsets[j], ready)
                                if candidate and (not q or candidate < q) then
                                    q, boarding = candidate, j
                                    depart = train_time(service, q, offsets[j])
                                    prefix = previous.journey
                                end
                            end
                        end
                    end
                end
            end
        end
        walk_step(following, walking, updated)
        result[#result + 1] = following
        current, marked = following, updated
    end
    return result
end

local function counts(journey)
    local rides, walks = 0, 0
    for _, leg in ipairs(journey) do
        if leg.kind == "ride" then
            rides = rides + 1
        elseif leg.kind == "walk" then
            walks = walks + 1
        end
    end
    return rides, walks
end

local function print_journey(heading, start, result)
    local rides, walks = counts(result.journey)
    emit("%s %s -> %s total %d rides %d walks %d", heading, time_text(start),
        time_text(result.arrival), result.arrival - start, rides, walks)
    local previous = start
    for _, leg in ipairs(result.journey) do
        if leg.kind == "ride" then
            emit("RIDE %s toward %s %s %s -> %s %s wait %d stops %d", leg.service.id,
                leg.terminal.id, leg.from.id, time_text(leg.depart), leg.to.id,
                time_text(leg.arrive), leg.depart - previous, leg.stops)
        elseif leg.kind == "walk" then
            emit("WALK %s %s -> %s %s", leg.from.id, time_text(leg.depart),
                leg.to.id, time_text(leg.arrive))
        else
            emit("STAY %s %s -> %s", leg.from.id, time_text(leg.depart), time_text(leg.arrive))
        end
        previous = leg.arrive
    end
end

local function segment_lines(a, b)
    local result = {}
    for _, id in ipairs(keys(lines)) do
        local service = lines[id]
        for i = 2, #service.stops do
            local x, y = service.stops[i - 1], service.stops[i]
            if (x == a and y == b) or (x == b and y == a) then
                result[#result + 1] = id
                break
            end
        end
    end
    return result
end

local function half(value)
    return (value + 19) // 20 * 10
end

local function print_fare(origin, destination, start, class, result)
    local tickets, total, previous = {}, 0, nil
    for _, leg in ipairs(result.journey) do
        if leg.kind == "ride" then
            local a, b = index_of(leg.service.stops, leg.from), index_of(leg.service.stops, leg.to)
            if a > b then
                a, b = b, a
            end
            local zones, zone_count = {}, 0
            for i = a, b do
                local zone = leg.service.stops[i].zone
                if not zones[zone] then
                    zones[zone], zone_count = true, zone_count + 1
                end
            end
            local price = tariff.prices[math.min(zone_count, #tariff.prices)]
            local cap = tariff.discount
            if class == "CHILD" then
                price, cap = half(price), half(cap)
            end
            local discount = 0
            if previous and leg.depart - previous <= tariff.window then
                discount = math.min(cap, price)
            end
            tickets[#tickets + 1] = {leg = leg, zones = zone_count, price = price, discount = discount}
            total, previous = total + price - discount, leg.arrive
        end
    end
    emit("FARE %s %s %s %s rides %d total %d", origin, destination, time_text(start), class, #tickets, total)
    for _, ticket in ipairs(tickets) do
        local leg = ticket.leg
        emit("TICKET %s %s %s zones %d price %d discount %d pay %d", leg.service.id,
            leg.from.id, leg.to.id, ticket.zones, ticket.price, ticket.discount, ticket.price - ticket.discount)
    end
end

local function command(w)
    local cmd = w[1]
    if cmd == "STATION" then
        if stations[w[2]] then
            fail("station %s already exists", w[2])
        end
        stations[w[2]] = {id = w[2], zone = tonumber(w[3]), name = w[4], transfer = 0, walks = {}}
        emit("STATION %s zone %s %s", w[2], w[3], w[4])
    elseif cmd == "LINE" then
        if lines[w[2]] then
            fail("line %s already exists", w[2])
        end
        local stops, seen, cumulative = {}, {}, {0}
        for i = 6, #w, 2 do
            stops[#stops + 1] = get_station(w[i])
        end
        for _, station in ipairs(stops) do
            if seen[station] then
                fail("station %s appears twice on line %s", station.id, w[2])
            end
            seen[station] = true
        end
        local first, last = time_value(w[3]), time_value(w[4])
        if first > last then
            fail("line %s first departure is after last departure", w[2])
        end
        for i = 7, #w, 2 do
            cumulative[#cumulative + 1] = cumulative[#cumulative] + tonumber(w[i])
        end
        local total = cumulative[#cumulative]
        if last + total > 1440 then
            fail("line %s runs past 24:00", w[2])
        end
        local service = {id = w[2], first = first, last = last, headway = tonumber(w[5]),
            total = total, stops = stops, cumulative = cumulative, delay = 0}
        lines[w[2]] = service
        emit("LINE %s stops %d time %d trips %d", service.id, #stops, total, trains(service))
    elseif cmd == "TRANSFER" then
        local station = get_station(w[2])
        station.transfer = tonumber(w[3])
        emit("TRANSFER %s %d", station.id, station.transfer)
    elseif cmd == "WALK" then
        local a, b = get_station(w[2]), get_station(w[3])
        if a == b then
            fail("walk from %s to itself", a.id)
        end
        local previous, minutes = a.walks[b.id], tonumber(w[4])
        a.walks[b.id], b.walks[a.id] = minutes, minutes
        local suffix = ""
        if previous then
            suffix = " was " .. previous
        else
            walk_count = walk_count + 1
        end
        emit("WALK %s %s %d%s", a.id, b.id, minutes, suffix)
    elseif cmd == "TARIFF" then
        local prices = {}
        for i = 4, #w do
            local price = tonumber(w[i])
            if #prices > 0 and price < prices[#prices] then
                fail("tariff prices must not decrease")
            end
            prices[#prices + 1] = price
        end
        tariff = {discount = tonumber(w[2]), window = tonumber(w[3]), prices = prices}
        emit("TARIFF zones %d discount %s window %s", #prices, w[2], w[3])
    elseif cmd == "CLOSE" or cmd == "OPEN" then
        local a = get_station(w[2])
        if #w == 2 then
            if cmd == "CLOSE" and a.closed then
                fail("station %s is already closed", a.id)
            end
            if cmd == "OPEN" and not a.closed then
                fail("station %s is not closed", a.id)
            end
            a.closed = cmd == "CLOSE"
            emit("%s %s", cmd, a.id)
        else
            local b = get_station(w[3])
            local key = segment(a.id, b.id)
            if cmd == "CLOSE" then
                local services = segment_lines(a, b)
                if #services == 0 then
                    fail("no segment %s-%s", a.id, b.id)
                end
                if closed[key] then
                    fail("segment %s-%s is already closed", a.id, b.id)
                end
                closed[key] = true
                emit("CLOSE %s-%s lines %s", a.id, b.id, table.concat(services, " "))
            else
                if not closed[key] then
                    fail("segment %s-%s is not closed", a.id, b.id)
                end
                closed[key] = nil
                emit("OPEN %s-%s", a.id, b.id)
            end
        end
    elseif cmd == "DELAY" or cmd == "SUSPEND" or cmd == "RESUME" then
        local service = get_line(w[2])
        if cmd == "DELAY" then
            local minutes = tonumber(w[3])
            if service.last + minutes + service.total > 1440 then
                fail("line %s runs past 24:00", service.id)
            end
            service.delay = minutes
            emit("DELAY %s %d", service.id, minutes)
        else
            if cmd == "SUSPEND" and service.suspended then
                fail("line %s is already suspended", service.id)
            end
            if cmd == "RESUME" and not service.suspended then
                fail("line %s is not suspended", service.id)
            end
            service.suspended = cmd == "SUSPEND"
            emit("%s %s", cmd, service.id)
        end
    elseif cmd == "ROUTE" or cmd == "FEWEST" or cmd == "PARETO" or cmd == "FARE" or
        cmd == "LASTTRAIN" or cmd == "ARRIVEBY" or cmd == "PROFILE" then
        local origin, destination = common(w[2], w[3])
        if cmd == "FARE" then
            if w[5] ~= "ADULT" and w[5] ~= "CHILD" then
                fail("unknown fare class %s", w[5])
            end
            if not tariff then
                fail("no tariff")
            end
        end
        local start = w[4] and time_value(w[4]) or 0
        if cmd == "PROFILE" then
            local finish = time_value(w[5])
            if start > finish then
                fail("empty interval %s %s", w[4], w[5])
            end
            local arrivals, selected = {}, {}
            for t = start, finish do
                local result = earliest(origin, t)[destination]
                arrivals[t] = result and result.arrival or false
            end
            for t = start, finish do
                local arrival = arrivals[t]
                if arrival and (t == finish or not arrivals[t + 1] or arrival < arrivals[t + 1]) then
                    selected[#selected + 1] = t
                end
            end
            emit("PROFILE %s %s %s %s count %d", origin.id, destination.id, w[4], w[5], #selected)
            for _, t in ipairs(selected) do
                emit("%s -> %s total %d", time_text(t), time_text(arrivals[t]), arrivals[t] - t)
            end
        elseif cmd == "LASTTRAIN" or cmd == "ARRIVEBY" then
            local latest = cmd == "LASTTRAIN" and 1439 or start - 1
            local heading = cmd .. " " .. origin.id .. " " .. destination.id
            if cmd == "ARRIVEBY" then
                heading = heading .. " by " .. w[4]
            end
            for t = latest, 0, -1 do
                local result = earliest(origin, t)[destination]
                if result and (cmd == "LASTTRAIN" or result.arrival <= start) then
                    print_journey(heading, t, result)
                    return
                end
            end
            emit("%s none", heading)
        elseif cmd == "FEWEST" or cmd == "PARETO" then
            local results = rounds(origin, start, cmd == "FEWEST" and destination or nil)
            if cmd == "FEWEST" then
                for i, labels in ipairs(results) do
                    if labels[destination] then
                        print_journey(string.format("FEWEST %s %s trips %d", origin.id, destination.id, i - 1),
                            start, labels[destination])
                        return
                    end
                end
                emit("FEWEST %s %s %s unreachable", origin.id, destination.id, w[4])
            else
                local options, previous = {}, nil
                for i, labels in ipairs(results) do
                    local result = labels[destination]
                    if result then
                        if not previous or result.arrival < previous then
                            options[#options + 1] = i
                        end
                        previous = result.arrival
                    end
                end
                emit("PARETO %s %s %s options %d", origin.id, destination.id, w[4], #options)
                for _, i in ipairs(options) do
                    print_journey(string.format("OPTION trips %d", i - 1), start, results[i][destination])
                end
            end
        else
            local result = earliest(origin, start)[destination]
            if not result then
                emit("%s %s %s %s%s unreachable", cmd, origin.id, destination.id, w[4],
                    cmd == "FARE" and " " .. w[5] or "")
            elseif cmd == "FARE" then
                print_fare(origin.id, destination.id, start, w[5], result)
            else
                print_journey("ROUTE " .. origin.id .. " " .. destination.id, start, result)
            end
        end
    elseif cmd == "VIA" then
        local origin, via, destination = get_station(w[2]), get_station(w[3]), get_station(w[4])
        if origin == destination then
            fail("origin and destination are the same")
        end
        if via == origin or via == destination then
            fail("via station %s must differ from origin and destination", via.id)
        end
        for _, station in ipairs({origin, via, destination}) do
            if station.closed then
                fail("station %s is closed", station.id)
            end
        end
        local start = time_value(w[5])
        local first = earliest(origin, start)[via]
        if first then
            local ready = first.arrival + via.transfer
            local second = earliest(via, ready)[destination]
            if second then
                local journey = extend(first.journey, {kind = "stay", from = via, to = via,
                    depart = first.arrival, arrive = ready})
                for _, leg in ipairs(second.journey) do
                    journey[#journey + 1] = leg
                end
                print_journey("VIA " .. origin.id .. " " .. via.id .. " " .. destination.id,
                    start, {arrival = second.arrival, journey = journey})
                return
            end
        end
        emit("VIA %s %s %s %s unreachable", origin.id, via.id, destination.id, w[5])
    elseif cmd == "REACH" then
        local origin = get_station(w[2])
        if origin.closed then
            fail("station %s is closed", origin.id)
        end
        local start, duration = time_value(w[3]), tonumber(w[4])
        local labels, selected = earliest(origin, start), {}
        for station, result in pairs(labels) do
            if result.arrival <= start + duration then
                selected[#selected + 1] = station
            end
        end
        table.sort(selected, function(a, b)
            if labels[a].arrival ~= labels[b].arrival then
                return labels[a].arrival < labels[b].arrival
            end
            return a.id < b.id
        end)
        emit("REACH %s %s %d count %d", origin.id, w[3], duration, #selected)
        for _, station in ipairs(selected) do
            local result = labels[station]
            emit("%s %s %s %d rides %d", station.id, station.name, time_text(result.arrival),
                result.arrival - start, counts(result.journey))
        end
    elseif cmd == "TIMETABLE" then
        local station, service = get_station(w[2]), get_line(w[3])
        if not index_of(service.stops, station) then
            fail("station %s is not on line %s", station.id, service.id)
        end
        local first, last = service.stops[1], service.stops[#service.stops]
        if w[4] ~= first.id and w[4] ~= last.id then
            fail("%s is not a terminal of line %s", w[4], service.id)
        end
        if station.id == w[4] then
            fail("no departures from %s toward %s", station.id, w[4])
        end
        if service.suspended then
            fail("line %s is suspended", service.id)
        end
        if station.closed then
            fail("station %s is closed", station.id)
        end
        local stops, offsets = direction(service, w[4] == first.id and 1 or 0)
        local at = index_of(stops, station)
        local q = first_train(service, offsets[at], time_value(w[5]))
        local times = {}
        if q then
            while q < trains(service) and #times < tonumber(w[6]) do
                times[#times + 1] = time_text(train_time(service, q, offsets[at]))
                q = q + 1
            end
        end
        emit("TIMETABLE %s %s toward %s %s next %d%s", station.id, service.id, w[4], w[5],
            #times, #times > 0 and " " .. table.concat(times, " ") or "")
    elseif cmd == "DEPARTURES" or cmd == "ARRIVALS" then
        local station = get_station(w[2])
        if station.closed then
            fail("station %s is closed", station.id)
        end
        local choices = {}
        for _, id in ipairs(keys(lines)) do
            local service = lines[id]
            if not service.suspended then
                for which = 0, 1 do
                    local stops, offsets = direction(service, which)
                    local at = index_of(stops, station)
                    if at and not (cmd == "DEPARTURES" and at == #stops) and
                        not (cmd == "ARRIVALS" and at == 1) then
                        local q = first_train(service, offsets[at], time_value(w[3]))
                        if q then
                            for train = q, trains(service) - 1 do
                                choices[#choices + 1] = {time = train_time(service, train, offsets[at]),
                                    service = service, direction = which, terminal = stops[#stops], start = stops[1]}
                            end
                        end
                    end
                end
            end
        end
        table.sort(choices, function(a, b)
            if a.time ~= b.time then
                return a.time < b.time
            end
            if a.service.id ~= b.service.id then
                return a.service.id < b.service.id
            end
            return a.direction < b.direction
        end)
        local count = math.min(#choices, tonumber(w[4]))
        emit("%s %s %s count %d", cmd, station.id, w[3], count)
        for i = 1, count do
            local choice = choices[i]
            emit("%s %s %s %s", time_text(choice.time), choice.service.id,
                cmd == "DEPARTURES" and "toward" or "from",
                cmd == "DEPARTURES" and choice.terminal.id or choice.start.id)
        end
    elseif cmd == "TRIP" or cmd == "SHOWLINE" then
        local service = get_line(w[2])
        if cmd == "SHOWLINE" then
            emit("SHOWLINE %s %s first %s last %s headway %d delay %d trips %d", service.id,
                service.suspended and "suspended" or "running", time_text(service.first),
                time_text(service.last), service.headway, service.delay, trains(service))
            for i, station in ipairs(service.stops) do
                local suffix = station.closed and " closed" or ""
                if i > 1 and closed[segment(service.stops[i - 1].id, station.id)] then
                    suffix = suffix .. " blocked"
                end
                emit("%d %s zone %d%s", service.cumulative[i], station.id, station.zone, suffix)
            end
        else
            local first, last = service.stops[1], service.stops[#service.stops]
            if w[3] ~= first.id and w[3] ~= last.id then
                fail("%s is not a terminal of line %s", w[3], service.id)
            end
            if service.suspended then
                fail("line %s is suspended", service.id)
            end
            local stops, offsets = direction(service, w[3] == first.id and 1 or 0)
            local q = first_train(service, 0, time_value(w[4]))
            if not q then
                emit("TRIP %s toward %s %s none", service.id, w[3], w[4])
                return
            end
            emit("TRIP %s toward %s %s trip %d departs %s", service.id, w[3], w[4],
                q + 1, time_text(train_time(service, q, 0)))
            for i, station in ipairs(stops) do
                local suffix = station.closed and " closed" or ""
                if i > 1 and closed[segment(stops[i - 1].id, station.id)] then
                    suffix = suffix .. " blocked"
                end
                emit("%s %s%s", time_text(train_time(service, q, offsets[i])), station.id, suffix)
            end
        end
    elseif cmd == "INFO" then
        local station = get_station(w[2])
        emit("INFO %s %s zone %d transfer %d %s", station.id, station.name, station.zone,
            station.transfer, station.closed and "closed" or "open")
        local services, walks = {}, {}
        for _, id in ipairs(keys(lines)) do
            if index_of(lines[id].stops, station) then
                services[#services + 1] = id
            end
        end
        for _, id in ipairs(keys(station.walks)) do
            walks[#walks + 1] = id .. " " .. station.walks[id]
        end
        emit("LINES %s", #services > 0 and table.concat(services, " ") or "none")
        emit("WALKS %s", #walks > 0 and table.concat(walks, " ") or "none")
    elseif cmd == "STATUS" then
        local station_ids, line_ids = keys(stations), keys(lines)
        emit("STATUS stations %d lines %d walks %d", #station_ids, #line_ids, walk_count)
        for _, id in ipairs(station_ids) do
            if stations[id].closed then
                emit("CLOSED %s", id)
            end
        end
        for _, key in ipairs(keys(closed)) do
            emit("CLOSED %s", (key:gsub("%z", "-")))
        end
        for _, id in ipairs(line_ids) do
            if lines[id].suspended then
                emit("SUSPENDED %s", id)
            end
        end
        for _, id in ipairs(line_ids) do
            if lines[id].delay ~= 0 then
                emit("DELAYED %s %d", id, lines[id].delay)
            end
        end
    end
end

local count = tonumber(io.read("*l"))
for _ = 1, count do
    local words = {}
    for word in io.read("*l"):gmatch("[^ ]+") do
        words[#words + 1] = word
    end
    local ok, message = pcall(command, words)
    if not ok then
        emit("ERROR %s", message)
    end
end
io.write(table.concat(output, "\n"), "\n")
