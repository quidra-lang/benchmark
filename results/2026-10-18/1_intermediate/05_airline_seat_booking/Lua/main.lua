local CLASSES = {'F', 'J', 'Y'}
local TIERS = {PLATINUM = 0, GOLD = 1, SILVER = 2, NONE = 3}
local aircraft, flights, bookings, used_pnr, people, statuses = {}, {}, {}, {}, {}, {}
local flight_order, definition = {}, nil
local function fail(message) error(message, 0) end
local function words(text, pattern)
    local values = {}
    for value in text:gmatch(pattern or '%S+') do values[#values + 1] = value end
    return values
end
local function append(target, items)
    for _, item in ipairs(items) do target[#target + 1] = item end
end
local function copy_set(values)
    local result = {}
    for key, value in pairs(values) do result[key] = value end
    return result
end
local function tier(p) return statuses[p.name] or 'NONE' end
local function active_ids(ids)
    local result = {}
    for _, id in ipairs(ids) do
        if people[id].active then result[#result + 1] = id end
    end
    return result
end
local function members(b) return active_ids(b.people) end
local function passengers(f) return active_ids(f.people) end
local function passenger_result(p)
    if p.type == 'INFANT' then return 'LAP' end
    return p.seat == '' and 'UNASSIGNED' or p.seat
end
local function get_flight(id, open)
    local f = flights[id]
    if not f then fail('unknown flight ' .. id) end
    if open and f.closed then fail('flight ' .. id .. ' is closed') end
    return f
end
local function get_booking(pnr, open)
    local b = bookings[pnr]
    if not b or #members(b) == 0 then fail('unknown PNR ' .. pnr) end
    get_flight(b.flight, open)
    return b
end
local function get_person(b, name)
    for _, id in ipairs(members(b)) do
        if people[id].name == name then return people[id] end
    end
    fail('no passenger ' .. name .. ' in ' .. b.pnr)
end
local function cabin(f, class)
    local c = f.model.cabins[class]
    if not c then fail('no cabin ' .. class .. ' on ' .. f.id) end
    return c
end
local function booked(f, class)
    local count = 0
    for _, id in ipairs(passengers(f)) do
        local p = people[id]
        if p.type ~= 'INFANT' and p.class == class then count = count + 1 end
    end
    return count
end
local function allowed(f, p, seat, class, vacated, assignments)
    vacated, assignments = vacated or {}, assignments or {}
    local s = f.model.seats[seat]
    if not s or s.class ~= class or f.blocked[seat] then return false end
    if f.occupied[seat] and not vacated[f.occupied[seat]] then return false end
    if (p.type == 'CHILD' or p.infant ~= 0) and f.model.exits[s.row] then return false end
    if p.infant ~= 0 then
        for other_seat, id in pairs(f.occupied) do
            if id ~= p.id and not vacated[id] and people[id].infant ~= 0 then
                local t = f.model.seats[other_seat]
                if t.row == s.row and t.block == s.block then return false end
            end
        end
        for id, other_seat in pairs(assignments) do
            if id ~= p.id and people[id].infant ~= 0 then
                local t = f.model.seats[other_seat]
                if t.row == s.row and t.block == s.block then return false end
            end
        end
    end
    return true
end
local function select_seat(f, p, class)
    class = class or p.class
    local first = ''
    for _, seat in ipairs(f.model.cabins[class].seats) do
        if allowed(f, p, seat, class) then
            if first == '' then first = seat end
            if p.pref ~= '' and f.model.seats[seat].kind == p.pref then return seat end
        end
    end
    return first
end
local function move_to(f, p, seat)
    if p.seat ~= '' then f.occupied[p.seat] = nil end
    p.seat = seat
    if seat ~= '' then f.occupied[seat] = p.id end
end
local function reassign(f, output)
    for _, id in ipairs(passengers(f)) do
        local p = people[id]
        if p.type ~= 'INFANT' and p.seat == '' then
            local seat = select_seat(f, p)
            if seat ~= '' then
                move_to(f, p, seat)
                output[#output + 1] = 'REASSIGNED ' .. p.pnr .. ' ' .. p.name .. ' ' .. seat
            end
        end
    end
end
local function fits(f, ids, seats, class)
    local assignments = {}
    for index, id in ipairs(ids) do assignments[id] = seats[index] end
    for index, id in ipairs(ids) do
        if not allowed(f, people[id], seats[index], class, {}, assignments) then return false end
    end
    return true
end
local function group_seats(f, ids, class)
    local c, total = f.model.cabins[class], #ids
    for _, method in ipairs({'BLOCK', 'ROW'}) do
        for row = c.from, c.to do
            local blocks = c.blocks
            if method == 'ROW' then blocks = {table.concat(c.blocks)} end
            for _, block in ipairs(blocks) do
                for x = 1, #block - total + 1 do
                    local seats = {}
                    for j = 0, total - 1 do seats[#seats + 1] = row .. block:sub(x + j, x + j) end
                    if fits(f, ids, seats, class) then return method, seats end
                end
            end
        end
    end
    for height = 2, total do
        local width = (total + height - 1) // height
        local rows = (total + width - 1) // width
        for row = c.from, c.to - rows + 1 do
            for _, block in ipairs(c.blocks) do
                for x = 1, #block - width + 1 do
                    local seats = {}
                    for j = 0, total - 1 do
                        local position = x + j % width
                        seats[#seats + 1] = (row + j // width) .. block:sub(position, position)
                    end
                    if fits(f, ids, seats, class) then return 'STACK', seats end
                end
            end
        end
    end
    return 'SPLIT', {}
end
local function removal_targets(p)
    if p.infant == 0 then return {p.id} end
    return {p.id, p.infant}
end
local function remove_people(f, ids)
    for _, id in ipairs(ids) do
        local p = people[id]
        if p.active then
            move_to(f, p, '')
            p.active, p.volunteer = false, false
            if p.type == 'INFANT' then people[p.adult].infant = 0 end
        end
    end
end
local function load_text(seated, seats)
    local q = (seated * 1000) // seats
    return (q // 10) .. '.' .. (q % 10) .. '%'
end
local function seat_less(f, a, b)
    local x, y = f.model.seats[people[a].seat], f.model.seats[people[b].seat]
    if x.row ~= y.row then return x.row < y.row end
    return x.letter < y.letter
end
local function tuple_less(a, b)
    for index = 1, math.min(#a, #b) do
        if a[index] ~= b[index] then return a[index] < b[index] end
    end
    return #a < #b
end
local function execute(line)
    local t, output = words(line), {}
    local command = t[1]
    local function emit(text) output[#output + 1] = text end
    if command == 'AIRCRAFT' then
        definition = {id = t[2], base = tonumber(t[3]), limit = tonumber(t[4]), cabins = {}, seats = {}, exits = {}, blocked = {}}
    elseif command == 'CABIN' then
        local class, blocks = t[2], {}
        for index = 5, #t do blocks[#blocks + 1] = t[index] end
        local c = {from = tonumber(t[3]), to = tonumber(t[4]), blocks = blocks, seats = {}}
        for row = c.from, c.to do
            for b, block in ipairs(blocks) do
                for x = 1, #block do
                    local kind
                    if (b == 1 and x == 1) or (b == #blocks and x == #block) then
                        kind = 'W'
                    elseif x == 1 or x == #block then
                        kind = 'A'
                    else
                        kind = 'M'
                    end
                    local letter = block:sub(x, x)
                    local seat = row .. letter
                    definition.seats[seat] = {row = row, letter = letter, class = class, block = b, kind = kind}
                    c.seats[#c.seats + 1] = seat
                end
            end
        end
        definition.cabins[class] = c
    elseif command == 'EXIT' then
        for index = 2, #t do definition.exits[tonumber(t[index])] = true end
    elseif command == 'BLOCKED' then
        for index = 2, #t do definition.blocked[t[index]] = true end
    elseif command == 'END' then
        local parts = {'AIRCRAFT', definition.id}
        for _, class in ipairs(CLASSES) do
            local c = definition.cabins[class]
            if c then
                c.capacity = 0
                for _, seat in ipairs(c.seats) do
                    if not definition.blocked[seat] then c.capacity = c.capacity + 1 end
                end
                append(parts, {class, c.capacity})
            end
        end
        aircraft[definition.id] = definition
        emit(table.concat(parts, ' '))
        definition = nil
    elseif command == 'FLIGHT' then
        if flights[t[2]] then fail('duplicate flight ' .. t[2]) end
        local model = aircraft[t[3]]
        if not model then fail('unknown aircraft ' .. t[3]) end
        local f = {id = t[2], model = model, blocked = copy_set(model.blocked), occupied = {}, limits = {}, closed = false, bookings = {}, people = {}, volunteers = {}}
        local parts = {'FLIGHT', f.id, model.id}
        for _, class in ipairs(CLASSES) do
            local c = model.cabins[class]
            if c then
                f.limits[class] = (c.capacity * (100 + tonumber(t[4]))) // 100
                append(parts, {class, c.capacity .. '/' .. f.limits[class]})
            end
        end
        flights[f.id] = f
        flight_order[#flight_order + 1] = f.id
        emit(table.concat(parts, ' '))
    elseif command == 'STATUS' then
        statuses[t[2]] = t[3]
        emit('STATUS ' .. t[2] .. ' ' .. t[3])
    elseif command == 'BOOK' then
        local pnr, flight, class = t[2], t[3], t[4]
        if used_pnr[pnr] then fail('duplicate PNR ' .. pnr) end
        local f = get_flight(flight, true)
        cabin(f, class)
        local parsed, names = {}, {}
        for index = 5, #t do
            local parts = words(t[index], '[^:]+')
            parsed[#parsed + 1] = parts
            if names[parts[1]] then fail('duplicate name ' .. parts[1] .. ' in ' .. pnr) end
            names[parts[1]] = true
        end
        local aboard = {}
        for _, id in ipairs(passengers(f)) do aboard[people[id].name] = true end
        local adults, infants = 0, 0
        for _, parts in ipairs(parsed) do
            if aboard[parts[1]] then fail(parts[1] .. ' already on ' .. flight) end
            if parts[2] == 'ADULT' then adults = adults + 1 end
            if parts[2] == 'INFANT' then infants = infants + 1 end
        end
        if adults == 0 then fail('no adult in ' .. pnr) end
        if infants > adults then fail('too many infants in ' .. pnr) end
        if booked(f, class) + #parsed - infants > f.limits[class] then fail('limit exceeded for ' .. flight .. ' ' .. class) end
        local b = {pnr = pnr, flight = flight, people = {}, checked = false}
        local adult_ids, infant_ids, seat_ids = {}, {}, {}
        for _, parts in ipairs(parsed) do
            local id = #people + 1
            local p = {id = id, pnr = pnr, name = parts[1], type = parts[2], pref = parts[3] or '', class = class,
                seat = '', active = true, infant = 0, adult = 0, volunteer = false}
            people[id] = p
            b.people[#b.people + 1] = id
            f.people[#f.people + 1] = id
            if p.type == 'ADULT' then adult_ids[#adult_ids + 1] = id end
            if p.type == 'INFANT' then infant_ids[#infant_ids + 1] = id else seat_ids[#seat_ids + 1] = id end
        end
        for index, id in ipairs(infant_ids) do
            people[id].adult = adult_ids[index]
            people[adult_ids[index]].infant = id
        end
        bookings[pnr], used_pnr[pnr] = b, true
        f.bookings[#f.bookings + 1] = pnr
        local method, seats
        if #seat_ids == 1 then
            method = 'SINGLE'
            local p = people[seat_ids[1]]
            move_to(f, p, select_seat(f, p))
        else
            method, seats = group_seats(f, seat_ids, class)
            for index, id in ipairs(seat_ids) do
                local seat = seats[index]
                if method == 'SPLIT' then seat = select_seat(f, people[id]) end
                move_to(f, people[id], seat)
            end
        end
        local parts = {'BOOKED', pnr, flight, class, method}
        for _, id in ipairs(b.people) do parts[#parts + 1] = people[id].name .. ':' .. passenger_result(people[id]) end
        emit(table.concat(parts, ' '))
    elseif command == 'FIND' then
        local lines = {}
        for _, flight in ipairs(flight_order) do
            local f = flights[flight]
            for _, id in ipairs(passengers(f)) do
                local p = people[id]
                if p.name == t[2] then
                    lines[#lines + 1] = flight .. ' ' .. p.pnr .. ' ' .. p.class .. ' ' .. passenger_result(p) .. ' ' .. (f.closed and 'CLOSED' or 'OPEN')
                end
            end
        end
        emit('FIND ' .. t[2] .. ' ' .. (statuses[t[2]] or 'NONE') .. ' ' .. #lines)
        append(output, lines)
    elseif command == 'SEAT' or command == 'SWAP' or command == 'CANCEL' or command == 'CHECKIN' or command == 'VOLUNTEER' or command == 'INFO' then
        local b = get_booking(t[2], command ~= 'INFO')
        local f = flights[b.flight]
        if command == 'INFO' then
            emit('INFO ' .. b.pnr .. ' ' .. b.flight .. ' ' .. #members(b) .. ' ' .. (b.checked and 'CHECKED' or 'NOT-CHECKED'))
            for _, id in ipairs(members(b)) do
                local p = people[id]
                emit(p.name .. ' ' .. p.type .. ' ' .. p.class .. ' ' .. passenger_result(p))
            end
        elseif command == 'CHECKIN' then
            if b.checked then fail(b.pnr .. ' already checked in') end
            b.checked = true
            emit('CHECKIN ' .. b.pnr .. ' ' .. #members(b))
        elseif command == 'CANCEL' then
            local targets = members(b)
            if t[3] then
                local p = get_person(b, t[3])
                local target_set = {}
                for _, id in ipairs(removal_targets(p)) do target_set[id] = true end
                local remaining, adult = 0, false
                targets = {}
                for _, id in ipairs(members(b)) do
                    if target_set[id] then
                        targets[#targets + 1] = id
                    else
                        remaining = remaining + 1
                        if people[id].type == 'ADULT' then adult = true end
                    end
                end
                if remaining > 0 and not adult then fail(b.pnr .. ' would have no adult') end
            end
            local names = {}
            for _, id in ipairs(targets) do names[#names + 1] = people[id].name end
            remove_people(f, targets)
            emit('CANCELLED ' .. b.pnr .. ' ' .. table.concat(names, ' '))
            reassign(f, output)
        else
            local p = get_person(b, t[3])
            if command == 'SWAP' then
                local b2 = get_booking(t[4], true)
                local q = get_person(b2, t[5])
                if p.id == q.id then fail('cannot swap ' .. p.name .. ' with itself') end
                for _, passenger in ipairs({p, q}) do
                    if passenger.type == 'INFANT' then fail('infant ' .. passenger.name .. ' has no seat') end
                end
                if b.flight ~= b2.flight then fail(b.pnr .. ' and ' .. b2.pnr .. ' are on different flights') end
                if p.class ~= q.class then fail(p.name .. ' and ' .. q.name .. ' are in different cabins') end
                for _, passenger in ipairs({p, q}) do
                    if passenger.seat == '' then fail(passenger.name .. ' has no seat') end
                end
                local vacated = {[p.id] = true, [q.id] = true}
                local assignments = {[p.id] = q.seat, [q.id] = p.seat}
                if not allowed(f, p, q.seat, p.class, vacated, assignments) or not allowed(f, q, p.seat, q.class, vacated, assignments) then
                    fail('swap of ' .. p.name .. ' and ' .. q.name .. ' breaks seating rules')
                end
                local old_p, old_q = p.seat, q.seat
                move_to(f, p, '')
                move_to(f, q, '')
                move_to(f, p, old_q)
                move_to(f, q, old_p)
                emit('SWAPPED ' .. b.pnr .. ' ' .. p.name .. ' ' .. p.seat .. ' ' .. b2.pnr .. ' ' .. q.name .. ' ' .. q.seat)
                reassign(f, output)
            elseif command == 'VOLUNTEER' then
                if p.type ~= 'ADULT' or p.infant ~= 0 then fail(p.name .. ' cannot volunteer') end
                if p.seat == '' then fail(p.name .. ' has no seat') end
                if p.volunteer then fail(p.name .. ' already volunteered') end
                p.volunteer = true
                f.volunteers[#f.volunteers + 1] = p.id
                emit('VOLUNTEER ' .. p.pnr .. ' ' .. p.name .. ' ' .. p.seat)
            else
                local seat = t[4]
                if p.type == 'INFANT' then fail('infant ' .. p.name .. ' has no seat') end
                local s = f.model.seats[seat]
                if not s or s.class ~= p.class then fail('no seat ' .. seat .. ' in cabin ' .. p.class) end
                if f.blocked[seat] then fail('seat ' .. seat .. ' is blocked') end
                if f.occupied[seat] then fail('seat ' .. seat .. ' is occupied') end
                if (p.type == 'CHILD' or p.infant ~= 0) and f.model.exits[s.row] then fail('exit row ' .. s.row .. ' not allowed for ' .. p.name) end
                if not allowed(f, p, seat, p.class) then fail('infant limit reached at ' .. seat) end
                local old = p.seat
                move_to(f, p, seat)
                emit('MOVED ' .. p.pnr .. ' ' .. p.name .. ' ' .. old .. ' -> ' .. seat)
                reassign(f, output)
            end
        end
    else
        local mutating = command == 'UPGRADE' or command == 'CLOSE' or command == 'BLOCK' or command == 'UNBLOCK'
        local f = get_flight(t[2], mutating)
        local classes = {}
        for _, class in ipairs(CLASSES) do
            if f.model.cabins[class] then classes[#classes + 1] = class end
        end
        if command == 'UPGRADE' then
            local total = 0
            for index = 1, #classes - 1 do
                local higher, lower = classes[index], classes[index + 1]
                local targets = {}
                for _, id in ipairs(passengers(f)) do
                    local p = people[id]
                    if p.class == lower and p.type == 'ADULT' and p.infant == 0 and tier(p) ~= 'NONE' then targets[#targets + 1] = id end
                end
                table.sort(targets, function(a, b)
                    local rank_a, rank_b = TIERS[tier(people[a])], TIERS[tier(people[b])]
                    if rank_a ~= rank_b then return rank_a < rank_b end
                    return a < b
                end)
                for _, id in ipairs(targets) do
                    if booked(f, higher) >= f.limits[higher] then break end
                    local p = people[id]
                    local seat = select_seat(f, p, higher)
                    if seat == '' then break end
                    local old = passenger_result(p)
                    move_to(f, p, seat)
                    p.class = higher
                    total = total + 1
                    emit('UPGRADED ' .. p.pnr .. ' ' .. p.name .. ' ' .. lower .. ' ' .. old .. ' -> ' .. higher .. ' ' .. seat)
                end
            end
            reassign(f, output)
            emit('UPGRADE ' .. f.id .. ' ' .. total)
        elseif command == 'CLOSE' then
            for _, pnr in ipairs(f.bookings) do
                local b = bookings[pnr]
                local ids = members(b)
                if #ids > 0 and not b.checked then
                    emit('NOSHOW ' .. pnr .. ' ' .. #ids)
                    remove_people(f, ids)
                end
            end
            reassign(f, output)
            local denied, total = 0, 0
            local rates = {F = 500, J = 300, Y = 150}
            for _, class in ipairs(classes) do
                local targets = {}
                for _, id in ipairs(f.volunteers) do
                    local p = people[id]
                    if p.active and p.volunteer and p.seat ~= '' and p.class == class then targets[#targets + 1] = id end
                end
                for _, id in ipairs(targets) do
                    local p, useful = people[id], false
                    for _, waiting_id in ipairs(passengers(f)) do
                        local waiting = people[waiting_id]
                        if waiting.type ~= 'INFANT' and waiting.class == class and waiting.seat == '' and allowed(f, waiting, p.seat, class, {[id] = true}) then
                            useful = true
                            break
                        end
                    end
                    if useful then
                        local amount = rates[class]
                        emit('DENIED VOLUNTARY ' .. p.pnr .. ' ' .. p.name .. ' ' .. class .. ' ' .. amount)
                        remove_people(f, {id})
                        denied, total = denied + 1, total + amount
                        reassign(f, output)
                    end
                end
            end
            for _, id in ipairs(passengers(f)) do
                local p = people[id]
                if p.active and p.type ~= 'INFANT' and p.seat == '' then
                    local amount = rates[p.class] * 2
                    if p.type == 'CHILD' then amount = amount // 2 end
                    emit('DENIED INVOLUNTARY ' .. p.pnr .. ' ' .. p.name .. ' ' .. p.class .. ' ' .. amount)
                    remove_people(f, removal_targets(p))
                    denied, total = denied + 1, total + amount
                end
            end
            f.closed = true
            emit('CLOSED ' .. f.id .. ' denied ' .. denied .. ' compensation ' .. total)
        elseif command == 'BLOCK' or command == 'UNBLOCK' then
            local seat = t[3]
            if not f.model.seats[seat] then fail('no seat ' .. seat .. ' on ' .. f.id) end
            if command == 'BLOCK' and f.blocked[seat] then fail('seat ' .. seat .. ' is blocked') end
            if command == 'UNBLOCK' and not f.blocked[seat] then fail('seat ' .. seat .. ' is not blocked') end
            emit(command .. ' ' .. f.id .. ' ' .. seat)
            if command == 'BLOCK' then
                f.blocked[seat] = true
                if f.occupied[seat] then
                    local p = people[f.occupied[seat]]
                    move_to(f, p, '')
                    move_to(f, p, select_seat(f, p))
                    emit('DISPLACED ' .. p.pnr .. ' ' .. p.name .. ' ' .. seat .. ' -> ' .. passenger_result(p))
                end
            else
                f.blocked[seat] = nil
            end
            reassign(f, output)
        elseif command == 'MAP' then
            emit('MAP ' .. f.id)
            for _, class in ipairs(classes) do
                local c = f.model.cabins[class]
                emit('CABIN ' .. class)
                emit('   ' .. table.concat(c.blocks, ' '))
                for row = c.from, c.to do
                    local blocks = {}
                    for _, block in ipairs(c.blocks) do
                        local marks = {}
                        for x = 1, #block do
                            local seat, mark = row .. block:sub(x, x), nil
                            if f.blocked[seat] then
                                mark = '#'
                            elseif f.occupied[seat] then
                                mark = 'X'
                            else
                                mark = f.model.exits[row] and 'E' or '.'
                            end
                            marks[#marks + 1] = mark
                        end
                        blocks[#blocks + 1] = table.concat(marks)
                    end
                    emit(string.format('%2d ', row) .. table.concat(blocks, ' '))
                end
            end
        elseif command == 'MANIFEST' or command == 'BOARDING' then
            local seated, unassigned, infants = {}, {}, 0
            for _, id in ipairs(passengers(f)) do
                local p = people[id]
                if p.type == 'INFANT' then
                    infants = infants + 1
                elseif p.seat == '' then
                    unassigned[#unassigned + 1] = id
                else
                    seated[#seated + 1] = id
                end
            end
            if command == 'MANIFEST' then
                table.sort(seated, function(a, b) return seat_less(f, a, b) end)
                emit('MANIFEST ' .. f.id .. ' seated ' .. #seated .. ' unassigned ' .. #unassigned .. ' infants ' .. infants)
                local ids = {}
                append(ids, seated)
                append(ids, unassigned)
                for _, id in ipairs(ids) do
                    local p = people[id]
                    local parts = {p.seat == '' and '---' or p.seat, p.class, p.pnr, p.name, p.type}
                    if p.infant ~= 0 then parts[#parts + 1] = '+' .. people[p.infant].name end
                    if tier(p) ~= 'NONE' then parts[#parts + 1] = tier(p) end
                    if bookings[p.pnr].checked then parts[#parts + 1] = 'CHECKED' end
                    if p.volunteer then parts[#parts + 1] = 'VOL' end
                    emit(table.concat(parts, ' '))
                end
            else
                local groups, keys = {}, {}
                for _, id in ipairs(seated) do
                    local p = people[id]
                    local s = f.model.seats[p.seat]
                    local has_infant = false
                    for _, member in ipairs(members(bookings[p.pnr])) do
                        if people[member].type == 'INFANT' then has_infant = true end
                    end
                    local group, key
                    if has_infant then
                        group, key = 'PRE', {0, s.row, s.letter}
                    elseif p.class ~= 'Y' then
                        group, key = 'CABIN', {1, s.row, s.letter}
                    elseif TIERS[tier(p)] <= 1 then
                        group, key = 'TIER', {2, s.row, s.letter}
                    else
                        local zone = (s.row - f.model.cabins.Y.from) // 5 + 1
                        group = 'ZONE' .. zone
                        key = {3, -zone, ({W = 0, M = 1, A = 2})[s.kind], -s.row, s.letter}
                    end
                    groups[id], keys[id] = group, key
                end
                table.sort(seated, function(a, b) return tuple_less(keys[a], keys[b]) end)
                emit('BOARDING ' .. f.id .. ' ' .. #seated)
                for number, id in ipairs(seated) do
                    local p = people[id]
                    emit(number .. ' ' .. groups[id] .. ' ' .. p.seat .. ' ' .. p.pnr .. ' ' .. p.name)
                end
            end
        elseif command == 'LOADFACTOR' then
            emit('LOADFACTOR ' .. f.id)
            local total_seated, total_seats = 0, 0
            for _, class in ipairs(classes) do
                local seats, seated = 0, 0
                for _, seat in ipairs(f.model.cabins[class].seats) do
                    if not f.blocked[seat] then seats = seats + 1 end
                end
                for _, id in ipairs(passengers(f)) do
                    if people[id].class == class and people[id].seat ~= '' then seated = seated + 1 end
                end
                emit(class .. ' ' .. seated .. '/' .. seats .. ' ' .. load_text(seated, seats) .. ' booked ' .. booked(f, class) .. '/' .. f.limits[class])
                total_seated, total_seats = total_seated + seated, total_seats + seats
            end
            emit('ALL ' .. total_seated .. '/' .. total_seats .. ' ' .. load_text(total_seated, total_seats))
        elseif command == 'BALANCE' then
            local weight, moment = 0, 0
            for _, id in ipairs(passengers(f)) do
                local p = people[id]
                if p.seat ~= '' then
                    local w = p.type == 'ADULT' and 80 or 40
                    if p.infant ~= 0 then w = w + 10 end
                    weight = weight + w
                    moment = moment + w * (f.model.seats[p.seat].row - f.model.base)
                end
            end
            local limit, verdict = f.model.limit, nil
            if moment < -limit then
                verdict = 'NOSE-HEAVY'
            elseif moment > limit then
                verdict = 'TAIL-HEAVY'
            else
                verdict = 'OK'
            end
            emit('BALANCE ' .. f.id .. ' weight ' .. weight .. ' moment ' .. moment .. ' limit ' .. limit .. ' ' .. verdict)
        elseif command == 'AVAIL' then
            local class = t[3]
            local c = cabin(f, class)
            local counts, free = {W = 0, M = 0, A = 0, EXIT = 0}, 0
            for _, seat in ipairs(c.seats) do
                if not f.blocked[seat] and not f.occupied[seat] then
                    local s = f.model.seats[seat]
                    free = free + 1
                    counts[s.kind] = counts[s.kind] + 1
                    if f.model.exits[s.row] then counts.EXIT = counts.EXIT + 1 end
                end
            end
            emit('AVAIL ' .. f.id .. ' ' .. class .. ' free ' .. free .. ' W ' .. counts.W .. ' M ' .. counts.M .. ' A ' .. counts.A .. ' EXIT ' .. counts.EXIT)
        end
    end
    return output
end
local count = tonumber(io.read('*l'))
for _ = 1, count do
    local ok, output = pcall(execute, io.read('*l'))
    if ok then
        for _, line in ipairs(output) do io.write(line, '\n') end
    else
        io.write('ERROR ', output, '\n')
    end
end
