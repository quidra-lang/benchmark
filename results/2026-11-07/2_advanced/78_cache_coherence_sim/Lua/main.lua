local config_io = require('config_io')
local Cache = require('cache')
local protocol = require('protocol')
local Bus = require('bus')
local stats = require('stats')
local address = config_io.hex_address
local function append(target, source) for _, value in ipairs(source) do target[#target + 1] = value end end
local function keys(values) local result = {}; for key in pairs(values) do result[#result + 1] = key end; table.sort(result); return result end
local function split_spaces(line)
    local fields, start = {}, 1
    while true do
        local position = line:find(' ', start, true)
        if not position then fields[#fields + 1] = line:sub(start); return fields end
        fields[#fields + 1] = line:sub(start, position - 1); start = position + 1
    end
end
local function validate_trace(lines, config)
    local events, rejected, latest = {}, {}, 0
    for number, line in ipairs(lines) do
        local fields, reason = split_spaces(line), nil
        local empty = false; for _, field in ipairs(fields) do if field == '' then empty = true end end
        if (#fields ~= 3 and #fields ~= 4) or empty then reason = 'fields'
        elseif not config_io.decimal_integer(fields[1], 7) then reason = 'cycle'
        elseif not config_io.decimal_integer(fields[2]) or tonumber(fields[2]) >= config.cores then reason = 'core'
        elseif (fields[3] ~= 'R' and fields[3] ~= 'W' and fields[3] ~= 'FENCE') or (fields[3] == 'FENCE' and #fields ~= 3) or (fields[3] ~= 'FENCE' and #fields ~= 4) then reason = 'op'
        elseif fields[3] ~= 'FENCE' and (not config_io.valid_hex_address(fields[4]) or tonumber(fields[4], 16) % 4 ~= 0 or tonumber(fields[4], 16) > 0x7fffffff) then reason = 'address'
        elseif tonumber(fields[1]) < latest then reason = 'order' end
        if reason then rejected[#rejected + 1] = {number = number, reason = reason}
        else
            latest = tonumber(fields[1])
            local event = {number = #events + 1, source_line = number, cycle = latest, core = tonumber(fields[2]), operation = fields[3]}
            if event.operation ~= 'FENCE' then event.address = tonumber(fields[4], 16); event.block = event.address // config.line; event.word = (event.address % config.line) // 4 end
            events[#events + 1] = event
        end
    end
    return events, rejected
end
local function per_core_events(events, count)
    local grouped = {}; for core = 1, count do grouped[core] = {} end
    for _, event in ipairs(events) do local list = grouped[event.core + 1]; list[#list + 1] = event end
    return grouped
end
local function reuse_analysis(events, config)
    local grouped, lines = per_core_events(events, config.cores), {}
    local capacities = {config.capacity // 4, config.capacity // 2, config.capacity, 2 * config.capacity, 4 * config.capacity}
    for core = 0, config.cores - 1 do
        local accesses, last, tree, cold, distances, misses = {}, {}, {}, 0, {}, {0, 0, 0, 0, 0}
        for _, event in ipairs(grouped[core + 1]) do if event.operation ~= 'FENCE' then accesses[#accesses + 1] = event end end
        local function prefix(position) local total = 0; while position > 0 do total = total + (tree[position] or 0); position = position - (position & -position) end; return total end
        local function update(position, delta) while position <= #accesses do tree[position] = (tree[position] or 0) + delta; position = position + (position & -position) end end
        for index, event in ipairs(accesses) do
            if last[event.block] then
                event.distance = cold - prefix(last[event.block]) + 1; distances[#distances + 1] = event.distance; update(last[event.block], -1)
            else cold = cold + 1; event.distance = nil end
            for column, capacity in ipairs(capacities) do if event.distance == nil or event.distance > capacity then misses[column] = misses[column] + 1 end end
            last[event.block] = index; update(index, 1)
        end
        local following, next_position = {}, {}
        for index = #accesses, 1, -1 do local block = accesses[index].block; following[index] = next_position[block] or #accesses + 1; next_position[block] = index end
        local resident, upcoming, resident_count, optimal = {}, {}, 0, 0
        for index, event in ipairs(accesses) do
            local block = event.block; upcoming[block] = following[index]
            if not resident[block] then
                optimal = optimal + 1
                if resident_count == config.capacity then
                    local victim
                    for line in pairs(resident) do
                        if victim == nil or upcoming[line] > upcoming[victim] or upcoming[line] == upcoming[victim] and line < victim then victim = line end
                    end
                    resident[victim] = nil; resident_count = resident_count - 1
                end
                resident[block], resident_count = true, resident_count + 1
            end
        end
        lines[#lines + 1] = 'reuse c' .. core .. ' accesses ' .. #accesses .. ' lines ' .. cold .. ' distance '
            .. stats.range_counts(distances, {'1', '2-4', '5-16', '17-64', '65-256', '257+'}, {1, 4, 16, 64, 256}) .. ' cold ' .. cold
        local curve = {}; for index, capacity in ipairs(capacities) do curve[#curve + 1] = capacity .. ':' .. misses[index] end
        lines[#lines + 1] = 'mrc c' .. core .. ' lru ' .. table.concat(curve, ' ') .. ' opt ' .. config.capacity .. ':' .. optimal
    end
    return lines
end
local function static_sharing(events)
    local lines = {}
    for _, event in ipairs(events) do
        if event.operation ~= 'FENCE' then
            local info = lines[event.block]
            if not info then info = {cores = {}, writers = {}, reads = 0, writes = 0, words = {}}; lines[event.block] = info end
            info.cores[event.core] = true
            local word = info.words[event.word]
            if not word then word = {readers = {}, writers = {}}; info.words[event.word] = word end
            if event.operation == 'W' then info.writers[event.core], word.writers[event.core], info.writes = true, true, info.writes + 1
            else word.readers[event.core], info.reads = true, info.reads + 1 end
        end
    end
    for _, info in pairs(lines) do
        info.shared, info.true_sharing = #keys(info.cores) >= 2 and next(info.writers) ~= nil, false
        for _, word in pairs(info.words) do
            local union = {}; for core in pairs(word.readers) do union[core] = true end; for core in pairs(word.writers) do union[core] = true end
            if next(word.writers) ~= nil and #keys(union) >= 2 then info.true_sharing = true end
        end
    end
    return lines
end

local Simulation = {}
Simulation.__index = Simulation
function Simulation.new(config, scenario, events)
    local self = setmetatable({config = config, scenario = scenario, primary = scenario.name == config.primary, l1 = {},
        l2 = Cache.new(config.l2_sets, config.l2_ways, scenario.l2), bus = Bus.new(config.tb), cores = {},
        event_lists = per_core_events(events, config.cores), indices = {}, ready = {}, write_completion = {}, seen = {}, invalidations = {},
        l2_counts = stats.counter(), accesses = {}, watch_lines = {}, handoffs = stats.counter(), last_writer = {}, word_state = {}, communications = {},
        true_misses = stats.counter(), false_misses = stats.counter()}, Simulation)
    for core = 1, config.cores do
        self.l1[core], self.cores[core] = Cache.new(config.l1_sets, config.l1_ways, scenario.l1), stats.empty()
        self.indices[core], self.ready[core], self.write_completion[core], self.seen[core], self.invalidations[core], self.communications[core] = 1, 0, 0, {}, {}, {}
        for target = 1, config.cores do self.communications[core][target] = 0 end
    end
    return self
end
function Simulation:line_states(block)
    local states = {}; for _, cache in ipairs(self.l1) do states[#states + 1] = cache:state(block) end
    states[#states + 1] = self.l2:state(block); return states
end
function Simulation:issue_transaction(core, kind, block, requested)
    local tx = self.bus:assign(core, kind, block, requested)
    local counts = self.cores[core + 1].bus; counts[kind] = counts[kind] + 1
    if kind == 'WB' then self.l2_counts.writebacks = self.l2_counts.writebacks + 1 end
    return tx
end
function Simulation:snoop_others(tx, word)
    for index, cache in ipairs(self.l1) do
        local core = index - 1
        if core ~= tx.core then
            local old = cache:state(tx.block)
            if old ~= 'I' then
                local updated, supplies, flushed = protocol.snoop(self.scenario.protocol, old, tx.kind)
                tx.snoops[#tx.snoops + 1], tx.snoop_hits = 'c' .. core .. ':' .. old .. '>' .. updated, tx.snoop_hits + 1
                if updated == 'I' then
                    cache:remove(tx.block); tx.invalidations = tx.invalidations + 1
                    local sent, received = self.cores[tx.core + 1].snoop, self.cores[index].snoop
                    sent.invalidations_sent, received.invalidations_received = sent.invalidations_sent + 1, received.invalidations_received + 1
                    self.invalidations[index][tx.block] = {[word] = true}
                else cache:change(tx.block, updated) end
                if supplies then tx.supplier = core; local counts = self.cores[index].snoop; counts.supplied = counts.supplied + 1 end
                if flushed then tx.flush = true end
            end
        end
    end
    if tx.flush then self.l2_counts.flushes = self.l2_counts.flushes + 1 end
end
function Simulation:access_l2(tx)
    local counts = self.l2_counts; counts.lookups = counts.lookups + 1
    if self.l2:state(tx.block) ~= 'I' then tx.l2, counts.hits = 'hit', counts.hits + 1; self.l2:touch(tx.block)
    else
        tx.l2, counts.misses = 'miss', counts.misses + 1
        local old = self.l2:fill(tx.block, 'C')
        if old then
            local copies, dirty = {}, old.state == 'D'
            for index, cache in ipairs(self.l1) do
                local state = cache:state(old.block)
                if state ~= 'I' then
                    cache:remove(old.block); copies[#copies + 1] = 'c' .. (index - 1) .. ':' .. state
                    self.cores[index].snoop.back_invalidations = self.cores[index].snoop.back_invalidations + 1
                    if protocol.dirty[state] then dirty = true end
                end
            end
            tx.eviction = {block = old.block, copies = copies, dirty = dirty}; counts.evictions = counts.evictions + 1
            if dirty then counts.dirty_evictions = counts.dirty_evictions + 1 end
        end
    end
    if tx.flush or tx.kind == 'BusWr' then self.l2:change(tx.block, 'D') end
end
function Simulation:transaction(core, kind, block, word, requested)
    local tx = self:issue_transaction(core, kind, block, requested)
    self:snoop_others(tx, word)
    if kind ~= 'BusUpgr' then self:access_l2(tx) end
    local completion = tx.start + self.config.tb
    if kind == 'BusUpgr' then return completion, tx end
    if kind ~= 'BusWr' and tx.supplier ~= nil then tx.source = 'c' .. tx.supplier
    else
        completion = completion + self.config.t2
        if tx.l2 == 'miss' then completion = completion + self.config.tm end
        if kind ~= 'BusWr' then tx.source = tx.l2 == 'hit' and 'L2' or 'mem' end
    end
    return completion, tx
end
function Simulation:communicate(event)
    local block, word, core = event.block, event.word, event.core
    self.word_state[block] = self.word_state[block] or {}
    local previous = self.word_state[block][word]
    if event.operation == 'W' then
        if self.last_writer[block] ~= nil and self.last_writer[block] ~= core then self.handoffs[block] = self.handoffs[block] + 1 end
        self.last_writer[block], self.word_state[block][word] = core, {writer = core, readers = {}}
    elseif previous and previous.writer ~= core and not previous.readers[core] then
        local vector = self.communications[previous.writer + 1]; vector[core + 1] = vector[core + 1] + 1; previous.readers[core] = true
    end
end
function Simulation:access(event, issue)
    local config, core, block, word = self.config, event.core, event.block, event.word
    local counter, cache = self.cores[core + 1], self.l1[core + 1]
    local before = {}; if self.primary then for _, watched in ipairs(config.watch) do before[watched] = self:line_states(watched) end end
    local old, miss = cache:state(block), nil
    local hit = old ~= 'I'
    local simple = counter.simple
    simple.accesses = simple.accesses + 1
    local operation_key, hit_key = event.operation == 'R' and 'reads' or 'writes', hit and 'hits' or 'misses'
    simple[operation_key], simple[hit_key] = simple[operation_key] + 1, simple[hit_key] + 1
    local other_has_line = false
    for index, other in ipairs(self.l1) do if index ~= core + 1 and other:state(block) ~= 'I' then other_has_line = true end end
    local kind, new = protocol.requester(self.scenario.protocol, old, event.operation, other_has_line)
    if hit then cache:touch(block)
    else
        if not self.seen[core + 1][block] then miss = 'compulsory'
        elseif self.invalidations[core + 1][block] then
            miss = 'coherence'
            local sharing = self.invalidations[core + 1][block][word] and 'true_sharing' or 'false_sharing'
            counter.misses[sharing] = counter.misses[sharing] + 1
            local values = sharing == 'true_sharing' and self.true_misses or self.false_misses; values[block] = values[block] + 1
        else miss = event.distance > config.capacity and 'capacity' or 'conflict' end
        counter.misses[miss] = counter.misses[miss] + 1
    end
    self.seen[core + 1][block] = true
    if event.operation == 'W' then for index = 1, config.cores do if index ~= core + 1 and self.invalidations[index][block] then self.invalidations[index][block][word] = true end end end
    if self.primary then self:communicate(event) end
    local completion, service
    if kind then
        local tx; completion, tx = self:transaction(core, kind, block, word, issue + config.t1)
        service = kind == 'BusUpgr' and 'upgrade' or kind == 'BusWr' and 'through' or tx.supplier ~= nil and 'cache' or tx.l2 == 'hit' and 'l2' or 'memory'
    else completion, service = issue + config.t1, 'l1' end
    if old ~= 'I' then cache:change(block, new)
    elseif new ~= 'I' then
        local evicted = cache:fill(block, new); self.invalidations[core + 1][block] = nil
        if evicted and protocol.dirty[evicted.state] then
            self:issue_transaction(core, 'WB', evicted.block, self.bus.free); self.l2:touch(evicted.block); self.l2:change(evicted.block, 'D')
        end
    end
    local latency = completion - issue
    counter.service[service], simple.latency = counter.service[service] + 1, simple.latency + latency
    if event.operation == 'R' then simple.read_latency, self.ready[core + 1] = simple.read_latency + latency, completion
    else simple.write_latency, self.ready[core + 1] = simple.write_latency + latency, issue + config.t1; self.write_completion[core + 1] = math.max(self.write_completion[core + 1], completion) end
    counter.finish = math.max(counter.finish, completion)
    self.accesses[#self.accesses + 1] = {event = event, issue = issue, latency = latency, service = service, miss = miss, hit = hit}
    if self.primary then
        for _, watched in ipairs(config.watch) do
            local after, changed = self:line_states(watched), watched == block
            for index, state in ipairs(after) do if state ~= before[watched][index] then changed = true end end
            if changed then
                local columns = {}; for index = 1, config.cores do columns[#columns + 1] = 'c' .. (index - 1) .. ':' .. after[index] end
                self.watch_lines[#self.watch_lines + 1] = event.number .. ' ' .. issue .. ' c' .. core .. ' ' .. event.operation .. ' ' .. address(event.address)
                    .. ' line ' .. address(watched * config.line) .. ' ' .. table.concat(columns, ' ') .. ' L2:' .. after[#after]
            end
        end
    end
end
function Simulation:run()
    while true do
        local chosen, issue, event
        for index, list in ipairs(self.event_lists) do
            local candidate = list[self.indices[index]]
            if candidate then
                local time = math.max(candidate.cycle, self.ready[index])
                if issue == nil or time < issue then chosen, issue, event = index, time, candidate end
            end
        end
        if not chosen then break end
        self.indices[chosen] = self.indices[chosen] + 1
        if event.operation == 'FENCE' then
            local counter = self.cores[chosen]; local completion = math.max(issue, self.write_completion[chosen])
            counter.simple.fences, counter.simple.fence_stall = counter.simple.fences + 1, counter.simple.fence_stall + completion - issue
            counter.finish, self.ready[chosen] = math.max(counter.finish, completion), completion
        else self:access(event, issue) end
    end
    self.total = stats.total(self.cores); self.finish = self.total.finish
end

local function scenario_report(state)
    local config, scenario, total, bus, l2 = state.config, state.scenario, state.total, state.bus, state.l2_counts
    local lines = {'scenario ' .. scenario.name .. ' ' .. scenario.protocol .. ' ' .. scenario.l1 .. ' ' .. scenario.l2}
    for index, counters in ipairs(state.cores) do append(lines, stats.six_lines('c' .. (index - 1), counters)) end
    append(lines, stats.six_lines('total', total))
    local l2_parts = {}; for _, key in ipairs({'lookups', 'hits', 'misses', 'flushes', 'writebacks', 'evictions', 'dirty_evictions'}) do l2_parts[#l2_parts + 1] = key .. ' ' .. l2[key] end
    lines[#lines + 1] = 'l2 ' .. table.concat(l2_parts, ' ')
    local count, busy = #bus.transactions, config.tb * #bus.transactions
    lines[#lines + 1] = 'bus transactions ' .. count .. ' busy ' .. busy .. ' wait ' .. bus.wait .. ' utilization ' .. stats.decimal(100 * busy, state.finish)
    local kinds = total.bus
    local data_bytes = config.line * (kinds.BusRd + kinds.BusRdX + kinds.WB) + 4 * kinds.BusWr
    lines[#lines + 1] = 'traffic command_bytes ' .. (8 * count) .. ' data_bytes ' .. data_bytes .. ' memory_bytes ' .. (config.line * (l2.misses + l2.dirty_evictions))
    local snoops, hits, fanout = 0, 0, stats.counter()
    for _, tx in ipairs(bus.transactions) do
        if tx.kind ~= 'WB' then
            snoops, hits = snoops + 1, hits + tx.snoop_hits
            if tx.kind == 'BusRdX' or tx.kind == 'BusUpgr' or tx.kind == 'BusWr' then fanout[tx.invalidations] = fanout[tx.invalidations] + 1 end
        end
    end
    local fanout_parts = {}; for amount = 0, config.cores - 1 do fanout_parts[#fanout_parts + 1] = amount .. ':' .. fanout[amount] end
    lines[#lines + 1] = 'snoops probes ' .. ((config.cores - 1) * snoops) .. ' hits ' .. hits .. ' fanout ' .. table.concat(fanout_parts, ' ')
    local latencies = {}; for _, access in ipairs(state.accesses) do latencies[#latencies + 1] = access.latency end
    lines[#lines + 1] = 'latencies reads ' .. total.simple.read_latency .. ' writes ' .. total.simple.write_latency .. ' histogram '
        .. stats.range_counts(latencies, {'1', '2-9', '10-29', '30-99', '100-299', '300+'}, {1, 9, 29, 99, 299})
    return lines
end
local function rank_scenarios(states)
    local ordered = {}; append(ordered, states)
    table.sort(ordered, function(a, b)
        if a.finish ~= b.finish then return a.finish < b.finish end
        if #a.bus.transactions ~= #b.bus.transactions then return #a.bus.transactions < #b.bus.transactions end
        return a.scenario.order < b.scenario.order
    end)
    local lines = {'ranking'}
    for rank, state in ipairs(ordered) do
        local total = state.total.simple
        lines[#lines + 1] = rank .. ' ' .. state.scenario.name .. ' finish ' .. state.finish .. ' transactions ' .. #state.bus.transactions
            .. ' amat ' .. stats.fraction(total.latency, total.accesses) .. ' ' .. stats.decimal(total.latency, total.accesses)
    end
    return lines
end
local function hot_lines(state)
    local counts, cores = {}, {}
    for _, tx in ipairs(state.bus.transactions) do
        counts[tx.block], cores[tx.block] = counts[tx.block] or stats.counter(), cores[tx.block] or {}
        local counter = counts[tx.block]
        counter[tx.kind], counter.transactions, counter.invalidations = counter[tx.kind] + 1, counter.transactions + 1, counter.invalidations + tx.invalidations
        cores[tx.block][tx.core] = true
    end
    for _, access in ipairs(state.accesses) do
        if access.miss then
            local block = access.event.block; counts[block] = counts[block] or stats.counter()
            counts[block].misses = counts[block].misses + 1
            if access.miss == 'coherence' then counts[block].coherence = counts[block].coherence + 1 end
        end
    end
    local ordered = {}; for block, counter in pairs(counts) do if counter.transactions > 0 then ordered[#ordered + 1] = block end end
    table.sort(ordered, function(a, b) if counts[a].transactions ~= counts[b].transactions then return counts[a].transactions > counts[b].transactions end; return a < b end)
    local lines = {'hot ' .. state.scenario.name}
    for rank = 1, math.min(#ordered, state.config.top) do
        local block = ordered[rank]; local counter, parts = counts[block], {}
        for _, kind in ipairs(stats.transactions) do parts[#parts + 1] = kind .. ' ' .. counter[kind] end
        lines[#lines + 1] = rank .. ' ' .. address(block * state.config.line) .. ' transactions ' .. counter.transactions .. ' ' .. table.concat(parts, ' ')
            .. ' misses ' .. counter.misses .. ' coherence ' .. counter.coherence .. ' invalidations ' .. counter.invalidations .. ' cores ' .. stats.core_string(cores[block])
    end
    return lines
end
local function interval_rows(state)
    local config, width = state.config, state.config.interval
    local count, accesses, misses, transactions, busy = state.finish // width + 1, {}, {}, {}, {}
    for index = 1, count do
        accesses[index], misses[index], transactions[index], busy[index] = {}, 0, 0, 0
        for core = 1, config.cores do accesses[index][core] = 0 end
    end
    for _, access in ipairs(state.accesses) do
        local bucket = access.issue // width + 1
        accesses[bucket][access.event.core + 1] = accesses[bucket][access.event.core + 1] + 1
        if access.miss then misses[bucket] = misses[bucket] + 1 end
    end
    for _, tx in ipairs(state.bus.transactions) do
        local first, last = tx.start, tx.start + config.tb
        if first // width < count then transactions[first // width + 1] = transactions[first // width + 1] + 1 end
        for bucket = first // width, (last - 1) // width do
            if bucket < count then busy[bucket + 1] = busy[bucket + 1] + math.max(0, math.min(last, (bucket + 1) * width) - math.max(first, bucket * width)) end
        end
    end
    local lines = {'intervals ' .. state.scenario.name .. ' ' .. width}
    for index = 1, count do
        local bucket = index - 1
        lines[#lines + 1] = bucket .. ' ' .. (bucket * width) .. '-' .. ((bucket + 1) * width - 1) .. ' accesses ' .. table.concat(accesses[index], ' ')
            .. ' misses ' .. misses[index] .. ' transactions ' .. transactions[index] .. ' busy ' .. busy[index] .. ' utilization ' .. stats.decimal(100 * busy[index], width)
    end
    return lines
end
local function slowest_rows(state)
    local ordered, lines = {}, {'slowest ' .. state.scenario.name}; append(ordered, state.accesses)
    table.sort(ordered, function(a, b) if a.latency ~= b.latency then return a.latency > b.latency end; return a.event.number < b.event.number end)
    for rank = 1, math.min(#ordered, state.config.top) do
        local item = ordered[rank]; local event = item.event
        lines[#lines + 1] = rank .. ' event ' .. event.number .. ' cycle ' .. item.issue .. ' c' .. event.core .. ' ' .. event.operation .. ' ' .. address(event.address)
            .. ' latency ' .. item.latency .. ' service ' .. item.service
    end
    return lines
end
local function region_rows(state)
    local config, counters, names = state.config, {}, {}
    for _, region in ipairs(config.regions) do names[#names + 1] = region.name; counters[region.name] = stats.counter() end
    names[#names + 1], counters.other = 'other', stats.counter()
    local function region_for(value)
        for _, region in ipairs(config.regions) do if region.first <= value and value <= region.last then return region.name end end
        return 'other'
    end
    for _, access in ipairs(state.accesses) do
        local counter = counters[region_for(access.event.address)]
        local operation = access.event.operation == 'R' and 'reads' or 'writes'
        counter.accesses, counter[operation], counter.latency = counter.accesses + 1, counter[operation] + 1, counter.latency + access.latency
        local kind = access.hit and 'hits' or access.miss; counter[kind] = counter[kind] + 1
    end
    for _, tx in ipairs(state.bus.transactions) do local counter = counters[region_for(tx.block * config.line)]; counter.transactions = counter.transactions + 1 end
    local lines = {'regions ' .. state.scenario.name}
    for _, name in ipairs(names) do
        local counter, parts, amat = counters[name], {}, '-'
        if counter.accesses > 0 then amat = stats.fraction(counter.latency, counter.accesses) .. ' ' .. stats.decimal(counter.latency, counter.accesses) end
        for _, kind in ipairs(stats.misses) do parts[#parts + 1] = kind .. ' ' .. counter[kind] end
        lines[#lines + 1] = name .. ' accesses ' .. counter.accesses .. ' reads ' .. counter.reads .. ' writes ' .. counter.writes .. ' hits ' .. counter.hits .. ' '
            .. table.concat(parts, ' ') .. ' transactions ' .. counter.transactions .. ' latency ' .. counter.latency .. ' amat ' .. amat
    end
    return lines
end
local function sharing_output(sharing, state)
    local shared, lines, true_lines, total_true, total_false = {}, {}, 0, 0, 0
    for _, block in ipairs(keys(sharing)) do if sharing[block].shared then shared[#shared + 1] = block end end
    for _, block in ipairs(shared) do
        local info, t, f = sharing[block], state.true_misses[block], state.false_misses[block]
        if info.true_sharing then true_lines = true_lines + 1 end
        total_true, total_false = total_true + t, total_false + f
        local words = {}
        for _, word in ipairs(keys(info.words)) do local item = info.words[word]; words[#words + 1] = 'w' .. word .. '=' .. stats.core_string(item.readers) .. '/' .. stats.core_string(item.writers) end
        lines[#lines + 1] = address(block * state.config.line) .. ' ' .. (info.true_sharing and 'true' or 'false') .. ' cores ' .. stats.core_string(info.cores)
            .. ' writers ' .. stats.core_string(info.writers) .. ' reads ' .. info.reads .. ' writes ' .. info.writes .. ' handoffs ' .. state.handoffs[block]
            .. ' coherence ' .. (t + f) .. ' true ' .. t .. ' false ' .. f .. ' words ' .. table.concat(words, ' ')
    end
    lines[#lines + 1] = 'lines ' .. #shared .. ' true_lines ' .. true_lines .. ' false_lines ' .. (#shared - true_lines) .. ' coherence ' .. (total_true + total_false) .. ' true ' .. total_true .. ' false ' .. total_false
    lines[#lines + 1] = 'communication'
    for core, vector in ipairs(state.communications) do lines[#lines + 1] = 'c' .. (core - 1) .. ' ' .. table.concat(vector, ' ') end
    return lines
end
local function final_state_output(state)
    local config, lines = state.config, {}
    local function append_sets(cache, label)
        for row = 1, cache.sets do
            local ways = {}
            for way = 1, cache.ways do local item = cache.entries[row][way]; ways[#ways + 1] = item and address(item.block * config.line) .. ':' .. item.state or '-' end
            lines[#lines + 1] = label .. ' ' .. (row - 1) .. ' ' .. table.concat(ways, ' ') .. ' ' .. cache.replacement:lower() .. ' ' .. cache:order(row)
                .. ' fills ' .. cache.fills[row] .. ' evictions ' .. cache.evictions[row]
        end
    end
    local in_l1 = {}
    for core, cache in ipairs(state.l1) do
        append_sets(cache, 'c' .. (core - 1))
        local counts, resident, parts = stats.counter(), cache:lines(), {}
        for _, item in ipairs(resident) do counts[item.state] = counts[item.state] + 1; in_l1[item.block] = true end
        for _, name in ipairs({'M', 'O', 'E', 'S', 'V'}) do parts[#parts + 1] = name .. ' ' .. counts[name] end
        lines[#lines + 1] = 'c' .. (core - 1) .. ' lines ' .. #resident .. ' ' .. table.concat(parts, ' ')
    end
    local l2, counts, resident = state.l2, stats.counter(), state.l2:lines()
    append_sets(l2, 'L2')
    for _, item in ipairs(resident) do counts[item.state] = counts[item.state] + 1 end
    lines[#lines + 1] = 'L2 lines ' .. #resident .. ' dirty ' .. counts.D .. ' clean ' .. counts.C .. ' in_l1 ' .. #keys(in_l1)
    return lines
end

local config, trace = config_io.read_config(), config_io.read_trace()
local events, rejected = validate_trace(trace, config)
local reuse, sharing = reuse_analysis(events, config), static_sharing(events)
local states, primary = {}, nil
for _, scenario in ipairs(config.scenarios) do
    local state = Simulation.new(config, scenario, events); state:run(); states[#states + 1] = state
    if state.primary then primary = state end
end
local configuration = {'trace lines ' .. #trace .. ' accepted ' .. #events .. ' rejected ' .. #rejected}
for _, item in ipairs(rejected) do configuration[#configuration + 1] = 'reject line ' .. item.number .. ' ' .. item.reason end
configuration[#configuration + 1] = 'geometry cores ' .. config.cores .. ' line ' .. config.line .. ' l1 ' .. config.l1_size .. ' ' .. config.l1_ways .. ' sets ' .. config.l1_sets
    .. ' l2 ' .. config.l2_size .. ' ' .. config.l2_ways .. ' sets ' .. config.l2_sets
configuration[#configuration + 1] = 'latency l1 ' .. config.t1 .. ' l2 ' .. config.t2 .. ' memory ' .. config.tm .. ' bus ' .. config.tb
local sections = {configuration, reuse}
for _, state in ipairs(states) do sections[#sections + 1] = scenario_report(state) end
append(sections, {rank_scenarios(states), hot_lines(primary), interval_rows(primary), slowest_rows(primary), region_rows(primary)})
local statistics, bus_log = {}, {}
for index, section in ipairs(sections) do if index > 1 then statistics[#statistics + 1] = '' end; append(statistics, section) end
for _, tx in ipairs(primary.bus.transactions) do bus_log[#bus_log + 1] = primary.bus:line(tx, config.line) end
config_io.write_lines('stats.txt', statistics)
config_io.write_lines('bus_log.txt', bus_log)
config_io.write_lines('watch.txt', primary.watch_lines)
config_io.write_lines('sharing.txt', sharing_output(sharing, primary))
config_io.write_lines('final_state.txt', final_state_output(primary))
