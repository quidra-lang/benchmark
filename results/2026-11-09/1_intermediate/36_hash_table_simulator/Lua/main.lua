local modes = {"CHAIN", "LINEAR", "QUADRATIC", "DOUBLE", "ROBINHOOD", "CUCKOO"}
local known_modes, commands = {}, {}
for _, mode in ipairs(modes) do known_modes[mode] = true end
for command in ("CREATE MAXLOAD MINLOAD TRACE HASH PUT ADD GET DEL PROBE GEN GENDEL " ..
                "RESIZE CONVERT CLEAR DUMP MAP STATS KEYS TOP SCAN CLUSTERS DIST COMPARE BENCH"):gmatch("%S+") do
    commands[command] = true
end
local TOMBSTONE = {}

local function fail(message) error({command_error = true, message = message}, 0) end
local function append(target, source)
    for _, value in ipairs(source) do target[#target + 1] = value end
end
local function ascii_less(a, b)
    for i = 1, math.min(#a, #b) do
        local x, y = a:byte(i), b:byte(i)
        if x ~= y then return x < y end
    end
    return #a < #b
end
local function checked_mode(mode)
    if not known_modes[mode] then fail("BAD MODE " .. mode) end
    return mode
end
local function hash(key, base, modulus)
    local value = 0
    for i = 1, #key do value = (value * base + key:byte(i)) % modulus end
    return value
end
local function prime(value)
    local candidate = math.max(value, 2)
    while true do
        local valid, divisor = true, 2
        while divisor * divisor <= candidate do
            if candidate % divisor == 0 then valid = false; break end
            divisor = divisor + 1
        end
        if valid then return candidate end
        candidate = candidate + 1
    end
end
local function ratio(numerator, denominator)
    local value = denominator == 0 and 0 or 100 * numerator // denominator
    return string.format("%d.%02d", value // 100, value % 100)
end
local function gauge(value) return value >= 10 and "+" or tostring(value) end
local function item_text(item) return item.key .. "=" .. item.value end
local function content(slot)
    if slot == TOMBSTONE then return "D" end
    return slot and slot.key or "-"
end
local function parts(mode) return mode == "CUCKOO" and 2 or 1 end
local function uses_tombstones(mode) return mode == "LINEAR" or mode == "QUADRATIC" or mode == "DOUBLE" end
local function generator(length, seed)
    return function()
        local bytes = {}
        for i = 1, length do
            seed = 48271 * seed % 2147483647
            bytes[i] = string.char(97 + seed % 26)
        end
        return table.concat(bytes)
    end
end
local function histogram(values)
    local counts, distinct, rows = {}, {}, {}
    for _, value in ipairs(values) do
        if not counts[value] then distinct[#distinct + 1] = value; counts[value] = 0 end
        counts[value] = counts[value] + 1
    end
    table.sort(distinct)
    for _, value in ipairs(distinct) do
        local count = counts[value]
        rows[#rows + 1] = string.format("%d %d %s%s", value, count, string.rep("#", math.min(count, 50)), count > 50 and "+" or "")
    end
    return rows
end
local function check_capacity(capacity)
    if capacity < 2 or capacity > 10000 then fail("BAD CAPACITY") end
end
local function check_generation(count, length, seed)
    if count < 1 or count > 500 or length < 1 or length > 10 or seed < 1 or seed > 2147483646 then fail("BAD ARGUMENT") end
end
local function path_lines(found, trace)
    return trace and {"PATH " .. (#found.path == 0 and "none" or table.concat(found.path, " "))} or {}
end
local function mutation(changed, row, path, moves, rehashes)
    local lines = {row}
    append(lines, path)
    append(lines, moves)
    append(lines, rehashes)
    return {changed = changed, lines = lines, rehashes = rehashes}
end

local Table = {}
Table.__index = Table
function Table.new(mode, capacity)
    local self = setmetatable({mode = mode, capacity = capacity, size = 0, tombstones = 0,
        buckets = {}, slots = {}, counters = {probes = 0, rehashes = 0, inserts = 0, updates = 0,
            hits = 0, misses = 0, deletes = 0, absent = 0}}, Table)
    if mode == "CHAIN" then
        for i = 1, capacity do self.buckets[i] = {} end
    else
        for i = 1, capacity * parts(mode) do self.slots[i] = false end
    end
    return self
end
function Table:slot_count() return self.capacity * parts(self.mode) end
function Table:position(index)
    index = index - 1
    return self.mode == "CUCKOO" and string.format("T%d.%d", index // self.capacity + 1, index % self.capacity) or tostring(index)
end
function Table:distance(key, index) return (index - 1 - hash(key, 31, self.capacity)) % self.capacity end
function Table:items()
    local result = {}
    if self.mode == "CHAIN" then
        for _, bucket in ipairs(self.buckets) do append(result, bucket) end
    else
        for _, slot in ipairs(self.slots) do
            if slot and slot ~= TOMBSTONE then result[#result + 1] = slot end
        end
    end
    return result
end
function Table:search(key, trace)
    local result = {probes = 0, path = {}}
    local first = hash(key, 31, self.capacity) + 1
    local function examine(index, slot)
        result.probes = result.probes + 1
        if trace then result.path[#result.path + 1] = self:position(index) .. ":" .. content(slot) end
    end
    local function found(item, index, chain_index)
        result.item, result.position, result.chain_index = item, index, chain_index
    end
    if self.mode == "CHAIN" then
        for i, item in ipairs(self.buckets[first]) do
            examine(first, item)
            if item.key == key then found(item, first, i); break end
        end
        return result
    end
    if self.mode == "CUCKOO" then
        for _, index in ipairs({first, self.capacity + hash(key, 37, self.capacity) + 1}) do
            local slot = self.slots[index]
            examine(index, slot)
            if slot and slot.key == key then found(slot, index); break end
        end
        return result
    end
    local step = self.mode == "DOUBLE" and 1 + hash(key, 37, self.capacity - 1) or 1
    for i = 0, self.capacity - 1 do
        local offset = self.mode == "QUADRATIC" and i * i or i * step
        local index = (first - 1 + offset) % self.capacity + 1
        local slot = self.slots[index]
        examine(index, slot)
        if not slot then result.available = result.available or index; break end
        if slot == TOMBSTONE then
            result.available = result.available or index
        else
            if slot.key == key then found(slot, index); break end
            if self.mode == "ROBINHOOD" and self:distance(slot.key, index) < i then break end
        end
    end
    return result
end
function Table:place(item, initial, trace)
    local result = {success = false, reused = false, shifted = 0, kicks = 0, moves = {}}
    if self.mode == "CHAIN" then
        local index = hash(item.key, 31, self.capacity) + 1
        self.buckets[index][#self.buckets[index] + 1] = item
        result.position, result.success = index, true
        return result
    end
    if uses_tombstones(self.mode) then
        local found = initial or self:search(item.key)
        local index = found.available
        if not index then result.homeless = item; return result end
        result.position, result.reused = index, self.slots[index] == TOMBSTONE
        self.slots[index] = item
        if result.reused then self.tombstones = self.tombstones - 1 end
        result.success = true
        return result
    end
    local current = item
    if self.mode == "ROBINHOOD" then
        local index, distance, origin = hash(item.key, 31, self.capacity) + 1, 0, nil
        while true do
            local resident = self.slots[index]
            if not resident then
                self.slots[index] = current
                if trace and origin then result.moves[#result.moves + 1] = string.format("SHIFT %s %d -> %d", current.key, origin - 1, index - 1) end
                result.position = result.position or index
                result.success = true
                return result
            end
            local resident_distance = self:distance(resident.key, index)
            if resident_distance < distance then
                self.slots[index] = current
                if trace and origin then result.moves[#result.moves + 1] = string.format("SHIFT %s %d -> %d", current.key, origin - 1, index - 1) end
                result.position = result.position or index
                current, origin, distance = resident, index, resident_distance
                result.shifted = result.shifted + 1
            end
            index, distance = index % self.capacity + 1, distance + 1
        end
    end
    local part = 0
    while true do
        local index = part * self.capacity + hash(current.key, part == 0 and 31 or 37, self.capacity) + 1
        local resident = self.slots[index]
        if not resident then
            self.slots[index] = current
            result.success = true
            result.position = self:search(item.key).position
            return result
        end
        if result.kicks == self.capacity then result.homeless = current; return result end
        self.slots[index] = current
        result.kicks = result.kicks + 1
        if trace then result.moves[#result.moves + 1] = "KICK " .. resident.key .. " " .. self:position(index) end
        current, part = resident, 1 - part
    end
end
function Table:remove(found, trace)
    local result = {shifted = 0, moves = {}}
    if self.mode == "CHAIN" then
        table.remove(self.buckets[found.position], found.chain_index)
    elseif uses_tombstones(self.mode) then
        self.slots[found.position] = TOMBSTONE
        self.tombstones = self.tombstones + 1
    else
        self.slots[found.position] = false
        if self.mode == "ROBINHOOD" then
            local following = found.position % self.capacity + 1
            while self.slots[following] and self:distance(self.slots[following].key, following) > 0 do
                local item = self.slots[following]
                local destination = (following - 2) % self.capacity + 1
                self.slots[destination], self.slots[following] = item, false
                if trace then result.moves[#result.moves + 1] = string.format("SHIFT %s %d -> %d", item.key, following - 1, destination - 1) end
                result.shifted = result.shifted + 1
                following = following % self.capacity + 1
            end
        end
    end
    self.size = self.size - 1
    return result
end
function Table.rebuild(items, mode, capacity)
    local trial = Table.new(mode, capacity)
    for _, item in ipairs(items) do
        if not trial:place(item).success then return nil end
        trial.size = trial.size + 1
    end
    return trial
end
function Table:adopt(replacement)
    self.mode, self.capacity = replacement.mode, replacement.capacity
    self.size, self.tombstones = replacement.size, replacement.tombstones
    self.buckets, self.slots = replacement.buckets, replacement.slots
end
function Table:automatic(reason, capacity, pending)
    local items, old = self:items(), self.capacity
    if pending then items[#items + 1] = pending end
    while true do
        local trial = Table.rebuild(items, self.mode, capacity)
        if trial then
            self:adopt(trial)
            self.counters.rehashes = self.counters.rehashes + 1
            return string.format("REHASH %s %d -> %d", reason, old, capacity)
        end
        capacity = prime(2 * capacity)
    end
end
function Table:load_check(max_load)
    local threshold = max_load * self:slot_count()
    if 100 * (self.size + self.tombstones) <= threshold then return {} end
    local grow = 200 * self.size > threshold
    return {self:automatic(grow and "load" or "tomb", grow and prime(2 * self.capacity) or self.capacity)}
end
function Table:shrink_check(min_load, max_load)
    local capacity = prime(self.capacity // 2)
    if 100 * self.size >= min_load * self:slot_count() or capacity >= self.capacity or
       100 * self.size > max_load * capacity * parts(self.mode) then return {} end
    local trial = Table.rebuild(self:items(), self.mode, capacity)
    if not trial then return {} end
    local old = self.capacity
    self:adopt(trial)
    self.counters.rehashes = self.counters.rehashes + 1
    return {string.format("REHASH shrink %d -> %d", old, capacity)}
end
function Table:put(key, value, max_load, command, trace)
    command = command or "PUT"
    local found = self:search(key, trace)
    local path = path_lines(found, trace)
    self.counters.probes = self.counters.probes + found.probes
    if found.item then
        local old = found.item.value
        local item = {key = key, value = command == "ADD" and old + value or value}
        if self.mode == "CHAIN" then self.buckets[found.position][found.chain_index] = item else self.slots[found.position] = item end
        self.counters.updates = self.counters.updates + 1
        local row = string.format("%s %s UPDATED old=%d at=%s probes=%d", command, item_text(item), old, self:position(found.position), found.probes)
        return mutation(false, row, path, {}, {})
    end
    local item = {key = key, value = value}
    local placed = self:place(item, found, trace)
    self.size = self.size + 1
    self.counters.inserts = self.counters.inserts + 1
    local row = command .. " " .. item_text(item) .. " NEW"
    if placed.success then
        row = row .. string.format(" at=%s probes=%d", self:position(placed.position), found.probes)
        if placed.reused then row = row .. " reused" end
        if self.mode == "ROBINHOOD" then row = row .. " shifted=" .. placed.shifted end
        if self.mode == "CUCKOO" then row = row .. " kicks=" .. placed.kicks end
    else
        row = row .. " probes=" .. found.probes .. (self.mode == "CUCKOO" and " kicks=" .. placed.kicks .. " failed" or " full")
    end
    local rehashes = {}
    if not placed.success then
        rehashes[#rehashes + 1] = self:automatic(self.mode == "CUCKOO" and "kicks" or "full", prime(2 * self.capacity), placed.homeless)
    end
    append(rehashes, self:load_check(max_load))
    return mutation(true, row, path, placed.moves, rehashes)
end
function Table:get(key, trace)
    local found = self:search(key, trace)
    self.counters.probes = self.counters.probes + found.probes
    local row
    if found.item then
        self.counters.hits = self.counters.hits + 1
        row = string.format("GET %s at=%s probes=%d", item_text(found.item), self:position(found.position), found.probes)
    else
        self.counters.misses = self.counters.misses + 1
        row = string.format("GET %s NOT FOUND probes=%d", key, found.probes)
    end
    local rows = {row}
    append(rows, path_lines(found, trace))
    return rows
end
function Table:delete(key, min_load, max_load, trace)
    local found = self:search(key, trace)
    local path = path_lines(found, trace)
    self.counters.probes = self.counters.probes + found.probes
    if not found.item then
        self.counters.absent = self.counters.absent + 1
        return mutation(false, string.format("DEL %s NOT FOUND probes=%d", key, found.probes), path, {}, {})
    end
    local removed = self:remove(found, trace)
    self.counters.deletes = self.counters.deletes + 1
    local row = string.format("DEL %s OK at=%s probes=%d", key, self:position(found.position), found.probes)
    if self.mode == "ROBINHOOD" then row = row .. " shifted=" .. removed.shifted end
    return mutation(true, row, path, removed.moves, self:shrink_check(min_load, max_load))
end
function Table:costs()
    local records = {}
    if self.mode == "CHAIN" then
        for index, bucket in ipairs(self.buckets) do
            for i, item in ipairs(bucket) do records[#records + 1] = {key = item.key, probes = i, position = index} end
        end
    else
        for index, slot in ipairs(self.slots) do
            if slot and slot ~= TOMBSTONE then
                local cost
                if self.mode == "CUCKOO" then cost = (index - 1) // self.capacity + 1
                elseif self.mode == "LINEAR" or self.mode == "ROBINHOOD" then cost = self:distance(slot.key, index) + 1
                else cost = self:search(slot.key).probes end
                records[#records + 1] = {key = slot.key, probes = cost, position = index}
            end
        end
    end
    return records
end
function Table:metrics()
    local total, longest = 0, 0
    for _, cost in ipairs(self:costs()) do total, longest = total + cost.probes, math.max(longest, cost.probes) end
    return {longest = longest, average = ratio(total, self.size)}
end
function Table:dump()
    local rows = {string.format("DUMP %s cap=%d size=%d tomb=%d", self.mode, self.capacity, self.size, self.tombstones)}
    if self.mode == "CHAIN" then
        for index, bucket in ipairs(self.buckets) do
            local words = {tostring(index - 1)}
            if #bucket == 0 then words[#words + 1] = "-" end
            for _, item in ipairs(bucket) do words[#words + 1] = item_text(item) end
            rows[#rows + 1] = table.concat(words, " ")
        end
    else
        for index, slot in ipairs(self.slots) do
            local label = self.mode == "CUCKOO" and string.format("T%d %d", (index - 1) // self.capacity + 1, (index - 1) % self.capacity) or tostring(index - 1)
            local value = content(slot)
            if slot and slot ~= TOMBSTONE then
                value = item_text(slot)
                if self.mode == "ROBINHOOD" then value = value .. " d=" .. self:distance(slot.key, index) end
            end
            rows[#rows + 1] = label .. " " .. value
        end
    end
    return rows
end
function Table:map()
    local rows = {string.format("MAP %s cap=%d", self.mode, self.capacity)}
    local cost_by_slot = {}
    if self.mode ~= "CHAIN" then
        for _, cost in ipairs(self:costs()) do cost_by_slot[cost.position] = cost.probes end
    end
    for part = 0, parts(self.mode) - 1 do
        local characters = {}
        for index = 1, self.capacity do
            if self.mode == "CHAIN" then
                local count = #self.buckets[index]
                characters[index] = count == 0 and "." or gauge(count)
            else
                local flat = part * self.capacity + index
                local slot = self.slots[flat]
                if not slot then characters[index] = "."
                elseif slot == TOMBSTONE then characters[index] = "D"
                elseif self.mode == "CUCKOO" then characters[index] = "#"
                else characters[index] = gauge(cost_by_slot[flat] - 1) end
            end
        end
        for index = 1, self.capacity, 40 do
            local prefix = self.mode == "CUCKOO" and "T" .. (part + 1) .. " " or ""
            rows[#rows + 1] = prefix .. string.format("%05d ", index - 1) .. table.concat(characters, "", index, math.min(index + 39, self.capacity))
        end
    end
    return rows
end
function Table:statistics()
    local values, count = self:metrics(), self.counters
    return {string.format("STATS %s size=%d cap=%d slots=%d tomb=%d load=%s%% longest=%d avg=%s probes=%d rehashes=%d",
        self.mode, self.size, self.capacity, self:slot_count(), self.tombstones, ratio(100 * self.size, self:slot_count()),
        values.longest, values.average, count.probes, count.rehashes),
        string.format("OPS inserts=%d updates=%d hits=%d misses=%d deletes=%d absent=%d", count.inserts, count.updates, count.hits, count.misses, count.deletes, count.absent)}
end
function Table:scan(cursor, limit)
    local keys = {}
    while cursor < self:slot_count() and #keys < limit do
        local index = cursor + 1
        if self.mode == "CHAIN" then
            for _, item in ipairs(self.buckets[index]) do keys[#keys + 1] = item.key end
        else
            local slot = self.slots[index]
            if slot and slot ~= TOMBSTONE then keys[#keys + 1] = slot.key end
        end
        cursor = cursor + 1
    end
    if cursor == self:slot_count() then cursor = 0 end
    local words = {"SCAN next=" .. cursor}
    append(words, keys)
    return {table.concat(words, " ")}
end
function Table:runs(start, count)
    local empty
    for i = 0, count - 1 do if not self.slots[start + i] then empty = i; break end end
    if empty == nil then return {count} end
    local lengths, length = {}, 0
    for offset = 1, count do
        if self.slots[start + (empty + offset) % count] then length = length + 1
        elseif length > 0 then lengths[#lengths + 1] = length; length = 0 end
    end
    return lengths
end
function Table:clusters()
    local lengths = {}
    if self.mode == "CHAIN" then
        for _, bucket in ipairs(self.buckets) do if #bucket > 0 then lengths[#lengths + 1] = #bucket end end
    else
        for part = 0, parts(self.mode) - 1 do append(lengths, self:runs(part * self.capacity + 1, self.capacity)) end
    end
    local longest = 0
    for _, length in ipairs(lengths) do longest = math.max(longest, length) end
    local rows = {string.format("CLUSTERS runs=%d longest=%d", #lengths, longest)}
    append(rows, histogram(lengths))
    return rows
end
function Table:distribution()
    local values, longest = {}, 0
    for _, cost in ipairs(self:costs()) do values[#values + 1] = cost.probes; longest = math.max(longest, cost.probes) end
    local rows = {string.format("DIST keys=%d longest=%d", self.size, longest)}
    append(rows, histogram(values))
    return rows
end

local Simulator = {}
Simulator.__index = Simulator
function Simulator.new() return setmetatable({max_load = 75, min_load = 0, trace = false}, Simulator) end
function Simulator:compare(capacity)
    local items = self.current:items()
    table.sort(items, function(a, b) return ascii_less(a.key, b.key) end)
    local rows = {string.format("COMPARE keys=%d cap=%d", #items, capacity)}
    for _, mode in ipairs(modes) do
        local trial = Table.new(mode, capacity)
        for _, item in ipairs(items) do trial:put(item.key, item.value, self.max_load) end
        local values = trial:metrics()
        rows[#rows + 1] = string.format("%s cap=%d longest=%d avg=%s probes=%d rehashes=%d", mode, trial.capacity, values.longest, values.average, trial.counters.probes, trial.counters.rehashes)
    end
    return rows
end
function Simulator:bench(capacity, count, length, seed)
    local next_key, keys = generator(length, seed), {}
    for i = 1, 2 * count do keys[i] = next_key() end
    local rows = {string.format("BENCH cap=%d count=%d len=%d seed=%d", capacity, count, length, seed)}
    for _, mode in ipairs(modes) do
        local trial = Table.new(mode, capacity)
        for i = 1, count do trial:put(keys[i], i, self.max_load) end
        local misses, probes = 0, 0
        for i = count + 1, 2 * count do
            local found = trial:search(keys[i])
            if not found.item then misses, probes = misses + 1, probes + found.probes end
        end
        rows[#rows + 1] = string.format("%s cap=%d keys=%d hit=%s misses=%d miss=%s rehashes=%d", mode, trial.capacity, trial.size,
            trial:metrics().average, misses, ratio(probes, misses), trial.counters.rehashes)
    end
    return rows
end
function Simulator:execute(line)
    local words = {}
    for word in line:gmatch("%S+") do words[#words + 1] = word end
    local command = words[1]
    if not commands[command] then fail("UNKNOWN COMMAND " .. command) end
    local function number(index) return tonumber(words[index], 10) end
    if command == "CREATE" then
        local mode = checked_mode(words[2])
        local capacity = number(3)
        check_capacity(capacity)
        self.current = Table.new(mode, prime(capacity))
        return {string.format("CREATE %s cap=%d", mode, self.current.capacity)}
    elseif command == "MAXLOAD" or command == "MINLOAD" then
        local value, maximum = number(2), command == "MAXLOAD"
        if maximum and (value < 10 or value > 95) or not maximum and (value < 0 or value > 40) then fail("BAD LOAD") end
        if maximum then self.max_load = value else self.min_load = value end
        return {command .. " " .. value}
    elseif command == "TRACE" then
        if words[2] ~= "ON" and words[2] ~= "OFF" then fail("BAD ARGUMENT") end
        self.trace = words[2] == "ON"
        return {"TRACE " .. words[2]}
    elseif command == "HASH" then
        local key, capacity = words[2], number(3)
        check_capacity(capacity)
        return {string.format("HASH %s m=%d h31=%d h37=%d step=%d", key, capacity, hash(key, 31, capacity), hash(key, 37, capacity), 1 + hash(key, 37, capacity - 1))}
    elseif command == "BENCH" then
        local capacity = number(2)
        check_capacity(capacity)
        local count, length, seed = number(3), number(4), number(5)
        check_generation(count, length, seed)
        return self:bench(prime(capacity), count, length, seed)
    end
    local current = self.current
    if not current then fail("NO TABLE") end
    if command == "PUT" or command == "ADD" then
        return current:put(words[2], number(3), self.max_load, command, self.trace).lines
    elseif command == "GET" then return current:get(words[2], self.trace)
    elseif command == "DEL" then return current:delete(words[2], self.min_load, self.max_load, self.trace).lines
    elseif command == "PROBE" then
        local found = current:search(words[2], true)
        local output = {"PROBE " .. words[2]}
        append(output, found.path)
        output[#output + 1] = (found.item and "FOUND" or "MISS") .. " probes=" .. found.probes
        return {table.concat(output, " ")}
    elseif command == "GEN" or command == "GENDEL" then
        local count, length, seed = number(2), number(3), number(4)
        check_generation(count, length, seed)
        local next_key, rows, changed = generator(length, seed), {}, 0
        for i = 1, count do
            local key = next_key()
            local result = command == "GEN" and current:put(key, i, self.max_load) or current:delete(key, self.min_load, self.max_load)
            if result.changed then changed = changed + 1 end
            append(rows, result.rehashes)
        end
        rows[#rows + 1] = command == "GEN" and string.format("GEN %d new=%d updated=%d", count, changed, count - changed)
            or string.format("GENDEL %d deleted=%d missing=%d", count, changed, count - changed)
        return rows
    elseif command == "RESIZE" or command == "CONVERT" then
        local mode, capacity = current.mode, current.capacity
        if command == "RESIZE" then capacity = number(2); check_capacity(capacity); capacity = prime(capacity)
        else mode = checked_mode(words[2]) end
        if 100 * current.size > self.max_load * capacity * parts(mode) then fail("TOO SMALL") end
        local trial = Table.rebuild(current:items(), mode, capacity)
        if not trial then fail("REBUILD FAILED") end
        local row = command == "RESIZE" and string.format("RESIZE %d -> %d", current.capacity, capacity)
            or string.format("CONVERT %s -> %s cap=%d", current.mode, mode, capacity)
        current:adopt(trial)
        return {row}
    elseif command == "CLEAR" then
        local size = current.size
        current:adopt(Table.new(current.mode, current.capacity))
        return {"CLEAR " .. size}
    elseif command == "DUMP" then return current:dump()
    elseif command == "MAP" then return current:map()
    elseif command == "STATS" then return current:statistics()
    elseif command == "KEYS" then
        local keys = {}
        for _, item in ipairs(current:items()) do keys[#keys + 1] = item.key end
        table.sort(keys, ascii_less)
        local output = {"KEYS " .. current.size}
        append(output, keys)
        return {table.concat(output, " ")}
    elseif command == "TOP" then
        local limit = number(2)
        if limit < 1 or limit > 100 then fail("BAD ARGUMENT") end
        local records = current:costs()
        table.sort(records, function(a, b)
            if a.probes ~= b.probes then return a.probes > b.probes end
            return ascii_less(a.key, b.key)
        end)
        local count = math.min(limit, #records)
        local rows = {"TOP " .. count}
        for i = 1, count do
            local cost = records[i]
            rows[#rows + 1] = string.format("%s cost=%d at=%s", cost.key, cost.probes, current:position(cost.position))
        end
        return rows
    elseif command == "SCAN" then
        local cursor, limit = number(2), number(3)
        if limit < 1 or limit > 100 then fail("BAD ARGUMENT") end
        if cursor >= current:slot_count() then fail("BAD CURSOR") end
        return current:scan(cursor, limit)
    elseif command == "CLUSTERS" then return current:clusters()
    elseif command == "DIST" then return current:distribution()
    elseif command == "COMPARE" then
        local capacity = number(2)
        check_capacity(capacity)
        return self:compare(prime(capacity))
    end
    error("Unhandled command " .. command, 0)
end

local count = tonumber(io.read("l"), 10)
local simulator = Simulator.new()
for _ = 1, count do
    local line = io.read("l"):gsub("\r$", "")
    local ok, rows = pcall(simulator.execute, simulator, line)
    if ok then io.write(table.concat(rows, "\n"), "\n")
    elseif type(rows) == "table" and rows.command_error then io.write("ERROR ", rows.message, "\n")
    else error(rows, 0) end
    io.flush()
end
