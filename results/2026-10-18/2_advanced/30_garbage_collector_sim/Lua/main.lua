local heap, mutator, marking, copying, generational = require("heap"), require("mutator"), require("mark_sweep"), require("copying"), require("generational")
local pair_text, pct = heap.pair_text, heap.pct
local function append(destination, source)
    for _, value in ipairs(source) do
        destination[#destination + 1] = value
    end
end
local function words(objects)
    local total = 0
    for _, object in ipairs(objects) do
        total = total + object.size
    end
    return total
end
local function pair_of(objects)
    local pair = heap.pair()
    for _, object in ipairs(objects) do
        heap.add(pair, object)
    end
    return pair
end
local function sorted_keys(values)
    local keys = {}
    for key in pairs(values) do
        keys[#keys + 1] = key
    end
    table.sort(keys)
    return keys
end
local function contains(values, target)
    for _, value in ipairs(values) do
        if value == target then
            return true
        end
    end
    return false
end
local function reachable(roots, objects)
    local reached, stack = {}, {}
    for _, root in ipairs(roots) do
        if root ~= 0 then
            stack[#stack + 1] = root
        end
    end
    while #stack > 0 do
        local number = table.remove(stack)
        if not reached[number] then
            reached[number] = true
            for _, child in ipairs(objects[number].fields) do
                if child ~= 0 then
                    stack[#stack + 1] = child
                end
            end
        end
    end
    return reached
end
local function fragmentation(blocks)
    local total = heap.total_free(blocks)
    return pct(total - heap.largest_free(blocks), total)
end
local Script = {}
Script.__index = Script
function Script.new()
    local counts = {}
    for _, name in ipairs(mutator.names) do
        counts[name] = 0
    end
    return setmetatable({commands = {}, errors = {}, counts = counts, roots = {}, objects = {}, births = {}, deaths = {}, lifetimes = {}, clock = 0, alive = {}, live = heap.pair(), peak = heap.pair(), checkpoints = {}, labels = {}, phase_start = 1}, Script)
end
function Script:value(source)
    return source < 0 and 0 or self.roots[source + 1]
end
function Script:check(command)
    local name, depth = command.name, #self.roots
    if (name == "ALLOC" or name == "PUSH" or name == "LOAD") and depth == 64 then
        return "stack"
    end
    if (name == "LOAD" or name == "SET" or name == "OVERWRITE") and command.slot >= depth then
        return "stack"
    end
    if (name == "PUSH" or name == "SET" or name == "OVERWRITE") and command.source >= depth then
        return "stack"
    end
    if name == "POP" and command.count > depth then
        return "stack"
    end
    if name == "LOAD" or name == "SET" then
        local target = self.roots[command.slot + 1]
        if target == 0 then
            return "null"
        end
        if command.field >= #self.objects[target].fields then
            return "field"
        end
    end
    if name == "CHECKPOINT" and self.labels[command.label] then
        return "duplicate"
    end
end
function Script:execute(command)
    local name = command.name
    if name == "ALLOC" then
        local object = heap.object(#self.objects + 1, command.pointers, command.data)
        self.objects[#self.objects + 1], self.births[#self.births + 1] = object, self.clock
        self.clock = self.clock + object.size
        self.roots[#self.roots + 1] = object.number
    elseif name == "PUSH" then
        self.roots[#self.roots + 1] = self:value(command.source)
    elseif name == "LOAD" then
        self.roots[#self.roots + 1] = self.objects[self.roots[command.slot + 1]].fields[command.field + 1]
    elseif name == "POP" then
        for _ = 1, command.count do
            self.roots[#self.roots] = nil
        end
    elseif name == "SET" then
        self.objects[self.roots[command.slot + 1]].fields[command.field + 1] = self:value(command.source)
    elseif name == "OVERWRITE" then
        self.roots[command.slot + 1] = self:value(command.source)
    end
end
function Script:analyze(lines)
    self.line_count = #lines
    for line, text in ipairs(lines) do
        local command, reason = mutator.parse_line(line, text)
        if not reason then
            reason = self:check(command)
        end
        if reason then
            self.errors[#self.errors + 1] = {line = line, reason = reason}
        else
            self.commands[#self.commands + 1], self.counts[command.name] = command, self.counts[command.name] + 1
            self:execute(command)
            local reached = reachable(self.roots, self.objects)
            for number in pairs(self.alive) do
                if not reached[number] then
                    self.deaths[number], self.lifetimes[number] = line, self.clock - self.births[number] - self.objects[number].size
                end
            end
            self.alive, self.live = reached, heap.pair()
            for number in pairs(reached) do
                heap.add(self.live, self.objects[number])
            end
            if not self.peak_line or self.live.words > self.peak.words then
                self.peak, self.peak_line = {count = self.live.count, words = self.live.words}, line
            end
            if command.name == "CHECKPOINT" then
                self.labels[command.label] = true
                local phase, survivors = heap.pair(), heap.pair()
                for i = self.phase_start, #self.objects do
                    local object = self.objects[i]
                    heap.add(phase, object)
                    if reached[i] then
                        heap.add(survivors, object)
                    end
                end
                self.phase_start = #self.objects + 1
                self.checkpoints[#self.checkpoints + 1] = {label = command.label, line = line, stack = #self.roots, live = {count = self.live.count, words = self.live.words}, allocated = pair_of(self.objects), phase = phase, survivors = survivors, reachable = reached}
            end
        end
    end
end
function Script:report()
    local lines = {string.format("script lines %d valid %d errors %d", self.line_count, #self.commands, #self.errors)}
    for _, error in ipairs(self.errors) do
        lines[#lines + 1] = "error line " .. error.line .. " " .. error.reason
    end
    local counts = {}
    for _, name in ipairs(mutator.names) do
        counts[#counts + 1] = name .. " " .. self.counts[name]
    end
    lines[#lines + 1] = "commands " .. table.concat(counts, " ")
    local sizes, lifetimes = {}, {0, 0, 0, 0, 0, 0}
    for i, object in ipairs(self.objects) do
        sizes[i] = object.size
        local life = self.lifetimes[i]
        local index = not life and 6 or life <= 63 and 1 or life <= 255 and 2 or life <= 1023 and 3 or life <= 4095 and 4 or 5
        lifetimes[index] = lifetimes[index] + 1
    end
    lines[#lines + 1] = "allocated objects " .. #sizes .. " words " .. words(self.objects) .. " sizes " .. heap.class_table(sizes)
    lines[#lines + 1] = "peak_live objects " .. self.peak.count .. " words " .. self.peak.words .. " line " .. self.peak_line
    lines[#lines + 1] = "end_live objects " .. self.live.count .. " words " .. self.live.words .. " stack " .. #self.roots
    lines[#lines + 1] = string.format("lifetimes 0-63 %d 64-255 %d 256-1023 %d 1024-4095 %d 4096+ %d live %d", table.unpack(lifetimes))
    for _, checkpoint in ipairs(self.checkpoints) do
        lines[#lines + 1] = "checkpoint " .. checkpoint.label .. " line " .. checkpoint.line .. " stack " .. checkpoint.stack .. " live " .. pair_text(checkpoint.live) .. " allocated " .. pair_text(checkpoint.allocated) .. " phase " .. pair_text(checkpoint.phase) .. " survivors " .. pair_text(checkpoint.survivors) .. " survival " .. pct(checkpoint.survivors.words, checkpoint.phase.words)
    end
    return lines
end
local function leak_report(title, garbage, deaths, objects)
    local members, neighbors, grouped, groups = {}, {}, {}, {}
    for _, object in ipairs(garbage) do
        members[object.number], neighbors[object.number] = true, {}
    end
    for _, object in ipairs(garbage) do
        for _, child in ipairs(object.fields) do
            if members[child] then
                neighbors[object.number][#neighbors[object.number] + 1] = child
                neighbors[child][#neighbors[child] + 1] = object.number
            end
        end
    end
    for _, number in ipairs(sorted_keys(members)) do
        if not grouped[number] then
            grouped[number] = true
            local stack, group = {number}, {}
            while #stack > 0 do
                local current = table.remove(stack)
                group[#group + 1] = current
                for _, other in ipairs(neighbors[current]) do
                    if not grouped[other] then
                        grouped[other], stack[#stack + 1] = true, other
                    end
                end
            end
            table.sort(group)
            groups[#groups + 1] = group
        end
    end
    local lines = {title .. " groups " .. #groups .. " objects " .. #garbage .. " words " .. words(garbage)}
    for position, group in ipairs(groups) do
        local ids, cycles, died, total = {}, 0, 0, 0
        for _, number in ipairs(group) do
            local visited, stack, cyclic = {}, {}, false
            for _, child in ipairs(objects[number].fields) do
                if members[child] then
                    stack[#stack + 1] = child
                end
            end
            while #stack > 0 do
                local current = table.remove(stack)
                if current == number then
                    cyclic = true
                    break
                end
                if not visited[current] then
                    visited[current] = true
                    for _, child in ipairs(objects[current].fields) do
                        if members[child] then
                            stack[#stack + 1] = child
                        end
                    end
                end
            end
            ids[#ids + 1] = number .. (cyclic and "*" or "")
            if cyclic then
                cycles = cycles + 1
            end
            died, total = math.max(died, deaths[number]), total + objects[number].size
        end
        lines[#lines + 1] = string.format("group %d objects %d words %d cycle %d died %d ids %s", position, #group, total, cycles, died, table.concat(ids, " "))
    end
    return lines
end
local function pause_stats(pauses)
    local works, total, freed, collections = {}, 0, 0, 0
    for i, pause in ipairs(pauses) do
        works[i], total, freed = pause.work, total + pause.work, freed + pause.freed
        if pause.collection then
            collections = collections + 1
        end
    end
    table.sort(works)
    return {count = #works, collections = collections, work = total, freed = freed, maximum = works[#works] or 0, p50 = #works == 0 and "-" or tostring(works[(50 * #works + 99) // 100]), p90 = #works == 0 and "-" or tostring(works[(90 * #works + 99) // 100])}
end
local Timeline = {}
Timeline.__index = Timeline
function Timeline.new()
    return setmetatable({segments = {}, length = 0, mutator = 0}, Timeline)
end
function Timeline:add(flag, units)
    if units == 0 then
        return
    end
    local last = self.segments[#self.segments]
    if last and last.mutator == flag then
        last.length = last.length + units
    else
        self.segments[#self.segments + 1] = {start = self.length, length = units, mutator = flag, before = self.mutator}
    end
    self.length = self.length + units
    if flag then
        self.mutator = self.mutator + units
    end
end
function Timeline:until_position(position)
    local low, high = 1, #self.segments
    while low < high do
        local middle = (low + high + 1) // 2
        if self.segments[middle].start <= position then
            low = middle
        else
            high = middle - 1
        end
    end
    local segment = self.segments[low]
    return segment.before + (segment.mutator and position - segment.start or 0)
end
function Timeline:mmu(width)
    if width > self.length then
        return "-"
    end
    local lowest = width
    for _, segment in ipairs(self.segments) do
        for _, begin in ipairs({segment.start, segment.start + segment.length - width}) do
            if begin >= 0 and begin <= self.length - width then
                lowest = math.min(lowest, self:until_position(begin + width) - self:until_position(begin))
            end
        end
    end
    return pct(lowest, width)
end
local Run = {}
Run.__index = Run
function Run.new(entry, config, script)
    return setmetatable({entry = entry, config = config, script = script, collector = heap.state(config.size, entry), roots = {}, cascades = {}, reports = {}, observations = {}, timeline = Timeline.new(), peak_used = 0, increments = 0, decrements = 0, released = {}}, Run)
end
function Run:retain(number)
    if self.entry.algorithm == "REFCOUNT" and number ~= 0 then
        self.collector.objects[number].count, self.increments = self.collector.objects[number].count + 1, self.increments + 1
    end
end
function Run:release(number)
    if self.entry.algorithm ~= "REFCOUNT" or number == 0 then
        return
    end
    local objects = self.collector.objects
    self.decrements, objects[number].count = self.decrements + 1, objects[number].count - 1
    if objects[number].count > 0 then
        return
    end
    local pending = {number}
    while #pending > 0 do
        local object = objects[table.remove(pending)]
        object.present = false
        self.released[#self.released + 1] = object
        for _, child in ipairs(object.fields) do
            if child ~= 0 then
                self.decrements, objects[child].count = self.decrements + 1, objects[child].count - 1
                if objects[child].count == 0 then
                    pending[#pending + 1] = child
                end
            end
        end
    end
end
function Run:value(source)
    return source < 0 and 0 or self.roots[source + 1]
end
function Run:push(number)
    self:retain(number)
    self.roots[#self.roots + 1] = number
end
function Run:backup(line, request)
    local state = self.collector
    local record = heap.record(state, line, request, "backup")
    marking.mark(state, self.roots, record)
    local garbage = {}
    for _, object in ipairs(heap.active(state)) do
        if not object.marked then
            garbage[#garbage + 1] = object
        end
    end
    self.reports[#self.reports + 1] = leak_report("backup " .. record.number .. " line " .. line, garbage, self.script.deaths, state.objects)
    marking.sweep(state, record)
    for _, object in ipairs(garbage) do
        for _, child in ipairs(object.fields) do
            if child ~= 0 and state.objects[child].marked then
                state.objects[child].count, self.decrements = state.objects[child].count - 1, self.decrements + 1
            end
        end
    end
    heap.finish(state, record)
end
function Run:allocate(object, line)
    local state, kind = self.collector, self.entry.algorithm
    if kind == "GENERATIONAL" then
        return generational.allocate(state, self.roots, object, line)
    end
    local address
    if kind == "MARK_COMPACT" or kind == "COPYING" then
        local finish = kind == "MARK_COMPACT" and state.size or state.base + state.half
        if state.top + object.size > finish then
            if kind == "COPYING" then
                copying.collect(state, self.roots, line, object.size)
            else
                marking.collect(state, self.roots, line, object.size)
            end
            finish = kind == "MARK_COMPACT" and state.size or state.base + state.half
        end
        if state.top + object.size > finish then
            return false
        end
        address, state.top = state.top, state.top + object.size
    else
        address = heap.first_fit(heap.free_list(state), object.size)
        if not address then
            if kind == "REFCOUNT" then
                self:backup(line, object.size)
            else
                marking.collect(state, self.roots, line, object.size)
            end
            address = heap.first_fit(heap.free_list(state), object.size)
        end
        if not address then
            return false
        end
    end
    object.address = address
    state.objects[#state.objects + 1] = object
    return true
end
function Run:observe(checkpoint)
    local state, reached = self.collector, checkpoint.reachable
    local objects, live, garbage = heap.active(state), heap.pair(), heap.pair()
    local pointers, forward, backward, distance = 0, 0, 0, 0
    for _, object in ipairs(objects) do
        if reached[object.number] then
            heap.add(live, object)
            for _, child in ipairs(object.fields) do
                if child ~= 0 then
                    local address = state.objects[child].address
                    pointers, distance = pointers + 1, distance + math.abs(address - object.address)
                    if address > object.address then
                        forward = forward + 1
                    elseif address < object.address then
                        backward = backward + 1
                    end
                end
            end
        else
            heap.add(garbage, object)
        end
    end
    local blocks = heap.free_list(state)
    local lengths = {}
    for i, block in ipairs(blocks) do
        lengths[i] = block.length
    end
    local lines = {
        "heap objects " .. pair_text(pair_of(objects)) .. " reachable " .. pair_text(live) .. " garbage " .. pair_text(garbage),
        "free total " .. heap.total_free(blocks) .. " largest " .. heap.largest_free(blocks) .. " blocks " .. #blocks .. " sizes " .. heap.class_table(lengths) .. " fragmentation " .. fragmentation(blocks),
        string.format("locality pointers %d forward %d backward %d mean_distance %s", pointers, forward, backward, pointers == 0 and "-" or heap.dec2(distance, pointers))
    }
    if self.entry.algorithm == "GENERATIONAL" then
        local young, old, ages = heap.pair(), heap.pair(), {0, 0, 0, 0}
        for _, object in ipairs(objects) do
            if object.address < state.young then
                heap.add(young, object)
                local age = math.min(3, object.age) + 1
                ages[age] = ages[age] + 1
            else
                heap.add(old, object)
            end
        end
        local remembered = 0
        for _ in pairs(state.remembered) do
            remembered = remembered + 1
        end
        lines[#lines + 1] = "generations young " .. pair_text(young) .. " old " .. pair_text(old) .. " remembered " .. remembered .. string.format(" ages 0:%d 1:%d 2:%d 3+:%d", table.unpack(ages))
    end
    if contains(self.config.maps, checkpoint.label) then
        local text = heap.heap_map(state, reached)
        for start = 0, #text - 1, self.config.width do
            lines[#lines + 1] = string.format("%04d %s", start, text:sub(start + 1, start + self.config.width))
        end
    end
    return lines
end
function Run:execute(command)
    local kind, state = command.name, self.collector
    if kind == "PUSH" then
        self:push(self:value(command.source))
    elseif kind == "LOAD" then
        self:push(state.objects[self.roots[command.slot + 1]].fields[command.field + 1])
    elseif kind == "POP" then
        for _ = 1, command.count do
            self:release(table.remove(self.roots))
        end
    elseif kind == "SET" then
        local target, value = self.roots[command.slot + 1], self:value(command.source)
        if self.entry.algorithm == "GENERATIONAL" then
            generational.write_barrier(state, target, value)
        end
        self:retain(value)
        local previous = state.objects[target].fields[command.field + 1]
        state.objects[target].fields[command.field + 1] = value
        self:release(previous)
    elseif kind == "OVERWRITE" then
        local value = self:value(command.source)
        self:retain(value)
        local previous = self.roots[command.slot + 1]
        self.roots[command.slot + 1] = value
        self:release(previous)
    elseif kind == "CHECKPOINT" then
        self.observations[#self.observations + 1] = self:observe(self.script.checkpoints[#self.observations + 1])
    end
end
function Run:simulate()
    for _, command in ipairs(self.script.commands) do
        local previous, placed, units = #self.collector.records, true, 1
        if command.name == "ALLOC" then
            local object = heap.object(#self.collector.objects + 1, command.pointers, command.data)
            placed, units = self:allocate(object, command.line), object.size
            if placed then
                self:push(object.number)
                self.peak_used = math.max(self.peak_used, words(heap.active(self.collector)))
            end
        else
            self:execute(command)
        end
        for i = previous + 1, #self.collector.records do
            self.timeline:add(false, self.collector.records[i].work)
        end
        if not placed then
            self.failed_line, self.failed_size = command.line, units
            return
        end
        self.timeline:add(true, units)
        if #self.released > 0 then
            local freed, work = pair_of(self.released), 0
            for _, object in ipairs(self.released) do
                work = work + 1 + #object.fields
            end
            self.cascades[#self.cascades + 1] = {line = command.line, freed = freed, work = work}
            self.timeline:add(false, work)
            self.released = {}
        end
    end
    if self.entry.algorithm == "REFCOUNT" then
        local garbage = {}
        for _, object in ipairs(heap.active(self.collector)) do
            if not self.script.alive[object.number] then
                garbage[#garbage + 1] = object
            end
        end
        self.reports[#self.reports + 1] = leak_report("end", garbage, self.script.deaths, self.collector.objects)
    end
end
function Run:pauses()
    local pauses = {}
    for _, record in ipairs(self.collector.records) do
        pauses[#pauses + 1] = {line = record.line, work = record.work, freed = record.freed.words, collection = true}
    end
    for _, cascade in ipairs(self.cascades) do
        pauses[#pauses + 1] = {line = cascade.line, work = cascade.work, freed = cascade.freed.words, collection = false}
    end
    return pauses
end
function Run:collection_lines()
    local state = self.collector
    local lines = {"collector " .. self.entry.name .. " " .. self.entry.algorithm}
    for _, record in ipairs(state.records) do
        lines[#lines + 1] = record.number .. " line " .. record.line .. " size " .. record.request .. " kind " .. record.kind .. " live " .. pair_text(record.live) .. " freed " .. pair_text(record.freed) .. " moved " .. pair_text(record.moved) .. " promoted " .. pair_text(record.promoted) .. " stack " .. record.stack .. " work " .. record.work .. " before " .. record.before[1] .. " " .. record.before[2] .. " after " .. record.after[1] .. " " .. record.after[2]
    end
    local pauses, stats = self:pauses(), pause_stats(self:pauses())
    lines[#lines + 1] = string.format("totals collections %d pauses %d work %d freed %d pause p50 %s p90 %s max %d", stats.collections, stats.count, stats.work, stats.freed, stats.p50, stats.p90, stats.maximum)
    local windows = {}
    for _, width in ipairs(self.config.windows) do
        windows[#windows + 1] = width .. ":" .. self.timeline:mmu(width)
    end
    lines[#lines + 1] = "utilization " .. pct(self.timeline.mutator, self.timeline.length) .. " mmu " .. table.concat(windows, " ")
    if self.entry.algorithm == "GENERATIONAL" then
        local parts, promoted = {"generational"}, heap.pair()
        for _, kind in ipairs({"minor", "major", "tenure", "full"}) do
            local count, work = 0, 0
            for _, record in ipairs(state.records) do
                if record.kind == kind then
                    count, work = count + 1, work + record.work
                end
            end
            parts[#parts + 1] = kind .. " " .. count .. " " .. work
        end
        for _, record in ipairs(state.records) do
            heap.add_pair(promoted, record.promoted)
        end
        parts[#parts + 1] = "promoted " .. pair_text(promoted) .. " barrier " .. state.barriers .. " remembered " .. state.remembers
        lines[#lines + 1] = table.concat(parts, " ")
    elseif self.entry.algorithm == "REFCOUNT" then
        local freed, largest = heap.pair(), nil
        for _, cascade in ipairs(self.cascades) do
            heap.add_pair(freed, cascade.freed)
            if not largest or cascade.work > largest.work then
                largest = cascade
            end
        end
        local maximum = largest and ("max_cascade " .. largest.freed.count .. " " .. largest.work .. " line " .. largest.line) or "max_cascade 0 0 line -"
        lines[#lines + 1] = string.format("refcount increments %d decrements %d cascades %d freed %s %s", self.increments, self.decrements, #self.cascades, pair_text(freed), maximum)
    end
    local previous = 0
    for _, checkpoint in ipairs(self.script.checkpoints) do
        if self.failed_line and self.failed_line < checkpoint.line then
            lines[#lines + 1] = "phase " .. checkpoint.label .. " out_of_memory"
        else
            local phase = {}
            for _, pause in ipairs(pauses) do
                if pause.line > previous and pause.line <= checkpoint.line then
                    phase[#phase + 1] = pause
                end
            end
            local phase_stats = pause_stats(phase)
            lines[#lines + 1] = string.format("phase %s collections %d pauses %d work %d freed %d max_pause %d", checkpoint.label, phase_stats.collections, phase_stats.count, phase_stats.work, phase_stats.freed, phase_stats.maximum)
        end
        previous = checkpoint.line
    end
    lines[#lines + 1] = self.failed_line and ("status out_of_memory line " .. self.failed_line .. " size " .. self.failed_size) or "status completed"
    return lines
end
function Run:summary()
    local state, stats = self.collector, pause_stats(self:pauses())
    local live, moved, moved_objects, maximum_moves = 0, 0, 0, 0
    for _, record in ipairs(state.records) do
        live, moved = live + record.live.count, moved + record.moved.count
    end
    for _, object in ipairs(state.objects) do
        if object.moves > 0 then
            moved_objects, maximum_moves = moved_objects + 1, math.max(maximum_moves, object.moves)
        end
    end
    local status = self.failed_line and "out_of_memory" or "completed"
    local values = {self.entry.name, self.entry.algorithm, status, #state.records, stats.count, live, moved, moved_objects, maximum_moves, stats.freed, stats.work, stats.p50, stats.p90, stats.maximum, self.peak_used}
    if self.failed_line then
        append(values, {"-", "-", "-", "-"})
    else
        local blocks = heap.free_list(state)
        append(values, {words(heap.active(state)), heap.total_free(blocks), heap.largest_free(blocks), fragmentation(blocks)})
    end
    return table.concat(values, ",")
end
local config, script = mutator.read_config("input/config.txt"), Script.new()
script:analyze(mutator.read_lines("input/mutator.txt"))
local runs = {}
for _, entry in ipairs(config.collectors) do
    local run = Run.new(entry, config, script)
    run:simulate()
    runs[#runs + 1] = run
end
local map_blocks, collection_blocks, leak_blocks = {}, {}, {}
for index, checkpoint in ipairs(script.checkpoints) do
    for _, run in ipairs(runs) do
        local lines = {"checkpoint " .. checkpoint.label .. " line " .. checkpoint.line .. " collector " .. run.entry.name}
        append(lines, run.observations[index] or {"out_of_memory"})
        map_blocks[#map_blocks + 1] = lines
    end
end
local summary = {"collector,type,status,collections,pauses,live,moved,moved_objects,max_moves,freed,total_work,p50_pause,p90_pause,max_pause,peak_used,end_used,end_free,largest_free,fragmentation"}
for _, run in ipairs(runs) do
    collection_blocks[#collection_blocks + 1] = run:collection_lines()
    summary[#summary + 1] = run:summary()
    if run.entry.algorithm == "REFCOUNT" then
        local lines = {"collector " .. run.entry.name}
        for _, report in ipairs(run.reports) do
            append(lines, report)
        end
        if run.failed_line then
            lines[#lines + 1] = "status out_of_memory"
        end
        leak_blocks[#leak_blocks + 1] = lines
    end
end
local function joined(blocks)
    local lines = {}
    for i, block in ipairs(blocks) do
        if i > 1 then
            lines[#lines + 1] = ""
        end
        append(lines, block)
    end
    return lines
end
os.execute("mkdir -p output")
local function write_lines(name, lines)
    local handle = assert(io.open("output/" .. name, "wb"))
    if #lines > 0 then
        handle:write(table.concat(lines, "\n"), "\n")
    end
    handle:close()
end
write_lines("mutator.txt", script:report())
write_lines("heap_maps.txt", joined(map_blocks))
write_lines("collections.txt", joined(collection_blocks))
write_lines("summary.csv", summary)
write_lines("leaks.txt", #leak_blocks == 0 and {"none"} or joined(leak_blocks))
