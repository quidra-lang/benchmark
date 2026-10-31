package.path = 'Lua/?.lua;' .. package.path
local eventlog = require('eventlog')
local dfg = require('dfg')
local alpha = require('alpha_miner')
local heuristic = require('heuristic_miner')
local conformance = require('conformance')
local report = require('report')
local F, fraction, names, percentage = report.rational, report.fraction, report.names, report.percentage
local function sorted(set)
    local out = {}; for key in pairs(set) do out[#out + 1] = key end; table.sort(out); return out
end
local function count(set) local n = 0; for _ in pairs(set) do n = n + 1 end; return n end
local function inc(map, key, amount) map[key] = (map[key] or 0) + (amount or 1) end
local function append(a, b) for _, x in ipairs(b) do a[#a + 1] = x end end
local function line(out, ...) out[#out + 1] = table.concat({...}, ' ') end
local function sum(a) local n = 0; for _, v in ipairs(a) do n = n + v end; return n end
local function mean(a) return fraction(F(sum(a), #a)) end
local function sequence_less(a, b)
    for i = 1, math.min(#a, #b) do if a[i] ~= b[i] then return a[i] < b[i] end end
    return #a < #b
end
local function value_order(map)
    local out = sorted(map)
    table.sort(out, function(a, b) return map[a] > map[b] or (map[a] == map[b] and a < b) end)
    return out
end
local function pair(key) return key:match('^([^:]+):([^:]+)$') end
local rows, raw_parameters = eventlog.read()
local p = {}
for key, value in pairs(raw_parameters) do
    local a, b = value:match('^(%d+)/(%d+)$')
    p[key] = a and F(tonumber(a), tonumber(b)) or tonumber(value)
end
local reference = conformance.read()
local errors, events, adopted = {}, {}, {}
for _, e in ipairs(rows) do
    local t = eventlog.minutes(e.timestamp)
    local identity = e.id .. ':' .. e.activity .. ':' .. e.timestamp
    if not t then line(errors, 'ERROR line ' .. e.line .. ': bad timestamp', e.timestamp)
    elseif adopted[identity] then line(errors, 'ERROR line ' .. e.line .. ': duplicate event', e.id, e.activity, e.timestamp)
    else adopted[identity] = true; e.time = t; events[#events + 1] = e end
end
local cases = eventlog.cases(events)
local activity_set, resource_set, log = {}, {}, {}
for _, e in ipairs(events) do activity_set[e.activity] = true; resource_set[e.resource] = true end
for _, c in ipairs(cases) do log[#log + 1] = {trace = c.trace, weight = 1} end
local activities, resources = sorted(activity_set), sorted(resource_set)
local counts = dfg.count(log)
local function log_summary()
    local out = {}; append(out, errors)
    local first, last = events[1], events[1]
    for _, e in ipairs(events) do if e.time < first.time then first = e end; if e.time > last.time then last = e end end
    line(out, 'LOG rows', #rows, 'adopted', #events, 'rejected', #errors, 'cases', #cases, 'activities', #activities,
        'resources', #resources, 'first', first.timestamp, 'last', last.timestamp)
    local stats = {}
    for _, a in ipairs(activities) do stats[a] = {events = 0, cases = 0, start = 0, finish = 0, rework = 0, waits = {}, resources = {}} end
    local we, ws, wf = {}, {}, {}
    for i = 0, 6 do we[i], ws[i], wf[i] = 0, 0, 0 end
    local lengths, durations, days, max_day, late = {}, {}, {}, 0, 0
    for _, c in ipairs(cases) do
        local occurrences = {}
        stats[c.trace[1]].start = stats[c.trace[1]].start + 1
        stats[c.trace[#c.trace]].finish = stats[c.trace[#c.trace]].finish + 1
        inc(ws, (c.events[1].time // 1440 + 3) % 7); inc(wf, (c.events[#c.events].time // 1440 + 3) % 7)
        for i, e in ipairs(c.events) do
            local s = stats[e.activity]
            s.events = s.events + 1; s.resources[e.resource] = true; inc(occurrences, e.activity)
            inc(we, (e.time // 1440 + 3) % 7)
            if i > 1 then s.waits[#s.waits + 1] = e.time - c.events[i - 1].time end
        end
        for a, n in pairs(occurrences) do stats[a].cases = stats[a].cases + 1; if n >= 2 then stats[a].rework = stats[a].rework + 1 end end
        lengths[#lengths + 1] = #c.events; durations[#durations + 1] = c.duration
        local d = c.duration // 1440; inc(days, d); max_day = math.max(max_day, d)
        if c.duration > p.sla_minutes then late = late + 1 end
    end
    for _, a in ipairs(activities) do
        local s = stats[a]
        line(out, 'ACTIVITY', a, 'events', s.events, 'cases', s.cases, 'start', s.start, 'end', s.finish, 'rework', s.rework,
            'wait', #s.waits > 0 and mean(s.waits) or '-', 'resources', count(s.resources), 'model', reference.inputs[a] and 'yes' or 'no')
    end
    for i, values in ipairs({lengths, durations}) do
        local low, high = values[1], values[1]
        for _, v in ipairs(values) do low = math.min(low, v); high = math.max(high, v) end
        line(out, i == 1 and 'LENGTH' or 'DURATION', 'min', low, 'max', high, 'mean', mean(values), 'median', fraction(eventlog.median(values)))
    end
    for d = 0, max_day do line(out, 'DAYS', d, 'cases', days[d] or 0, 'share', percentage(days[d] or 0, #cases)) end
    line(out, 'SLA limit', p.sla_minutes, 'late', late, 'share', percentage(late, #cases))
    for i, day in ipairs({'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'}) do line(out, 'WEEKDAY', day, 'events', we[i - 1], 'starts', ws[i - 1], 'ends', wf[i - 1]) end
    return out
end
local variants, variant_by_case, filtered, grouped = {}, {}, {}, {}
for _, c in ipairs(cases) do
    local key = table.concat(c.trace, ',')
    if not grouped[key] then grouped[key] = {trace = c.trace, cases = {}} end
    local group = grouped[key]; group.cases[#group.cases + 1] = c
end
for _, v in pairs(grouped) do variants[#variants + 1] = v end
table.sort(variants, function(a, b) return #a.cases > #b.cases or (#a.cases == #b.cases and sequence_less(a.trace, b.trace)) end)
local kept_cases, kept_events = 0, 0
for number, v in ipairs(variants) do
    v.number, v.keep = number, true
    for i = 1, #v.trace - 1 do if dfg.get(counts, v.trace[i], v.trace[i + 1]) < p.filter_min_follows then v.keep = false end end
    for _, c in ipairs(v.cases) do variant_by_case[c.id] = number end
    if v.keep then
        filtered[#filtered + 1] = {trace = v.trace, weight = #v.cases}
        kept_cases = kept_cases + #v.cases; kept_events = kept_events + #v.trace * #v.cases
    end
end
local function dfg_report()
    local starts, ends, waits, edge_cases = {}, {}, {}, {}
    for _, c in ipairs(cases) do
        inc(starts, c.trace[1]); local last = c.trace[#c.trace]
        ends[last] = ends[last] or {}; ends[last][#ends[last] + 1] = c.duration
        local present = {}
        for i = 1, #c.events - 1 do
            local a, b = c.events[i], c.events[i + 1]
            local key = dfg.key(a.activity, b.activity)
            waits[key] = waits[key] or {}; waits[key][#waits[key] + 1] = b.time - a.time; present[key] = true
        end
        for key in pairs(present) do inc(edge_cases, key) end
    end
    local out, end_counts = {}, {}
    for a, values in pairs(ends) do end_counts[a] = #values end
    for _, a in ipairs(value_order(starts)) do line(out, 'START', a, 'count', starts[a]) end
    for _, a in ipairs(value_order(end_counts)) do line(out, 'END', a, 'count', #ends[a], 'duration', mean(ends[a])) end
    for _, key in ipairs(value_order(counts)) do
        local a, b = pair(key)
        local values = waits[key]
        local low, high = values[1], values[1]
        for _, v in ipairs(values) do low = math.min(low, v); high = math.max(high, v) end
        line(out, 'EDGE', a, b, 'count', counts[key], 'cases', edge_cases[key], 'mean', mean(values), 'min', low, 'max', high)
    end
    append(out, dfg.footprint(activities, function(a, b) return dfg.relation(counts, a, b) end))
    return out
end
local function discover(source, names_list, relation)
    local candidates, seen, causal = {}, {}, 0
    local function put(candidate)
        local key = candidate[1] * 4096 + candidate[2]
        if not seen[key] then seen[key] = true; candidates[#candidates + 1] = candidate end
    end
    for i, a in ipairs(names_list) do
        for j, b in ipairs(names_list) do
            if relation(a, b) == '->' then
                causal = causal + 1
                if relation(a, a) == '#' and relation(b, b) == '#' then put({1 << (i - 1), 1 << (j - 1)}) end
            end
        end
    end
    local cursor = 1
    while cursor <= #candidates do
        local candidate = candidates[cursor]; cursor = cursor + 1
        for i = 1, #names_list do
            for side = 1, 2 do local extended = alpha.extend(candidate, i, side, names_list, relation); if extended then put(extended) end end
        end
    end
    local maximal = {}
    for _, candidate in ipairs(candidates) do
        local extendible = false
        for i = 1, #names_list do
            if alpha.extend(candidate, i, 1, names_list, relation) or alpha.extend(candidate, i, 2, names_list, relation) then extendible = true; break end
        end
        if not extendible then maximal[#maximal + 1] = candidate end
    end
    table.sort(maximal, function(a, b) return alpha.less(a, b, names_list) end)
    local start_set, end_set = {}, {}
    for _, row in ipairs(source) do start_set[row.trace[1]] = true; end_set[row.trace[#row.trace]] = true end
    local starts, ends = sorted(start_set), sorted(end_set)
    local places, arcs = {'start'}, {}
    for _, a in ipairs(starts) do arcs['start:' .. a] = true end
    for _, a in ipairs(ends) do arcs[a .. ':end'] = true end
    for i, candidate in ipairs(maximal) do
        local place = 'p' .. i; places[#places + 1] = place
        for _, a in ipairs(alpha.members(candidate[1], names_list)) do arcs[a .. ':' .. place] = true end
        for _, b in ipairs(alpha.members(candidate[2], names_list)) do arcs[place .. ':' .. b] = true end
    end
    places[#places + 1] = 'end'
    return {net = conformance.net(places, names_list, arcs, 'start', 'end'), pairs = maximal, candidates = #candidates, causal = causal,
        starts = starts, ends = ends, activities = names_list, relation = relation}
end
local function pair_line(out, discovery) line(out, 'PAIRS causal', discovery.causal, 'candidates', discovery.candidates, 'maximal', #discovery.pairs) end
local function net_lines(out, discovery)
    local net = discovery.net
    line(out, 'PLACE start -', names(discovery.starts))
    for i, candidate in ipairs(discovery.pairs) do
        line(out, 'PLACE p' .. i, names(alpha.members(candidate[1], discovery.activities)), names(alpha.members(candidate[2], discovery.activities)))
    end
    line(out, 'PLACE end', names(discovery.ends), '-')
    for _, t in ipairs(net.transitions) do
        local ins, outs = {}, {}
        for _, i in ipairs(net.inputs[t]) do ins[#ins + 1] = net.places[i] end
        for _, i in ipairs(net.outputs[t]) do outs[#outs + 1] = net.places[i] end
        line(out, 'TRANSITION', t, 'in', names(ins), 'out', names(outs))
    end
    line(out, 'NET places', #net.places, 'transitions', #net.transitions, 'arcs', count(net.arcs))
end
local function workflows()
    local fc, aset = dfg.count(filtered), {}
    for _, row in ipairs(filtered) do for _, a in ipairs(row.trace) do aset[a] = true end end
    local acts, loops, loop_set = sorted(aset), {}, {}
    for _, a in ipairs(acts) do if dfg.get(fc, a, a) >= 1 then loops[#loops + 1] = a; loop_set[a] = true end end
    local basic = function(a, b) return dfg.relation(fc, a, b) end
    local an = discover(filtered, acts, basic)
    local out = {}
    line(out, 'LOG variants', #filtered, 'cases', kept_cases, 'activities', names(acts)); line(out, 'LOOPS', names(loops)); line(out, 'MINER alpha')
    append(out, dfg.footprint(acts, basic)); pair_line(out, an); net_lines(out, an)
    local reduced, retained = {}, {}
    for _, a in ipairs(acts) do if not loop_set[a] then retained[#retained + 1] = a end end
    for _, row in ipairs(filtered) do
        local trace = {}; for _, a in ipairs(row.trace) do if not loop_set[a] then trace[#trace + 1] = a end end
        reduced[#reduced + 1] = {trace = trace, weight = row.weight}
    end
    local rc, triangles = dfg.count(reduced), alpha.triangles(reduced)
    local relation = function(a, b) return alpha.relation(rc, triangles, a, b) end
    local ap = discover(reduced, retained, relation)
    line(out, 'MINER alpha_plus')
    for _, key in ipairs(sorted(triangles)) do local a, b = pair(key); line(out, 'TRIANGLE', a, b, 'count', triangles[key]) end
    append(out, dfg.footprint(retained, relation)); pair_line(out, ap)
    for _, a in ipairs(loops) do
        local before, after = 0, 0
        for i, other in ipairs(retained) do
            if dfg.get(fc, other, a) >= 1 then before = before | (1 << (i - 1)) end
            if dfg.get(fc, a, other) >= 1 then after = after | (1 << (i - 1)) end
        end
        local place = '-'
        for i, candidate in ipairs(ap.pairs) do
            if before == candidate[1] and after == candidate[2] then
                place = 'p' .. i; ap.net.arcs[place .. ':' .. a] = true; ap.net.arcs[a .. ':' .. place] = true; break
            end
        end
        line(out, 'LOOP', a, 'before', names(alpha.members(before, retained)), 'after', names(alpha.members(after, retained)), 'place', place)
    end
    ap.net = conformance.net(ap.net.places, acts, ap.net.arcs, 'start', 'end')
    net_lines(out, ap)
    return out, {{name = 'reference', net = reference}, {name = 'alpha', net = an.net}, {name = 'alpha_plus', net = ap.net}}
end
local function heuristic_report()
    local triangles, loops1, loops2, out = alpha.triangles(log), {}, {}, {}
    for _, a in ipairs(activities) do
        local n = dfg.get(counts, a, a)
        if n > 0 then
            local m = heuristic.loop(n)
            local accepted = n >= p.positive_observations and m >= p.loop1_threshold
            if accepted then loops1[a] = true end
            line(out, 'L1', a, 'count', n, 'measure', fraction(m), accepted and 'ACCEPT' or 'REJECT')
        end
    end
    for i, a in ipairs(activities) do
        for j = i + 1, #activities do
            local b = activities[j]
            local n = dfg.get(triangles, a, b) + dfg.get(triangles, b, a)
            if not loops1[a] and not loops1[b] and n > 0 then
                local m = heuristic.loop(n)
                local accepted = n >= p.positive_observations and m >= p.loop2_threshold
                if accepted then loops2[dfg.key(a, b)] = true end
                line(out, 'L2', a, b, 'count', n, 'measure', fraction(m), accepted and 'ACCEPT' or 'REJECT')
            end
        end
    end
    local measures, best_out, best_in, edges = {}, {}, {}, {}
    for key in pairs(counts) do
        local a, b = pair(key)
        if a ~= b then
            local m = heuristic.dependency(counts, a, b); measures[key] = m
            if not best_out[a] or m > best_out[a] then best_out[a] = m end
            if not best_in[b] or m > best_in[b] then best_in[b] = m end
        end
    end
    for a in pairs(loops1) do edges[dfg.key(a, a)] = true end
    for _, key in ipairs(sorted(measures)) do
        local a, b = pair(key)
        local m, verdict = measures[key], 'ACCEPT'
        local unordered = a < b and dfg.key(a, b) or dfg.key(b, a)
        if loops2[unordered] then verdict = 'LOOP2'
        elseif counts[key] < p.positive_observations then verdict = 'REJECT_COUNT'
        elseif m < p.dependency_threshold then verdict = 'REJECT_MEASURE'
        elseif best_out[a] - m > p.relative_to_best and best_in[b] - m > p.relative_to_best then verdict = 'REJECT_BEST' end
        if verdict == 'ACCEPT' or verdict == 'LOOP2' then edges[key] = true end
        line(out, 'DEP', a, b, 'count', counts[key], 'reverse', dfg.get(counts, b, a), 'measure', fraction(m), verdict)
    end
    local inputs, outputs = {}, {}
    for _, a in ipairs(activities) do
        inputs[a], outputs[a] = {}, {}
        for _, b in ipairs(activities) do
            if edges[dfg.key(b, a)] then inputs[a][#inputs[a] + 1] = b end
            if edges[dfg.key(a, b)] then outputs[a][#outputs[a] + 1] = b end
        end
        line(out, 'NODE', a, 'in', names(inputs[a]), 'out', names(outputs[a]))
    end
    for _, a in ipairs(activities) do
        for side, neighbors in ipairs({outputs[a], inputs[a]}) do
            for i, b in ipairs(neighbors) do
                for j = i + 1, #neighbors do
                    local c = neighbors[j]
                    if b ~= a and c ~= a then
                        local m = side == 1 and heuristic.split(counts, a, b, c) or heuristic.join(counts, a, b, c)
                        line(out, side == 1 and 'SPLIT' or 'JOIN', a, b, c, 'measure', fraction(m), m >= p.and_threshold and 'AND' or 'XOR')
                    end
                end
            end
        end
    end
    line(out, 'GRAPH activities', #activities, 'edges', count(edges), 'loops1', count(loops1), 'loops2', count(loops2))
    return out
end
local function marking_key(marking) return table.concat(marking, ',') end
local function explore(net)
    local initial = marking_key(net.initial_marking)
    local final = marking_key(net.final_marking)
    local states, queue, enabled_at, reverse, ever, edges = {[initial] = net.initial_marking}, {initial}, {}, {}, {}, {}
    local unsafe, deadlocks, cursor = 0, 0, 1
    while cursor <= #queue do
        local key = queue[cursor]; cursor = cursor + 1
        local marking = states[key]
        local enabled = conformance.enabled_transitions(net, marking); enabled_at[key] = enabled
        for _, t in ipairs(enabled) do ever[t] = true end
        if #enabled == 0 and key ~= final then deadlocks = deadlocks + 1 end
        for _, t in ipairs(enabled) do
            local after = conformance.fire(net, marking, t)
            local safe = true; for _, n in ipairs(after) do if n > 1 then safe = false; break end end
            if not safe then unsafe = unsafe + 1 else
                local ak = marking_key(after)
                edges[#edges + 1] = {transition = t, after = ak}
                reverse[ak] = reverse[ak] or {}; reverse[ak][key] = true
                if not states[ak] then states[ak] = after; queue[#queue + 1] = ak end
            end
        end
    end
    local reached, pending = {}, {}
    if states[final] then reached[final] = true; pending[1] = final end
    cursor = 1
    while cursor <= #pending do
        local key = pending[cursor]; cursor = cursor + 1
        for before in pairs(reverse[key] or {}) do if not reached[before] then reached[before] = true; pending[#pending + 1] = before end end
    end
    local dead, follows = {}, {}
    for _, t in ipairs(net.transitions) do if not ever[t] then dead[#dead + 1] = t end end
    for _, edge in ipairs(edges) do for _, u in ipairs(enabled_at[edge.after]) do follows[dfg.key(edge.transition, u)] = 1 end end
    local stuck = #queue - #pending
    return {markings = #queue, edges = #edges, unsafe = unsafe, deadlocks = deadlocks, stuck = stuck,
        final = states[final] ~= nil, dead = dead, sound = unsafe == 0 and stuck == 0 and #dead == 0, follows = follows}
end
local function footprint_fitness(out, name, net, follows)
    local aset = {}; for _, a in ipairs(activities) do aset[a] = true end; for _, a in ipairs(net.transitions) do aset[a] = true end
    local acts, differences = sorted(aset), {}
    for _, a in ipairs(acts) do
        for _, b in ipairs(acts) do
            local observed, modeled = dfg.relation(counts, a, b), dfg.relation(follows, a, b)
            if observed ~= modeled then differences[#differences + 1] = {a, b, observed, modeled} end
        end
    end
    local cells = #acts * #acts
    line(out, 'FOOTPRINT', name, 'activities', #acts, 'cells', cells, 'differing', #differences, 'fitness', fraction(F(cells - #differences, cells)))
    if name == 'reference' then
        for _, d in ipairs(differences) do if d[1] <= d[2] then line(out, 'DIFF', d[1], d[2], 'log', d[3], 'model', d[4]) end end
    end
end
local prefixes = {weight = 0, followers = {}}
for _, c in ipairs(cases) do
    local node = prefixes; node.weight = node.weight + 1
    for _, a in ipairs(c.trace) do
        if not node.followers[a] then node.followers[a] = {weight = 0, followers = {}} end
        node = node.followers[a]; node.weight = node.weight + 1
    end
end
local function precision_report(out, name, net)
    local fitting, allowed, escaping, weights = 0, 0, 0, {}
    local function visit(node, marking)
        fitting = fitting + 1
        for _, t in ipairs(conformance.enabled_transitions(net, marking)) do
            allowed = allowed + node.weight
            if not node.followers[t] then escaping = escaping + node.weight; inc(weights, t, node.weight) end
        end
        for _, t in ipairs(sorted(node.followers)) do
            if net.inputs[t] and conformance.enabled(net, marking, t) then visit(node.followers[t], conformance.fire(net, marking, t)) end
        end
    end
    visit(prefixes, net.initial_marking)
    line(out, 'PRECISION', name, 'prefixes', fitting, 'allowed', allowed, 'escaping', escaping,
        'precision', fraction(allowed == 0 and F(1) or F(allowed - escaping, allowed)))
    for _, t in ipairs(value_order(weights)) do line(out, 'ESCAPE', name, t, 'weight', weights[t]) end
end
local function replay(net, c)
    local result = conformance.totals(#net.places)
    local tokens, heads = {}, {}
    for i = 1, #net.places do tokens[i] = {}; heads[i] = 1 end
    tokens[net.initial][1] = c.events[1].time; result.produced = 1
    for _, e in ipairs(c.events) do
        local t = e.activity
        if not net.inputs[t] then result.skipped = result.skipped + 1 else
            for _, i in ipairs(net.inputs[t]) do
                result.consumed = result.consumed + 1
                if heads[i] <= #tokens[i] then
                    local produced = tokens[i][heads[i]]; heads[i] = heads[i] + 1
                    result.waiting[i][#result.waiting[i] + 1] = e.time - produced; inc(result.routes[i], t)
                else result.missing = result.missing + 1; result.place_missing[i] = result.place_missing[i] + 1 end
            end
            for _, i in ipairs(net.outputs[t]) do tokens[i][#tokens[i] + 1] = e.time; result.produced = result.produced + 1 end
        end
    end
    result.consumed = result.consumed + 1
    if heads[net.final] <= #tokens[net.final] then heads[net.final] = heads[net.final] + 1 else
        result.missing = result.missing + 1; result.place_missing[net.final] = result.place_missing[net.final] + 1
    end
    for i = 1, #net.places do
        local remaining = #tokens[i] - heads[i] + 1
        result.place_remaining[i] = remaining; result.remaining = result.remaining + remaining
        result.deviating[i] = (remaining > 0 or result.place_missing[i] > 0) and 1 or 0
    end
    return result
end
local function aggregate(net)
    local total, results, fitting = conformance.totals(#net.places), {}, 0
    for _, c in ipairs(cases) do
        local r = replay(net, c); results[c.id] = r
        if r.missing == 0 and r.remaining == 0 then fitting = fitting + 1 end
        for _, key in ipairs({'missing', 'remaining', 'consumed', 'produced', 'skipped'}) do total[key] = total[key] + r[key] end
        for i = 1, #net.places do
            for _, key in ipairs({'place_missing', 'place_remaining', 'deviating'}) do total[key][i] = total[key][i] + r[key][i] end
            append(total.waiting[i], r.waiting[i]); for t, n in pairs(r.routes[i]) do inc(total.routes[i], t, n) end
        end
    end
    return total, results, fitting
end
local function replay_report(out, name, net, total, fitting)
    line(out, 'REPLAY', name, 'cases', #cases, 'fitting', fitting, 'skipped', total.skipped, 'missing', total.missing,
        'remaining', total.remaining, 'consumed', total.consumed, 'produced', total.produced, 'fitness', fraction(conformance.fitness(total)))
    for i, place in ipairs(net.places) do
        local waits, maximum = total.waiting[i], 0
        for _, v in ipairs(waits) do maximum = math.max(maximum, v) end
        line(out, 'PLACE', name, place, 'missing', total.place_missing[i], 'remaining', total.place_remaining[i], 'deviating', total.deviating[i],
            'tokens', #waits, 'mean', #waits > 0 and mean(waits) or '-', 'max', #waits > 0 and maximum or '-')
    end
    for i, place in ipairs(net.places) do
        if #net.routes[i] >= 2 then
            local consumptions = {}
            for _, t in ipairs(net.routes[i]) do consumptions[#consumptions + 1] = t .. '=' .. (total.routes[i][t] or 0) end
            line(out, 'ROUTE', name, place, table.concat(consumptions, ','))
        end
    end
end
local function conformance_report(nets)
    local out, exploration, reference_replays = {}, {}, nil
    line(out, 'MODEL places', #reference.places, 'transitions', #reference.transitions, 'arcs', count(reference.arcs))
    for _, entry in ipairs(nets) do
        local r = explore(entry.net); exploration[entry.name] = r
        line(out, 'REACHABILITY', entry.name, 'markings', r.markings, 'edges', r.edges, 'unsafe', r.unsafe, 'deadlocks', r.deadlocks,
            'stuck', r.stuck, 'final', r.final and 'yes' or 'no', 'dead', names(r.dead), 'sound', r.sound and 'yes' or 'no')
    end
    for _, entry in ipairs(nets) do footprint_fitness(out, entry.name, entry.net, exploration[entry.name].follows) end
    for _, entry in ipairs(nets) do precision_report(out, entry.name, entry.net) end
    for _, entry in ipairs(nets) do
        local total, results, fitting = aggregate(entry.net)
        if entry.name == 'reference' then reference_replays = results end
        replay_report(out, entry.name, entry.net, total, fitting)
    end
    return out, reference_replays
end
local function variant_report(results)
    local out = {}
    for _, v in ipairs(variants) do
        local durations, late = {}, 0
        for _, c in ipairs(v.cases) do durations[#durations + 1] = c.duration; if c.duration > p.sla_minutes then late = late + 1 end end
        line(out, 'VARIANT', v.number, 'count', #v.cases, 'share', percentage(#v.cases, #cases), 'length', #v.trace,
            'first', v.cases[1].id, 'duration', mean(durations), 'late', late, 'fitness', fraction(conformance.fitness(results[v.cases[1].id])),
            v.keep and 'KEEP' or 'DROP', names(v.trace))
    end
    line(out, 'FILTER min_follows', p.filter_min_follows, 'variants', #filtered, 'of', #variants, 'cases', kept_cases, 'of', #cases, 'events', kept_events, 'of', #events)
    return out
end
local function conformance_csv(results)
    local out = {'case_id,variant,events,skipped,missing,remaining,consumed,produced,fitness'}
    for _, c in ipairs(cases) do
        local r = results[c.id]
        out[#out + 1] = table.concat({c.id, variant_by_case[c.id], #c.events, r.skipped, r.missing, r.remaining, r.consumed, r.produced, fraction(conformance.fitness(r))}, ',')
    end
    return out
end
local function resource_report()
    local event_counts, case_counts, work, handovers, handover_cases, subcontract, together = {}, {}, {}, {}, {}, {}, {}
    for _, resource in ipairs(resources) do work[resource] = {} end
    for _, c in ipairs(cases) do
        local workers, present, seen = {}, {}, {}
        for _, e in ipairs(c.events) do
            workers[#workers + 1] = e.resource; present[e.resource] = true
            inc(event_counts, e.resource); inc(work[e.resource], e.activity)
        end
        local ps = sorted(present)
        for i, a in ipairs(ps) do
            inc(case_counts, a)
            for j = i + 1, #ps do inc(together, dfg.key(a, ps[j])) end
        end
        for i = 1, #workers - 1 do
            local key = dfg.key(workers[i], workers[i + 1]); inc(handovers, key); seen[key] = true
        end
        for key in pairs(seen) do inc(handover_cases, key) end
        for i = 1, #workers - 2 do
            if workers[i] == workers[i + 2] and workers[i] ~= workers[i + 1] then inc(subcontract, dfg.key(workers[i], workers[i + 1])) end
        end
    end
    local out = {}
    for i, resource in ipairs(resources) do
        local list = {}; for _, a in ipairs(sorted(work[resource])) do list[#list + 1] = a .. '=' .. work[resource][a] end
        line(out, 'RESOURCE', i, resource, 'events', event_counts[resource], 'cases', case_counts[resource], 'work', table.concat(list, ','))
    end
    for _, key in ipairs(value_order(handovers)) do
        local a, b = pair(key)
        if a ~= b then line(out, 'HANDOVER', a, b, 'count', handovers[key], 'cases', handover_cases[key]) end
    end
    local table_rows = {}
    for i, a in ipairs(resources) do table_rows[i] = {}; for j, b in ipairs(resources) do table_rows[i][j] = dfg.get(handovers, a, b) end end
    append(out, dfg.table(table_rows, 5))
    for _, key in ipairs(value_order(subcontract)) do local a, b = pair(key); line(out, 'SUBCONTRACT', a, b, 'count', subcontract[key]) end
    for _, key in ipairs(value_order(together)) do local a, b = pair(key); line(out, 'TOGETHER', a, b, 'cases', together[key]) end
    local total, own = 0, 0
    for key, n in pairs(handovers) do local a, b = pair(key); total = total + n; if a == b then own = own + n end end
    line(out, 'TOTAL handovers', total, 'self', own, 'other', total - own)
    return out
end
local workflow_lines, nets = workflows()
local conformance_lines, reference_replays = conformance_report(nets)
report.write({['log_summary.txt'] = log_summary(), ['variants.txt'] = variant_report(reference_replays), ['dfg.txt'] = dfg_report(),
    ['alpha_net.txt'] = workflow_lines, ['heuristic_net.txt'] = heuristic_report(), ['conformance.csv'] = conformance_csv(reference_replays),
    ['conformance.txt'] = conformance_lines, ['resources.txt'] = resource_report()})
