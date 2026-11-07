local Topology = require("topology")
local Policy = require("policy")
local Decision = require("decision")
local Simulator = require("simulator")
local Report = require("report")
local Simulation = {}
Simulation.__index = Simulation

local function append(items, item)
    items[#items + 1] = item
end

local function count(items)
    local n = 0
    for _ in pairs(items) do n = n + 1 end
    return n
end

local function copy(items)
    local result = {}
    for key, value in pairs(items) do result[key] = value end
    return result
end

local function union(first, second)
    local result = copy(first)
    for key in pairs(second) do result[key] = true end
    return result
end

local function collapse(path)
    local result = {}
    for _, owner in ipairs(path) do
        if result[#result] ~= owner then append(result, owner) end
    end
    return result
end

local function valley_position(pattern)
    local position = 1
    while pattern:sub(position, position) == "U" do position = position + 1 end
    if pattern:sub(position, position) == "P" then position = position + 1 end
    while pattern:sub(position, position) == "D" do position = position + 1 end
    return position - 1
end

local function message_text(message)
    return string.format("#%d %d->%d %s %s", message.serial, message.sender, message.receiver,
        message.link.name, message.prefix)
end

function Simulation.new()
    local network, policies = Topology.new(), Policy.new()
    local defaults, stepcap, traces = Simulator.params()
    local self = setmetatable({network = network, policies = policies, defaults = defaults,
        stepcap = stepcap, traces = traces, routers = {}, sessions = {}, by_session = {},
        messages = Simulator.new(), time = 0, logs = {}, periods = {}, changed_prefixes = {},
        trace_records = {}, ongoing_traces = {}, ring_records = {}, ongoing_rings = {}}, Simulation)
    for _, owner in ipairs(network.ases) do
        local router = {owner = owner, origination = {}, rib = {}, sessions = {}, changes = 0}
        self.routers[owner], self.by_session[owner] = router, {}
        for _, link in ipairs(network.at_as[owner]) do
            local session = {owner = owner, link = link, incoming = {}, outgoing = {}, pending = {}, sent = 0, received = 0}
            append(router.sessions, session)
            append(self.sessions, session)
            self.by_session[owner][link.number] = session
        end
    end
    return self
end

function Simulation:log(format, ...)
    append(self.logs, self.time .. " " .. string.format(format, ...))
end

function Simulation:import_route(session, prefix, attribute)
    local rule = self.policies:applied("IMPORT", session.owner, session.link, prefix, attribute.path, attribute.communities)
    if rule and rule.settings.DENY then return nil, rule end
    local preference = self.defaults[session.link:role(session.owner)]
    local med, communities = attribute.med, attribute.communities
    if rule then
        preference, med = rule.settings.LOCALPREF or preference, rule.settings.MED or med
        communities = Policy.edit(communities, rule)
    end
    return {path = attribute.path, origin = attribute.origin, med = med, communities = communities,
        local_pref = preference, link = session.link}, rule
end

function Simulation:candidates(owner, prefix)
    local result = {}
    for _, session in ipairs(self.routers[owner].sessions) do
        if session.incoming[prefix] then
            local route = self:import_route(session, prefix, session.incoming[prefix])
            if route then append(result, route) end
        end
    end
    return result
end

function Simulation:advertised(session, prefix)
    local owner, link = session.owner, session.link
    local route = self.routers[owner].rib[prefix]
    if not route or (route.link and route.path[1] == link:other(owner))
        or Policy.contains(route.communities, Policy.NO_EXPORT) then return nil, nil end
    local rule = self.policies:applied("EXPORT", owner, link, prefix, route.path, route.communities)
    if rule and rule.settings.DENY then return nil, rule end
    if not (rule and rule.settings.ALLOW) and route.link then
        if route.link:role(owner) ~= "customer" and link:role(owner) ~= "customer" then return nil, rule end
    end
    local prepend, med, communities = 0, 0, route.communities
    if rule then
        prepend, med = rule.settings.PREPEND or 0, rule.settings.MED or 0
        communities = Policy.edit(communities, rule)
    end
    local path = {}
    for _ = 1, 1 + prepend do append(path, owner) end
    for _, value in ipairs(route.path) do append(path, value) end
    return {path = path, origin = route.origin, med = med, communities = communities}, rule
end

function Simulation:redecide(owner, prefix)
    local router = self.routers[owner]
    local route = router.origination[prefix]
    if not route then
        local candidates = self:candidates(owner, prefix)
        if #candidates > 0 then route = Decision.best(candidates, self.network.router_ids) end
    end
    if Decision.equal(router.rib[prefix], route) then return end
    router.rib[prefix], router.changes = route, router.changes + 1
    self:log("BEST %d %s %s", owner, prefix, Report.route(route))
    local period = self.period
    period.best_changes = period.best_changes + 1
    period.exploration[owner][prefix] = (period.exploration[owner][prefix] or 0) + 1
    append(period.best_lines, {time = self.time, owner = owner, prefix = prefix, route = route})
    self.changed_prefixes[prefix] = true
    for _, session in ipairs(router.sessions) do
        if session.link.up then
            session.pending[prefix] = true
            if not session.timer then self:process_pending(session) end
        end
    end
end

function Simulation:process_pending(session)
    local sent = 0
    for _, prefix in ipairs(Topology.sorted(session.pending)) do
        local content, rule = self:advertised(session, prefix)
        if not Decision.equal(session.outgoing[prefix], content) then
            session.outgoing[prefix] = content
            local message = self.messages:send(self.time, session.owner, session.link:other(session.owner), session.link, prefix, content)
            self:log("SEND %s %s", message_text(message), content and "ANNOUNCE " .. Report.attribute(content) or "WITHDRAW")
            sent, session.sent, self.period.updates = sent + 1, session.sent + 1, self.period.updates + 1
            if not content then self.period.withdrawals = self.period.withdrawals + 1 end
            if rule then rule.hits = rule.hits + 1 end
        end
    end
    session.pending = {}
    session.timer = sent > 0 and session.link.mrai >= 1 and self.time + session.link.mrai or nil
end

function Simulation:receive(message)
    local session = self.by_session[message.receiver][message.link.number]
    local prefix, content, result = message.prefix, message.content
    session.received, self.period.convergence_time = session.received + 1, self.time - self.period.event.time
    if not content then
        session.incoming[prefix], result = nil, "WITHDRAW"
    elseif Policy.contains(content.path, message.receiver) then
        session.incoming[prefix], result = nil, "ANNOUNCE loop"
    else
        session.incoming[prefix] = content
        local route, rule = self:import_route(session, prefix, content)
        if rule then rule.hits = rule.hits + 1 end
        if not route then result = "ANNOUNCE deny " .. rule.name
        elseif rule then result = "ANNOUNCE accept " .. rule.name
        else result = "ANNOUNCE accept" end
    end
    self:log("RECV %s %s", message_text(message), result)
    self:redecide(message.receiver, prefix)
end

function Simulation:originate(owner, prefix, origin, fields, first)
    Topology.prefix(prefix)
    self.routers[owner].origination[prefix] = Decision.originated(origin, Policy.communities(fields, first))
    self:redecide(owner, prefix)
end

function Simulation:link_down(link)
    link.up, link.down_count = false, link.down_count + 1
    for _, message in ipairs(self.messages:remove_link(link)) do
        self:log("DROP %s", message_text(message))
        self.period.drops = self.period.drops + 1
    end
    local endpoints, remembered = {link.first, link.second}, {}
    table.sort(endpoints)
    for _, owner in ipairs(endpoints) do
        local session = self.by_session[owner][link.number]
        remembered[owner] = Topology.sorted(session.incoming)
        session.incoming, session.outgoing, session.pending, session.timer = {}, {}, {}, nil
    end
    for _, owner in ipairs(endpoints) do
        for _, prefix in ipairs(remembered[owner]) do self:redecide(owner, prefix) end
    end
end

function Simulation:link_up(link)
    link.up = true
    local endpoints = {link.first, link.second}
    table.sort(endpoints)
    for _, owner in ipairs(endpoints) do
        local session = self.by_session[owner][link.number]
        session.pending = copy(self.routers[owner].rib)
        self:process_pending(session)
    end
end

function Simulation:change_policy(rule, active)
    rule.active = active
    local router = self.routers[rule.owner]
    if rule.direction == "IMPORT" then
        local prefixes = {}
        for _, session in ipairs(router.sessions) do
            for prefix in pairs(session.incoming) do prefixes[prefix] = true end
        end
        for _, prefix in ipairs(Topology.sorted(prefixes)) do self:redecide(rule.owner, prefix) end
    else
        for _, session in ipairs(router.sessions) do
            if session.link.up then
                session.pending = union(union(session.pending, router.rib), session.outgoing)
                if not session.timer then self:process_pending(session) end
            end
        end
    end
end

function Simulation:execute_event(event)
    self:log("EVENT %d %s", self.period.number, event.text)
    local fields, kind = event.fields, event.kind
    if kind == "INITIAL" then
        for _, f in ipairs(self.network.initial) do self:originate(tonumber(f[2]), f[3], f[4], f, 5) end
    elseif kind == "ANNOUNCE" then self:originate(tonumber(fields[2]), fields[3], fields[4], fields, 5)
    elseif kind == "WITHDRAW" then
        local owner, prefix = tonumber(fields[2]), fields[3]
        self.routers[owner].origination[prefix] = nil
        self:redecide(owner, prefix)
    elseif kind == "LINK_DOWN" then self:link_down(self.network.by_name[fields[3]])
    elseif kind == "LINK_UP" then self:link_up(self.network.by_name[fields[3]])
    else self:change_policy(self.policies.by_name[fields[3]], kind == "POLICY_ON") end
end

local function attribute_state(attribute)
    if not attribute then return "N" end
    return "A[" .. Report.path(attribute.path) .. ";" .. attribute.origin .. ";" .. attribute.med
        .. ";" .. Policy.communities_text(attribute.communities) .. "]"
end

local function table_state(items)
    local result = {}
    for _, prefix in ipairs(Topology.sorted(items)) do append(result, prefix .. "=" .. attribute_state(items[prefix])) end
    return table.concat(result, "|")
end

function Simulation:global_state()
    local parts = {}
    for _, session in ipairs(self.sessions) do
        append(parts, "S{" .. table_state(session.incoming) .. "}{" .. table_state(session.outgoing)
            .. "}{" .. table.concat(Topology.sorted(session.pending), ",") .. "}{"
            .. (session.timer and tostring(session.timer - self.time) or "N") .. "}")
    end
    for _, message in ipairs(self.messages:ordered()) do
        append(parts, string.format("M{%d,%d,%d,%d,%s,%s}", message.arrival - self.time,
            message.receiver, message.sender, message.link.number, message.prefix, attribute_state(message.content)))
    end
    return table.concat(parts)
end

function Simulation:detect_divergence()
    local period = self.period
    if period.divergence or period.delivery_times > self.stepcap then return end
    local state = self:global_state()
    local first = period.states[state]
    if first then
        local cycle = {}
        for _, entry in ipairs(period.best_lines) do
            if entry.time > first and entry.time <= self.time then append(cycle, entry) end
        end
        period.divergence = {first = first, repeat_time = self.time, cycle = cycle}
    else
        period.states[state] = self.time
    end
end

function Simulation:quiet()
    if self.messages:next_time() then return false end
    for _, session in ipairs(self.sessions) do if next(session.pending) then return false end end
    return true
end

function Simulation:next_moment(boundary)
    local result = self.messages:next_time() or boundary or math.maxinteger
    if boundary then result = math.min(result, boundary) end
    for _, session in ipairs(self.sessions) do if session.timer then result = math.min(result, session.timer) end end
    return result
end

function Simulation:run_period(number, event, boundary)
    local period = {number = number, event = event, before = {}, exploration = {}, best_lines = {},
        updates = 0, withdrawals = 0, drops = 0, best_changes = 0, convergence_time = 0,
        delivery_times = 0, states = {}, routes_changed = 0, max_exploration = 0}
    self.period = period
    append(self.periods, period)
    for _, owner in ipairs(self.network.ases) do
        period.before[owner], period.exploration[owner] = copy(self.routers[owner].rib), {}
    end
    self.time, self.changed_prefixes = event.time, {}
    self:execute_event(event)
    local quiet
    while true do
        local delivered = false
        while self.messages:next_time() == self.time do self:receive(self.messages:take()); delivered = true end
        for _, session in ipairs(self.sessions) do
            if session.timer == self.time then
                session.timer = nil
                if next(session.pending) then self:process_pending(session) end
            end
        end
        if next(self.changed_prefixes) then self:forwarding_checks() end
        if delivered then period.delivery_times = period.delivery_times + 1; self:detect_divergence() end
        quiet = self:quiet()
        if not boundary then
            if quiet or period.divergence or period.delivery_times >= self.stepcap then break end
        elseif self.time == boundary then break end
        self.time, self.changed_prefixes = self:next_moment(boundary), {}
    end
    period.status = period.divergence and "DIVERGENT" or quiet and "CONVERGED" or (boundary and "UNSETTLED" or "CAPPED")
    for _, owner in ipairs(self.network.ases) do
        local before, after = period.before[owner], self.routers[owner].rib
        for prefix in pairs(union(before, after)) do
            if not Decision.equal(before[prefix], after[prefix]) then period.routes_changed = period.routes_changed + 1 end
        end
        for _, n in pairs(period.exploration[owner]) do period.max_exploration = math.max(period.max_exploration, n) end
    end
    period.states = {}
end

function Simulation:run(events)
    for index, event in ipairs(events) do
        self:run_period(index - 1, event, events[index + 1] and events[index + 1].time - 1 or nil)
    end
end

function Simulation:trace(source, address)
    local visits, visited, hops, owner, hop_count = {source}, {[source] = true}, {}, source, 0
    while true do
        local prefix, length
        for name in pairs(self.routers[owner].rib) do
            local value = Topology.prefix(name)
            if Topology.contains(value, address) and (not length or value.length > length) then
                prefix, length = name, value.length
            end
        end
        if not prefix then
            return {result = #hops == 0 and "UNREACHABLE" or "BLACKHOLE", visits = visits, hops = hops, count = hop_count}
        end
        local route = self.routers[owner].rib[prefix]
        append(hops, {owner = owner, prefix = prefix, link = route.link})
        if not route.link then return {result = "DELIVERED", visits = visits, hops = hops, count = hop_count, arrival = owner} end
        hop_count, owner = hop_count + 1, route.link:other(owner)
        append(visits, owner)
        if visited[owner] then return {result = "LOOP", visits = visits, hops = hops, count = hop_count} end
        visited[owner] = true
    end
end

function Simulation:prefix_loops(prefix)
    local arrows, finished, loops = {}, {}, {}
    for _, owner in ipairs(self.network.ases) do
        local route = self.routers[owner].rib[prefix]
        if route and route.link then arrows[owner] = route.link:other(owner) end
    end
    for _, start in ipairs(self.network.ases) do
        if not finished[start] then
            local path, positions, current = {}, {}, start
            while arrows[current] and not finished[current] and not positions[current] do
                positions[current] = #path + 1
                append(path, current)
                current = arrows[current]
            end
            if positions[current] then
                local cycle, minimum = {}, math.maxinteger
                for i = positions[current], #path do append(cycle, path[i]); minimum = math.min(minimum, path[i]) end
                local first
                for i, owner in ipairs(cycle) do if owner == minimum then first = i; break end end
                local ordered = {}
                for i = 0, #cycle - 1 do append(ordered, cycle[(first + i - 1) % #cycle + 1]) end
                loops[Report.path(ordered)] = ordered
            end
            for _, owner in ipairs(path) do finished[owner] = true end
        end
    end
    return loops
end

function Simulation:forwarding_checks()
    for _, prefix in ipairs(Topology.sorted(self.changed_prefixes)) do
        local loops = self:prefix_loops(prefix)
        self.ongoing_rings[prefix] = self.ongoing_rings[prefix] or {}
        local ongoing = self.ongoing_rings[prefix]
        for key, record in pairs(ongoing) do
            if not loops[key] then record.finish, ongoing[key] = self.time, nil end
        end
        local keys = {}
        for key in pairs(loops) do append(keys, key) end
        table.sort(keys, function(a, b) return loops[a][1] < loops[b][1] end)
        for _, key in ipairs(keys) do
            if not ongoing[key] then
                local record = {prefix = prefix, path = loops[key], start = self.time}
                append(self.ring_records, record)
                ongoing[key] = record
            end
        end
    end
    for index, trace in ipairs(self.traces) do
        local path = self:trace(trace.source, trace.value)
        local bad = path.result == "LOOP" or path.result == "BLACKHOLE"
        local record = self.ongoing_traces[index]
        if record and (not bad or record.result ~= path.result or not Decision.sequence_equal(record.visits, path.visits)) then
            record.finish, self.ongoing_traces[index] = self.time, nil
        end
        if bad and not self.ongoing_traces[index] then
            record = {index = index, result = path.result, visits = path.visits, start = self.time}
            append(self.trace_records, record)
            self.ongoing_traces[index] = record
        end
    end
end

function Simulation:rib_lines()
    local lines = {}
    for _, owner in ipairs(self.network.ases) do
        local router, locals, sent, received = self.routers[owner], 0, 0, 0
        for _, route in pairs(router.rib) do if not route.link then locals = locals + 1 end end
        for _, session in ipairs(router.sessions) do sent, received = sent + session.sent, received + session.received end
        append(lines, string.format("AS %d routes %d local %d sent %d received %d changes %d", owner,
            count(router.rib), locals, sent, received, router.changes))
        for _, session in ipairs(router.sessions) do
            local accepted, link = 0, session.link
            for prefix, attribute in pairs(session.incoming) do
                if self:import_route(session, prefix, attribute) then accepted = accepted + 1 end
            end
            append(lines, string.format("SESSION %s %d %s %s in %d accepted %d out %d sent %d received %d flaps %d",
                link.name, link:other(owner), link:role(owner), link.up and "UP" or "DOWN", count(session.incoming),
                accepted, count(session.outgoing), session.sent, session.received, link.down_count))
        end
        for _, prefix in ipairs(Topology.sorted(router.rib)) do
            local route = router.rib[prefix]
            local candidates = self:candidates(owner, prefix)
            local line = string.format("%s %s candidates %d", prefix, Report.route(route), #candidates)
            if route.link then
                local _, reason = Decision.best(candidates, self.network.router_ids)
                line = line .. " reason " .. reason
            end
            append(lines, line)
            local remaining = {}
            for _, candidate in ipairs(candidates) do if not Decision.equal(candidate, route) then append(remaining, candidate) end end
            while #remaining > 0 do
                local alternate = Decision.best(remaining, self.network.router_ids)
                append(lines, "ALT " .. Report.route(alternate))
                for i, candidate in ipairs(remaining) do if candidate == alternate then table.remove(remaining, i); break end end
            end
        end
    end
    return lines
end

function Simulation:trace_lines(trace)
    local source, path = trace.source, self:trace(trace.source, trace.value)
    local lines = {string.format("TRACE %d %s %s hops %d", source, trace.address, path.result, path.count)}
    local pattern = {}
    for _, hop in ipairs(path.hops) do
        local line = string.format("HOP %d %s", hop.owner, hop.prefix)
        if hop.link then
            line = line .. string.format(" next %d link %s", hop.link:other(hop.owner), hop.link.name)
            append(pattern, hop.link:direction(hop.owner))
        else line = line .. " LOCAL" end
        append(lines, line)
    end
    if path.result == "LOOP" then append(lines, string.format("HOP %d REVISIT", path.visits[#path.visits]))
    elseif path.result == "BLACKHOLE" or path.result == "UNREACHABLE" then
        append(lines, string.format("HOP %d NOROUTE", path.visits[#path.visits]))
    end
    if #path.hops == 0 then append(lines, "CONTROL NONE")
    else
        local route, rest = self.routers[source].rib[path.hops[1].prefix], {}
        for i = 2, #path.visits do append(rest, path.visits[i]) end
        local match = path.result == "DELIVERED" and Decision.sequence_equal(collapse(route.path), rest)
        append(lines, "CONTROL " .. (route.link and Report.path(route.path) or "LOCAL") .. " " .. (match and "MATCH" or "MISMATCH"))
    end
    if path.count > 0 then
        local text = table.concat(pattern)
        append(lines, "PATTERN " .. text .. " " .. (valley_position(text) == #text and "VALLEYFREE" or "VALLEY"))
    end
    return lines
end

function Simulation:path_lines()
    local lines, originated = {}, {}
    for _, trace in ipairs(self.traces) do
        for _, line in ipairs(self:trace_lines(trace)) do append(lines, line) end
    end
    for _, owner in ipairs(self.network.ases) do
        for prefix in pairs(self.routers[owner].origination) do originated[prefix] = true end
    end
    local prefixes = Topology.sorted(originated)
    append(lines, "PREFIXES" .. (#prefixes > 0 and " " .. table.concat(prefixes, ",") or ""))
    for _, source in ipairs(self.network.ases) do
        local symbols = {}
        for _, prefix in ipairs(prefixes) do
            local path, symbol = self:trace(source, Topology.prefix(prefix).address)
            if path.result == "DELIVERED" then
                symbol = path.count == 0 and "*" or self.routers[path.arrival].origination[prefix] and "+" or "X"
            else symbol = ({LOOP = "L", BLACKHOLE = "B", UNREACHABLE = "U"})[path.result] end
            append(symbols, symbol)
        end
        append(lines, "REACH " .. source .. (#symbols > 0 and " " .. table.concat(symbols) or ""))
    end
    return lines
end

function Simulation:audit_lines()
    local lines, trace_totals = {}, {LOOP = 0, BLACKHOLE = 0}
    table.sort(self.trace_records, function(a, b)
        if a.start ~= b.start then return a.start < b.start end
        return a.index < b.index
    end)
    for _, record in ipairs(self.trace_records) do
        local trace = self.traces[record.index]
        trace_totals[record.result] = trace_totals[record.result] + 1
        local line = string.format("%s %d %s from %d to %s", record.result, trace.source, trace.address,
            record.start, record.finish and tostring(record.finish) or "END")
        if record.result == "BLACKHOLE" then line = line .. " at " .. record.visits[#record.visits] end
        append(lines, line .. " path " .. Report.path(record.visits))
    end
    table.sort(self.ring_records, function(a, b)
        if a.start ~= b.start then return a.start < b.start end
        if a.prefix ~= b.prefix then return Topology.less(a.prefix, b.prefix) end
        return a.path[1] < b.path[1]
    end)
    for _, record in ipairs(self.ring_records) do
        append(lines, string.format("RING %s from %d to %s path %s", record.prefix, record.start,
            record.finish and tostring(record.finish) or "END", Report.path(record.path)))
    end
    local routes, valleys, divergent = 0, 0, 0
    for _, owner in ipairs(self.network.ases) do
        local rib = self.routers[owner].rib
        for _, prefix in ipairs(Topology.sorted(rib)) do
            local route = rib[prefix]
            if route.link then
                routes = routes + 1
                local full, pattern = {owner}, {}
                for _, value in ipairs(route.path) do append(full, value) end
                local path = collapse(full)
                for i = 1, #path - 1 do append(pattern, self.network:connecting(path[i], path[i + 1]):direction(path[i])) end
                local text = table.concat(pattern)
                local violation = valley_position(text)
                if violation ~= #text then
                    valleys = valleys + 1
                    append(lines, string.format("VALLEY %d %s path %s pattern %s leaker %d", owner,
                        prefix, Report.path(route.path), text, path[violation + 1]))
                end
            end
        end
    end
    for _, rule in ipairs(self.policies.rules) do
        append(lines, string.format("RULE %s %s %s hits %d", rule.name, rule.direction,
            rule.active and "ON" or "OFF", rule.hits))
    end
    for _, period in ipairs(self.periods) do
        local divergence = period.divergence
        if divergence then
            divergent = divergent + 1
            append(lines, string.format("DIVERGENT event %d first %d repeat %d period %d", period.number,
                divergence.first, divergence.repeat_time, divergence.repeat_time - divergence.first))
            local oscillations = {}
            for _, entry in ipairs(divergence.cycle) do
                append(lines, string.format("CYCLE %d %d %s %s", entry.time, entry.owner, entry.prefix, Report.route(entry.route)))
                oscillations[entry.owner] = oscillations[entry.owner] or {}
                local changes = oscillations[entry.owner]
                changes[entry.prefix] = (changes[entry.prefix] or 0) + 1
            end
            for _, owner in ipairs(self.network.ases) do
                local changes = oscillations[owner]
                if changes then
                    for _, prefix in ipairs(Topology.sorted(changes)) do
                        append(lines, string.format("OSCILLATE %d %s changes %d", owner, prefix, changes[prefix]))
                    end
                end
            end
        end
    end
    append(lines, string.format("SUMMARY loops %d blackholes %d rings %d routes %d valleys %d divergent %d end %d",
        trace_totals.LOOP, trace_totals.BLACKHOLE, #self.ring_records, routes, valleys, divergent, self.time))
    return lines
end

function Simulation:write_outputs()
    local convergence = {"event,time,kind,status,convergence_time,updates,withdrawals,drops,best_changes,routes_changed,max_exploration"}
    for _, p in ipairs(self.periods) do
        append(convergence, table.concat({p.number, p.event.time, p.event.kind, p.status, p.convergence_time,
            p.updates, p.withdrawals, p.drops, p.best_changes, p.routes_changed, p.max_exploration}, ","))
    end
    Report.write({{"updates.txt", self.logs}, {"convergence.csv", convergence}, {"ribs.txt", self:rib_lines()},
        {"paths.txt", self:path_lines()}, {"audit.txt", self:audit_lines()}})
end

local simulation = Simulation.new()
simulation:run(Simulator.events())
simulation:write_outputs()
