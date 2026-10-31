local network = require('network')
local clocks = require('clocks')
local processes = require('processes')
local snapshots = require('snapshot')
local analysis = require('analysis')
local function yes(value) return value and 'yes' or 'no' end
local function message_name(message) return 'm' .. message.id end
local function numeric_words(values)
    local result = {}
    for i, value in ipairs(values) do result[i] = tostring(value) end
    return table.concat(result, ' ')
end
local function load_params()
    local input = assert(io.open('input/params.txt', 'r'))
    local result = {compare = {}, cuts = {}, predicates = {}}
    for line in input:lines() do
        local t = {}
        for token in line:gmatch('%S+') do t[#t + 1] = token end
        local key = t[1]
        if key == 'COMPARE' then result.compare[#result.compare + 1] = {t[2], t[3]}
        elseif key == 'CUT' then
            local cut = {}
            for i = 2, #t do cut[#cut + 1] = tonumber(t[i]) end
            result.cuts[#result.cuts + 1] = cut
        elseif key == 'PREDICATE' then result.predicates[#result.predicates + 1] = tonumber(t[2])
        else result[key:lower()] = tonumber(t[2]) end
    end
    input:close()
    return result
end
local function item_less(first, second)
    if first.time ~= second.time then return first.time < second.time end
    if first.process ~= second.process then return first.process < second.process end
    return first.creation < second.creation
end
local Simulation = {}
Simulation.__index = Simulation
function Simulation:enqueue(now, p, arrival, payload)
    self.creation = self.creation + 1
    local item = {time = now, process = p, creation = self.creation, arrival = arrival, payload = payload}
    local index = #self.queue + 1
    while index > 1 do
        local parent = index // 2
        if not item_less(item, self.queue[parent]) then break end
        self.queue[index] = self.queue[parent]
        index = parent
    end
    self.queue[index] = item
end
function Simulation:pop()
    local result = self.queue[1]
    local last = table.remove(self.queue)
    if #self.queue > 0 then
        local index = 1
        while 2 * index <= #self.queue do
            local child = 2 * index
            if child < #self.queue and item_less(self.queue[child + 1], self.queue[child]) then child = child + 1 end
            if not item_less(self.queue[child], last) then break end
            self.queue[index] = self.queue[child]
            index = child
        end
        self.queue[index] = last
    end
    return result
end
function Simulation.new(names, channels, order, scripts, params, raw)
    local result = setmetatable({names = names, order = order, params = params, raw = raw, states = processes.initialize(scripts, #names),
        channels = network.initialize(channels, #names), generator = network.generator(params.seed), queue = {}, creation = 0,
        now = 0, messages = {}, copies = {}, events = {}, snapshots = {}, snapshot_by_name = {}, timeline = {}}, Simulation)
    processes.schedule(result.states, params['end'], function(now, p, arrival, action) result:enqueue(now, p, arrival, action) end)
    return result
end
function Simulation:dispatch(packet)
    local arrival = network.dispatch(self.channels, packet, self.now, self.generator)
    self:enqueue(arrival, packet.destination, true, packet)
end
function Simulation:event(p, kind, details, sending)
    local state = self.states[p]
    if sending then clocks.receive_event(state, p, sending) else clocks.local_event(state, p) end
    local event = {number = #self.events + 1, local_number = #state.events + 1, process = p, type = kind, details = details,
        time = self.now, lamport = state.lamport, vector = clocks.copy(state.vector), balance = state.balance}
    event.name = self.names[p] .. '.' .. event.local_number
    state.events[#state.events + 1] = event
    state.counts[kind] = (state.counts[kind] or 0) + 1
    state.minimum = math.min(state.minimum, state.balance)
    self.events[#self.events + 1] = event
    self.timeline[#self.timeline + 1] = {event = event}
    return event
end
function Simulation:send(p, action, sender)
    local state, kind = self.states[p], action.kind
    local destination = action.destination
    if destination == 0 then destination = sender end
    local amount, tag, event_type, message_kind = 0, action.value, 'SEND', 'P2P'
    if kind == 'TRANSFER' then
        amount, tag = action.value, 'transfer'
        if amount > state.balance then
            state.refused = state.refused + 1
            self:event(p, 'NOFUNDS', {destination = destination, amount = amount})
            return
        end
        state.balance, state.sent = state.balance - amount, state.sent + amount
    elseif kind == 'BROADCAST' then
        state.broadcast[p] = state.broadcast[p] + 1
        event_type, message_kind = 'BCAST', 'BCAST'
    end
    local message = {id = #self.messages + 1, kind = message_kind, source = p, tag = tag, amount = amount, copies = {},
        stamp = message_kind == 'BCAST' and clocks.copy(state.broadcast) or nil, send_time = self.now}
    self.messages[#self.messages + 1] = message
    local sending = self:event(p, event_type, {message = message, destination = destination})
    message.send_event = sending
    for target = 1, #self.names do
        if message_kind == 'BCAST' and target ~= p or message_kind == 'P2P' and target == destination then
            local copy = {message = message, kind = message_kind, tag = tag, amount = amount, send_event = sending, stamp = message.stamp,
                source = p, destination = target, fifo_wait = false, causal_wait = false, missing = {}}
            message.copies[#message.copies + 1] = copy
            self.copies[#self.copies + 1] = copy
            self:dispatch(copy)
        end
    end
end
function Simulation:action(p, action, sender)
    if action.kind == 'LOCAL' then self:event(p, 'LOCAL', {label = action.value})
    elseif action.kind == 'SNAPSHOT' then self:initiate(p, action.value)
    else self:send(p, action, sender) end
end
function Simulation:record(snapshot, p, reason)
    snapshots.record(snapshot, self.states[p], p, self.now, reason)
    self.timeline[#self.timeline + 1] = {snapshot = snapshot.name, process = p, time = self.now}
    snapshot.markers[p] = snapshot.markers[p] or {}
    for destination = 1, #self.names do
        if destination ~= p then
            snapshot.markers[p][destination] = {sent = self.now}
            self:dispatch({marker = true, snapshot = snapshot, source = p, destination = destination})
        end
    end
end
function Simulation:initiate(p, name)
    local snapshot = self.snapshot_by_name[name]
    if not snapshot then
        snapshot = snapshots.new(name, self.now, #self.names)
        self.snapshots[#self.snapshots + 1], self.snapshot_by_name[name] = snapshot, snapshot
    end
    if snapshot.records[p] then snapshot.ignored[#snapshot.ignored + 1] = {p, self.now}
    else self:record(snapshot, p, 'initiate') end
end
function Simulation:marker(p, packet)
    local snapshot = packet.snapshot
    if not snapshot.records[p] then self:record(snapshot, p, 'marker ' .. self.names[packet.source]) end
    snapshots.accept(snapshot, packet.source, p, self.now, #self.names)
end
function Simulation:deliver(p, copy)
    local state = self.states[p]
    if copy.kind == 'BCAST' then state.broadcast[copy.source] = state.broadcast[copy.source] + 1 end
    state.balance, state.received = state.balance + copy.amount, state.received + copy.amount
    copy.recv_event = self:event(p, 'RECV', {copy = copy}, copy.send_event)
    copy.delivery_time = self.now
    state.delivered[#state.delivered + 1] = copy
    for _, rule in ipairs(state.on) do if rule.tag == copy.tag then self:action(p, rule.action, copy.source) end end
end
function Simulation:can_deliver(p, copy)
    return clocks.deliverable(copy.stamp, self.states[p].broadcast, copy.source)
end
function Simulation:release(p)
    local holdback = self.states[p].holdback
    while true do
        local found
        for i, copy in ipairs(holdback) do if self:can_deliver(p, copy) then found = i; break end end
        if not found then break end
        self:deliver(p, table.remove(holdback, found))
    end
end
function Simulation:accept(p, packet)
    local state, source = self.states[p], packet.source
    state.next_sequence[source] = state.next_sequence[source] + 1
    if packet.marker then self:marker(p, packet); return end
    for _, snapshot in ipairs(self.snapshots) do
        local marker = snapshot.markers[source] and snapshot.markers[source][p]
        if snapshot.records[p] and (not marker or not marker.accepted) then
            local channel = snapshot.states[source][p]
            channel[#channel + 1] = packet
        end
    end
    if packet.kind == 'P2P' or self.raw then self:deliver(p, packet)
    elseif self:can_deliver(p, packet) then self:deliver(p, packet); self:release(p)
    else
        packet.causal_wait = true
        packet.missing = clocks.missing(packet.stamp, state.broadcast, source)
        state.holdback[#state.holdback + 1] = packet
    end
end
function Simulation:receive(p, packet)
    local state, source = self.states[p], packet.source
    if self.raw then self:accept(p, packet)
    elseif packet.sequence ~= state.next_sequence[source] then
        packet.fifo_wait = true
        state.reorder[source][packet.sequence] = packet
        local channel = self.channels[source][p]
        channel.buffered = channel.buffered + 1
    else
        self:accept(p, packet)
        local buffer = state.reorder[source]
        while buffer[state.next_sequence[source]] do
            local next_number = state.next_sequence[source]
            local following = buffer[next_number]
            buffer[next_number] = nil
            self:accept(p, following)
        end
    end
    state.max_held = math.max(state.max_held, processes.held(state))
end
function Simulation:run()
    while #self.queue > 0 and self.queue[1].time <= self.params['end'] do
        local item = self:pop()
        self.now = item.time
        if item.arrival then self:receive(item.process, item.payload) else self:action(item.process, item.payload) end
    end
    return self
end
local function initial_total(sim)
    local result = 0
    for _, state in ipairs(sim.states) do result = result + state.initial end
    return result
end
local function event_line(event, names)
    local kind, d, information = event.type, event.details, ''
    if kind == 'LOCAL' then information = d.label
    elseif kind == 'NOFUNDS' then information = 'to ' .. names[d.destination] .. ' amount ' .. d.amount .. ' balance ' .. event.balance
    elseif kind == 'SEND' or kind == 'BCAST' then
        local message = d.message
        information = message_name(message)
        if kind == 'SEND' then information = information .. ' to ' .. names[d.destination] end
        information = information .. ' tag ' .. message.tag
        if message.amount > 0 then information = information .. ' amount ' .. message.amount .. ' balance ' .. event.balance end
    else
        local copy = d.copy
        information = message_name(copy.message) .. ' from ' .. names[copy.source] .. ' tag ' .. copy.tag
        if copy.amount > 0 then information = information .. ' amount ' .. copy.amount .. ' balance ' .. event.balance end
    end
    return event.number .. ' t=' .. event.time .. ' ' .. event.name .. ' ' .. kind .. ' ' .. information .. ' L=' .. event.lamport .. ' V=' .. clocks.text(event.vector)
end
local function delivered_count(sim)
    local result = 0
    for _, copy in ipairs(sim.copies) do if copy.recv_event then result = result + 1 end end
    return result
end
local function trace_lines(sim)
    local lines = {}
    for _, event in ipairs(sim.events) do lines[#lines + 1] = event_line(event, sim.names) end
    local count = delivered_count(sim)
    lines[#lines + 1] = 'SUMMARY events ' .. #sim.events .. ' messages ' .. #sim.messages .. ' copies ' .. #sim.copies
        .. ' delivered ' .. count .. ' undelivered ' .. #sim.copies - count .. ' draws ' .. sim.generator.draws
    for p, state in ipairs(sim.states) do
        lines[#lines + 1] = 'FINAL ' .. sim.names[p] .. ' events ' .. #state.events .. ' L=' .. state.lamport .. ' V=' .. clocks.text(state.vector)
            .. ' B=' .. clocks.text(state.broadcast) .. ' balance ' .. state.balance .. ' in ' .. state.received .. ' out ' .. state.sent .. ' refused ' .. state.refused .. ' min ' .. state.minimum
    end
    for p, state in ipairs(sim.states) do
        local c = state.counts
        lines[#lines + 1] = 'COUNTS ' .. sim.names[p] .. ' local ' .. (c.LOCAL or 0) .. ' nofunds ' .. (c.NOFUNDS or 0)
            .. ' send ' .. (c.SEND or 0) .. ' bcast ' .. (c.BCAST or 0) .. ' recv ' .. (c.RECV or 0)
    end
    return lines
end
local function names_text(names, indices)
    local result = {}
    for _, index in ipairs(indices) do result[#result + 1] = names[index] end
    return table.concat(result, ',')
end
local function wait_mode(copy, names)
    if not copy.causal_wait then return copy.fifo_wait and 'fifo' or 'direct' end
    return (copy.fifo_wait and 'fifo+causal ' or 'causal ') .. names_text(names, copy.missing)
end
local function broadcast_history(state)
    local result = {}
    for _, event in ipairs(state.events) do
        if event.type == 'BCAST' then result[#result + 1] = event.details.message.id
        elseif event.type == 'RECV' and event.details.copy.kind == 'BCAST' then result[#result + 1] = event.details.copy.message.id end
    end
    return result
end
local function deliveries_lines(sim)
    local lines, histories = {}, {}
    for p, state in ipairs(sim.states) do
        lines[#lines + 1] = 'PROCESS ' .. sim.names[p]
        local modes, total_wait, max_wait = {direct = 0, fifo = 0, causal = 0, both = 0}, 0, 0
        for number, copy in ipairs(state.delivered) do
            local wait = copy.delivery_time - copy.arrival_time
            total_wait, max_wait = total_wait + wait, math.max(max_wait, wait)
            local mode = copy.fifo_wait and (copy.causal_wait and 'both' or 'fifo') or (copy.causal_wait and 'causal' or 'direct')
            modes[mode] = modes[mode] + 1
            lines[#lines + 1] = number .. ' ' .. message_name(copy.message) .. ' from ' .. sim.names[copy.source] .. ' ' .. copy.kind .. ' tag ' .. copy.tag
                .. ' sent ' .. copy.message.send_time .. ' arrived ' .. copy.arrival_time .. ' delivered ' .. copy.delivery_time .. ' wait ' .. wait .. ' ' .. wait_mode(copy, sim.names)
        end
        for _, copy in ipairs(sim.copies) do
            if copy.destination == p and copy.arrival_time <= sim.params['end'] and not copy.recv_event then
                local place = state.reorder[copy.source][copy.sequence] and 'fifo' or 'causal ' .. names_text(sim.names, copy.missing)
                lines[#lines + 1] = 'HELD ' .. message_name(copy.message) .. ' from ' .. sim.names[copy.source] .. ' ' .. copy.kind .. ' tag ' .. copy.tag
                    .. ' sent ' .. copy.message.send_time .. ' arrived ' .. copy.arrival_time .. ' ' .. place
            end
        end
        for _, copy in ipairs(sim.copies) do
            if copy.destination == p and copy.arrival_time > sim.params['end'] then
                lines[#lines + 1] = 'TRANSIT ' .. message_name(copy.message) .. ' from ' .. sim.names[copy.source] .. ' ' .. copy.kind .. ' tag ' .. copy.tag
                    .. ' sent ' .. copy.message.send_time .. ' arrival ' .. copy.arrival_time
            end
        end
        lines[#lines + 1] = 'TOTAL delivered ' .. #state.delivered .. ' direct ' .. modes.direct .. ' fifo ' .. modes.fifo .. ' causal ' .. modes.causal
            .. ' both ' .. modes.both .. ' wait ' .. total_wait .. ' max_wait ' .. max_wait .. ' max_held ' .. state.max_held
        local history, words = broadcast_history(state), {}
        histories[p] = {}
        for i, id in ipairs(history) do words[#words + 1] = 'm' .. id; histories[p][id] = i end
        lines[#lines + 1] = 'BCASTS ' .. (#words == 0 and 'none' or table.concat(words, ' '))
    end
    for _, pair in ipairs(sim.order) do
        local source, destination = table.unpack(pair)
        local c = sim.channels[source][destination]
        lines[#lines + 1] = 'CHANNEL ' .. sim.names[source] .. '->' .. sim.names[destination] .. ' ' .. c.kind .. ' ' .. network.delay_text(c)
            .. ' messages ' .. c.messages .. ' markers ' .. c.markers .. ' buffered ' .. c.buffered .. ' max_delay ' .. c.max_delay .. ' entries ' .. c.entries
    end
    local tags, tag_order = {}, {}
    for _, copy in ipairs(sim.copies) do
        local group = tags[copy.tag]
        if not group then group = {copies = 0, delivered = 0, latency = 0, maximum = 0}; tags[copy.tag] = group; tag_order[#tag_order + 1] = copy.tag end
        group.copies = group.copies + 1
        if copy.recv_event then
            local latency = copy.delivery_time - copy.message.send_time
            group.delivered, group.latency, group.maximum = group.delivered + 1, group.latency + latency, math.max(group.maximum, latency)
        end
    end
    table.sort(tag_order)
    for _, tag in ipairs(tag_order) do
        local group = tags[tag]
        lines[#lines + 1] = 'TAG ' .. tag .. ' copies ' .. group.copies .. ' delivered ' .. group.delivered .. ' latency ' .. group.latency .. ' max ' .. group.maximum
    end
    local broadcasts = {}
    for _, message in ipairs(sim.messages) do
        if message.kind == 'BCAST' then
            broadcasts[#broadcasts + 1] = message
            local complete, latest = true, 0
            for _, copy in ipairs(message.copies) do
                if not copy.recv_event then complete = false else latest = math.max(latest, copy.delivery_time) end
            end
            lines[#lines + 1] = 'STABLE ' .. message_name(message) .. ' ' .. sim.names[message.source] .. ' tag ' .. message.tag .. ' sent ' .. message.send_time .. ' stable ' .. (complete and tostring(latest) or 'none')
        end
    end
    local disagreements = 0
    for i, first in ipairs(broadcasts) do
        for j = i + 1, #broadcasts do
            local second = broadcasts[j]
            local earlier, later = {}, {}
            for p, history in ipairs(histories) do
                local a, b = history[first.id], history[second.id]
                if a and b then
                    local group = a < b and earlier or later
                    group[#group + 1] = p
                end
            end
            if #earlier > 0 and #later > 0 then
                disagreements = disagreements + 1
                lines[#lines + 1] = 'DISAGREE ' .. message_name(first) .. ' ' .. message_name(second) .. ' ' .. names_text(sim.names, earlier) .. ' ' .. names_text(sim.names, later)
            end
        end
    end
    lines[#lines + 1] = 'DISAGREEMENTS ' .. disagreements
    return lines
end
local function verdict(details, names)
    if details.consistent then return 'yes' end
    local values = {}
    for _, copy in ipairs(details.orphans) do values[#values + 1] = snapshots.label(copy, names) end
    return 'no ' .. table.concat(values, ' ')
end
local function snapshots_lines(normal, raw)
    local lines = {}
    for run, sim in ipairs({normal, raw}) do
        for _, snapshot in ipairs(sim.snapshots) do
            local cut = snapshots.cut(snapshot, #sim.names)
            local details = snapshots.details(cut, sim.states, sim.copies)
            local entries, pending = snapshots.recorded(snapshot, sim.order)
            local channels_total, balance_total = 0, 0
            for _, copy in ipairs(entries) do channels_total = channels_total + copy.amount end
            for _, record in ipairs(snapshot.records) do balance_total = balance_total + record.balance end
            local money = balance_total + channels_total
            local initial = initial_total(sim)
            if run == 2 then
                lines[#lines + 1] = 'RAW ' .. snapshot.name .. ' completed ' .. snapshot.complete .. ' cut ' .. clocks.text(cut)
                    .. ' consistent ' .. verdict(details, sim.names) .. ' money ' .. money .. ' conserved ' .. yes(money == initial)
            else
                lines[#lines + 1] = 'SNAPSHOT ' .. snapshot.name .. ' started ' .. snapshot.start .. ' completed ' .. snapshot.complete
                for p, record in ipairs(snapshot.records) do
                    local values = {}
                    for _, copy in ipairs(record.pending) do values[#values + 1] = message_name(copy.message) end
                    lines[#lines + 1] = 'RECORD ' .. sim.names[p] .. ' t=' .. record.time .. ' ' .. record.reason .. ' balance ' .. record.balance
                        .. ' L=' .. record.lamport .. ' V=' .. clocks.text(record.vector) .. ' pending ' .. (#values == 0 and 'none' or table.concat(values, ' '))
                end
                for _, pair in ipairs(sim.order) do
                    local source, destination = table.unpack(pair)
                    local values = {}
                    for _, copy in ipairs(snapshot.states[source][destination]) do
                        values[#values + 1] = message_name(copy.message) .. (copy.amount == 0 and '' or ':' .. copy.amount)
                    end
                    local marker = snapshot.markers[source][destination]
                    lines[#lines + 1] = 'CHANNEL ' .. sim.names[source] .. '->' .. sim.names[destination] .. ' marker ' .. marker.sent .. ' ' .. marker.accepted
                        .. ' state ' .. (#values == 0 and 'empty' or table.concat(values, ' '))
                end
                for _, ignored in ipairs(snapshot.ignored) do lines[#lines + 1] = 'IGNORED ' .. sim.names[ignored[1]] .. ' t=' .. ignored[2] end
                lines[#lines + 1] = 'CUT ' .. clocks.text(cut) .. ' consistent ' .. verdict(details, sim.names) .. ' vector ' .. yes(snapshots.vector_consistent(snapshot, cut))
                lines[#lines + 1] = 'TRANSIT channels ' .. #entries .. ' pending ' .. #pending .. ' cut ' .. #details.transit .. ' match ' .. yes(snapshots.match(entries, pending, details.transit))
                lines[#lines + 1] = 'MONEY balances ' .. balance_total .. ' channels ' .. channels_total .. ' total ' .. money .. ' initial ' .. initial .. ' conserved ' .. yes(money == initial)
            end
        end
    end
    return lines
end
local function range_notation(path, events, names)
    if #path == 0 then return '-' end
    local result = {}
    local first, last = events[path[1]], events[path[1]]
    local function append()
        local text = names[first.process] .. '.' .. first.local_number
        if first ~= last then text = text .. '-' .. last.local_number end
        result[#result + 1] = text
    end
    for i = 2, #path do
        local event = events[path[i]]
        if event.process == last.process and event.local_number == last.local_number + 1 then last = event
        else append(); first, last = event, event end
    end
    append()
    return table.concat(result, ' ')
end
local function longest_chain(sim)
    local current = sim.events[1]
    for _, event in ipairs(sim.events) do if event.lamport > current.lamport then current = event end end
    local reversed = {current.number}
    while current.lamport > 1 do
        local previous
        if current.type == 'RECV' then
            local sending = current.details.copy.send_event
            if sending.lamport == current.lamport - 1 then previous = sending end
        end
        if not previous then previous = sim.states[current.process].events[current.local_number - 1] end
        reversed[#reversed + 1] = previous.number
        current = previous
    end
    local result = {}
    for i = #reversed, 1, -1 do result[#result + 1] = reversed[i] end
    return result
end
local function compare_lines(sim)
    local edges = analysis.graph(sim.events, sim.copies, sim.states)
    local indexed, lines = {}, {}
    for _, event in ipairs(sim.events) do indexed[event.name] = event end
    for _, pair in ipairs(sim.params.compare) do
        local first, second = indexed[pair[1]], indexed[pair[2]]
        local relation = clocks.relation(first.vector, second.vector)
        local path = analysis.path(first.number, second.number, edges)
        local graph_relation = '->'
        if not path then path = analysis.path(second.number, first.number, edges); graph_relation = path and '<-' or '||' end
        lines[#lines + 1] = 'COMPARE ' .. first.name .. ' ' .. relation .. ' ' .. second.name .. ' L=' .. first.lamport .. ',' .. second.lamport
            .. ' graph ' .. graph_relation .. ' agree ' .. yes(relation == graph_relation)
        if path then
            local messages = 0
            for i = 2, #path do if sim.events[path[i - 1]].process ~= sim.events[path[i]].process then messages = messages + 1 end end
            lines[#lines + 1] = 'PATH length ' .. #path .. ' messages ' .. messages .. ' ' .. range_notation(path, sim.events, sim.names)
        end
        for _, event in ipairs({first, second}) do
            local future = {}
            for p, state in ipairs(sim.states) do
                future[p] = 0
                for _, candidate in ipairs(state.events) do if candidate.vector[event.process] < event.local_number then future[p] = future[p] + 1 end end
            end
            lines[#lines + 1] = 'WINDOW ' .. event.name .. ' past ' .. clocks.text(event.vector) .. ' future ' .. clocks.text(future)
        end
    end
    return lines
end
local function analysis_lines(sim, raw)
    local lines = compare_lines(sim)
    local concurrency = analysis.concurrency(sim.events, #sim.names)
    lines[#lines + 1] = 'CONCURRENCY events ' .. #sim.events .. ' pairs ' .. concurrency.pairs .. ' ordered ' .. concurrency.ordered
        .. ' concurrent ' .. concurrency.concurrent .. ' same_lamport ' .. concurrency.same_lamport .. ' inversions ' .. concurrency.inversions
    for p = 1, #sim.names do
        for q = p + 1, #sim.names do lines[#lines + 1] = 'PAIR ' .. sim.names[p] .. ' ' .. sim.names[q] .. ' ' .. concurrency.by_pair[p][q] end
    end
    local chain = longest_chain(sim)
    lines[#lines + 1] = 'CHAIN length ' .. #chain .. ' ' .. range_notation(chain, sim.events, sim.names)
    local races, violations, fifo = analysis.races(sim.states)
    for _, race in ipairs(races) do
        local p, first, second = table.unpack(race)
        lines[#lines + 1] = 'RACE ' .. sim.names[p] .. ' ' .. message_name(first.message) .. ' ' .. sim.names[first.source]
            .. ' ' .. message_name(second.message) .. ' ' .. sim.names[second.source]
    end
    lines[#lines + 1] = 'RACES ' .. #races
    for _, violation in ipairs(violations) do
        local p, first, second = table.unpack(violation)
        lines[#lines + 1] = 'VIOLATION ' .. sim.names[p] .. ' ' .. message_name(first.message) .. ' ' .. sim.names[first.source]
            .. ' overtook ' .. message_name(second.message) .. ' ' .. sim.names[second.source]
    end
    lines[#lines + 1] = 'VIOLATIONS causal ' .. #violations .. ' fifo ' .. fifo
    local _, raw_violations, raw_fifo = analysis.races(raw.states)
    lines[#lines + 1] = 'RAW events ' .. #raw.events .. ' delivered ' .. delivered_count(raw) .. ' causal ' .. #raw_violations .. ' fifo ' .. raw_fifo
    for _, cut in ipairs(sim.params.cuts) do
        local details = snapshots.details(cut, sim.states, sim.copies)
        local text = 'CUT ' .. clocks.text(cut)
        if details.consistent then text = text .. ' consistent'
        else
            local labels = {}
            for _, copy in ipairs(details.orphans) do labels[#labels + 1] = snapshots.label(copy, sim.names) end
            text = text .. ' inconsistent orphans ' .. table.concat(labels, ' ')
        end
        lines[#lines + 1] = text .. ' transit ' .. #details.transit .. ' money ' .. details.money .. ' initial ' .. initial_total(sim)
    end
    local enumeration = analysis.enumerate(sim.states, sim.params.cutcount, sim.params.predicates)
    lines[#lines + 1] = 'CUTCOUNT t=' .. sim.params.cutcount .. ' events ' .. clocks.text(enumeration.limits) .. ' product ' .. enumeration.product .. ' consistent ' .. enumeration.consistent
    lines[#lines + 1] = 'LEVELS ' .. numeric_words(enumeration.levels)
    for i, threshold in ipairs(sim.params.predicates) do
        local p = enumeration.predicates[i]
        lines[#lines + 1] = 'PREDICATE transit>=' .. threshold .. ' cuts ' .. p.cuts .. ' possibly ' .. yes(p.possibly) .. ' definitely ' .. yes(p.definitely)
    end
    return lines
end
local function write_at(line, position, text)
    for i = 1, #text do
        local index = position + i
        while #line < index do line[#line + 1] = ' ' end
        line[index] = text:sub(i, i)
    end
end
local function trimmed_line(line)
    local result = table.concat(line):gsub(' +$', '')
    return result
end
local function diagram_header(letter, names)
    local line = {}
    write_at(line, 0, '    ' .. letter .. ' ')
    for p, name in ipairs(names) do write_at(line, 8 * p - 2, name) end
    return trimmed_line(line)
end
local function diagram_entry(value, p, kind, detail, sim)
    local line, columns = {}, {}
    write_at(line, 0, string.format('%5d ', value))
    for q = 1, #sim.names do columns[q] = 8 * q - 2; write_at(line, columns[q], '|') end
    local own = columns[p]
    local symbols = {LOCAL = '*', NOFUNDS = 'x', SEND = 'S', BCAST = 'B', RECV = 'R', snapshot = '#'}
    write_at(line, own, symbols[kind])
    if kind == 'snapshot' then write_at(line, own + 1, detail)
    elseif kind == 'SEND' or kind == 'BCAST' then write_at(line, own + 1, message_name(detail.message))
    elseif kind == 'RECV' then
        local copy = detail.copy
        local other = columns[copy.source]
        local low, high = math.min(other, own), math.max(other, own)
        for position = low + 1, high - 1 do write_at(line, position, (position - 6) % 8 == 0 and '+' or '-') end
        write_at(line, other < own and high - 1 or low + 1, other < own and '>' or '<')
        write_at(line, low + 2, message_name(copy.message))
    end
    return trimmed_line(line)
end
local function diagram_lines(sim)
    local lines = {diagram_header('t', sim.names)}
    for _, entry in ipairs(sim.timeline) do
        if entry.event then
            local event = entry.event
            lines[#lines + 1] = diagram_entry(event.time, event.process, event.type, event.details, sim)
        else lines[#lines + 1] = diagram_entry(entry.time, entry.process, 'snapshot', entry.snapshot, sim) end
    end
    lines[#lines + 1] = diagram_header('L', sim.names)
    local events = {}
    for i, event in ipairs(sim.events) do events[i] = event end
    table.sort(events, function(first, second)
        if first.lamport ~= second.lamport then return first.lamport < second.lamport end
        return first.process < second.process
    end)
    for _, event in ipairs(events) do lines[#lines + 1] = diagram_entry(event.lamport, event.process, event.type, event.details, sim) end
    return lines
end
local function save(name, lines)
    local output = assert(io.open('output/' .. name, 'w'))
    output:write(table.concat(lines, '\n'), '\n')
    output:close()
end
local names, indices, channels, order = network.read()
local scripts, params = processes.read(indices), load_params()
local normal = Simulation.new(names, channels, order, scripts, params, false):run()
local raw = Simulation.new(names, channels, order, scripts, params, true):run()
save('trace.txt', trace_lines(normal))
save('deliveries.txt', deliveries_lines(normal))
save('snapshots.txt', snapshots_lines(normal, raw))
save('analysis.txt', analysis_lines(normal, raw))
save('diagram.txt', diagram_lines(normal))
