local policies = {
    "FIFO",
    "LRU",
    "LFU",
    "NRU",
    "AGING",
    "CLOCK",
    "ECLOCK",
    "WSCLOCK",
    "RANDOM",
    "OPT"
}
local defaults = {
    page = 256,
    frames = 4,
    tlb = 4,
    sets = 1,
    policy = "FIFO",
    scope = "GLOBAL",
    asid = "OFF",
    tick = 0,
    tau = 8,
    seed = 1
}
local keys = {"page", "frames", "tlb", "sets", "policy", "scope", "asid", "tick", "tau", "seed"}
local function emit(s)
    io.write(s, "\n")
end
local function hex(n)
    return string.format("0x%X", n)
end
local function ratio(x, y)
    local v = y > 0 and 10000 * x // y or 0
    return string.format("%d.%02d%%", v // 100, v % 100)
end
local function sortedkeys(t)
    local a = {}
    for k in pairs(t) do
        a[#a + 1] = k
    end
    table.sort(a)
    return a
end
local function contains(a, value)
    for i, v in ipairs(a) do
        if v == value then
            return i
        end
    end
end
local function fail(s)
    error(s, 0)
end
local Sim = {}
Sim.__index = Sim
function Sim:new(config, refs)
    local s =
        setmetatable(
        {
            c = config,
            refs = refs,
            procs = {},
            frames = {},
            tlb = {},
            swap = {},
            events = {},
            history = {},
            time = 0,
            faults = 0,
            writebacks = 0,
            tlbhits = 0,
            zero = 0,
            swapin = 0,
            switches = 0,
            cursor = 0,
            hand = 0,
            random = config.seed,
            fixed = false,
            trace = false
        },
        self
    )
    for i = 1, config.sets do
        s.tlb[i] = {}
    end
    return s
end
function Sim:declare(pid, count)
    if self.fixed then
        fail("processes are fixed")
    end
    if self.procs[pid] then
        fail("duplicate process " .. pid)
    end
    if count < 1 or count > 256 then
        fail("invalid page count")
    end
    local n = #sortedkeys(self.procs)
    if n >= 8 or (self.c.scope == "LOCAL" and n >= self.c.frames) then
        fail("too many processes")
    end
    local p = {
        pages = {},
        accesses = 0,
        faults = 0,
        writebacks = 0,
        segfaults = 0,
        protfaults = 0,
        peak = 0,
        hand = 0,
        refs = {}
    }
    for i = 0, count - 1 do
        p.pages[i + 1] = {
            pid = pid,
            p = i,
            r = 0,
            m = 0,
            load = 0,
            last = 0,
            uses = 0,
            age = 0,
            ro = false,
            locked = false,
            ever = false
        }
    end
    self.procs[pid] = p
end
function Sim:process(pid)
    local p = self.procs[pid]
    if not p then
        fail("unknown process " .. pid)
    end
    if p.exited then
        fail("process " .. pid .. " exited")
    end
    return p
end
function Sim:resident(pid)
    local n = 0
    for i = 0, self.c.frames - 1 do
        if self.frames[i] and self.frames[i].pid == pid then
            n = n + 1
        end
    end
    return n
end
function Sim:quota(pid)
    local ids = sortedkeys(self.procs)
    local q, r = self.c.frames // #ids, self.c.frames % #ids
    return q + (contains(ids, pid) <= r and 1 or 0)
end
function Sim:invalidate(page)
    for _, set in ipairs(self.tlb) do
        local i = contains(set, page)
        if i then
            table.remove(set, i)
        end
    end
end
function Sim:writeback(page)
    self.writebacks = self.writebacks + 1
    local p = self.procs[page.pid]
    p.writebacks = p.writebacks + 1
    page.m = 0
    if page.slot == nil then
        local slot = 0
        while self.swap[slot] do
            slot = slot + 1
        end
        page.slot = slot
        self.swap[slot] = page
    end
end
function Sim:victim(pid)
    local candidates, unlocked = {}, {}
    for i = 0, self.c.frames - 1 do
        local p = self.frames[i]
        if p and (self.c.scope == "GLOBAL" or p.pid == pid) then
            candidates[#candidates + 1] = i
            if not p.locked then
                unlocked[#unlocked + 1] = i
            end
        end
    end
    if #unlocked > 0 then
        candidates = unlocked
    end
    local policy = self.c.policy
    if policy == "RANDOM" then
        self.random = 48271 * self.random % 2147483647
        return candidates[1 + self.random % #candidates]
    end
    local chosen, best, besttie
    if policy == "OPT" then
        for _, i in ipairs(candidates) do
            local page = self.frames[i]
            local pos = math.huge
            for j = self.cursor + 1, #self.refs do
                local ref = self.refs[j]
                if ref[1] == page.pid and ref[3] // self.c.page == page.p then
                    pos = j
                    break
                end
            end
            if not chosen or pos > best then
                chosen, best = i, pos
            end
        end
        return chosen
    end
    local field = ({FIFO = "load", LRU = "last", LFU = "uses", AGING = "age"})[policy]
    if field or policy == "NRU" then
        for _, i in ipairs(candidates) do
            local p = self.frames[i]
            local value = field and p[field] or 2 * p.r + p.m
            local tie = policy == "NRU" and i or p.load
            if chosen == nil or value < best or (value == best and tie < besttie) then
                chosen, best, besttie = i, value, tie
            end
        end
        return chosen
    end
    local hand = self.c.scope == "GLOBAL" and self.hand or self.procs[pid].hand
    table.sort(
        candidates,
        function(a, b)
            return (a - hand) % self.c.frames < (b - hand) % self.c.frames
        end
    )
    if policy == "CLOCK" then
        while chosen == nil do
            for _, i in ipairs(candidates) do
                local p = self.frames[i]
                if p.r == 0 then
                    chosen = i
                    break
                end
                p.r = 0
            end
        end
    elseif policy == "ECLOCK" then
        while chosen == nil do
            for _, i in ipairs(candidates) do
                local p = self.frames[i]
                if p.r == 0 and p.m == 0 then
                    chosen = i
                    break
                end
            end
            if chosen == nil then
                for _, i in ipairs(candidates) do
                    local p = self.frames[i]
                    if p.r == 0 and p.m == 1 then
                        chosen = i
                        break
                    end
                    p.r = 0
                end
            end
        end
    else
        for _, i in ipairs(candidates) do
            local p = self.frames[i]
            if p.r == 1 then
                p.r, p.last = 0, self.time
            elseif self.time - p.last > self.c.tau then
                if p.m == 0 then
                    chosen = i
                    break
                end
                self:writeback(p)
            end
        end
        if chosen == nil then
            for _, i in ipairs(candidates) do
                if self.frames[i].m == 0 then
                    chosen = i
                    break
                end
            end
            chosen = chosen or candidates[1]
        end
    end
    if self.c.scope == "GLOBAL" then
        self.hand = (chosen + 1) % self.c.frames
    else
        self.procs[pid].hand = (chosen + 1) % self.c.frames
    end
    return chosen
end
function Sim:access(pid, op, addr, silent)
    self.fixed = true
    self.cursor = self.cursor + 1
    local proc = self:process(pid)
    if addr >= #proc.pages * self.c.page then
        proc.segfaults = proc.segfaults + 1
        if not silent then
            emit("SEGFAULT P" .. pid .. " " .. hex(addr))
        end
        return
    end
    local page = proc.pages[addr // self.c.page + 1]
    if op == "W" and page.ro then
        proc.protfaults = proc.protfaults + 1
        if not silent then
            emit("PROTFAULT P" .. pid .. " " .. hex(addr))
        end
        return
    end
    self.events[#self.events + 1] = {"access", pid, op, addr}
    self.time = self.time + 1
    proc.accesses = proc.accesses + 1
    proc.refs[#proc.refs + 1] = page.p
    local switched = self.previous ~= nil and self.previous ~= pid
    if switched then
        self.switches = self.switches + 1
        if self.c.asid == "OFF" then
            for i = 1, self.c.sets do
                self.tlb[i] = {}
            end
        end
    end
    self.previous = pid
    local set = self.tlb[page.p % self.c.sets + 1]
    local hit = contains(set, page)
    local fault, victim, wrote, result = false, nil, false, nil
    if hit then
        result = "TLBHIT"
        self.tlbhits = self.tlbhits + 1
        table.remove(set, hit)
    else
        if page.frame ~= nil then
            result = "HIT"
        else
            fault = true
            self.faults = self.faults + 1
            proc.faults = proc.faults + 1
            if page.slot ~= nil then
                self.swapin = self.swapin + 1
                result = "FAULT SWAPIN"
            else
                self.zero = self.zero + 1
                result = "FAULT ZERO"
            end
            local free
            for i = 0, self.c.frames - 1 do
                if not self.frames[i] then
                    free = i
                    break
                end
            end
            local usefree
            if self.c.scope == "GLOBAL" then
                usefree = free ~= nil
            else
                usefree = self:resident(pid) < self:quota(pid)
            end
            local frame = usefree and free or self:victim(pid)
            victim = self.frames[frame]
            if victim then
                self:invalidate(victim)
                wrote = victim.m == 1
                if wrote then
                    self:writeback(victim)
                end
                victim.frame = nil
            end
            self.frames[frame] = page
            page.frame, page.load, page.uses, page.m, page.age = frame, self.time, 0, 0, 0
            proc.peak = math.max(proc.peak, self:resident(pid))
        end
        if #set == self.c.tlb // self.c.sets then
            table.remove(set, 1)
        end
    end
    set[#set + 1] = page
    page.r = 1
    if op == "W" then
        page.m = 1
    end
    page.last, page.uses, page.ever = self.time, page.uses + 1, true
    self.history[#self.history + 1] = fault
    local tick = self.c.tick > 0 and self.time % self.c.tick == 0
    if tick then
        for i = 0, self.c.frames - 1 do
            local p = self.frames[i]
            if p then
                p.age, p.r = p.age // 2 + 128 * p.r, 0
            end
        end
    end
    if self.trace and not silent then
        local line =
            "t=" ..
            self.time ..
                " P" ..
                    pid ..
                        " " ..
                            op ..
                                " " ..
                                    hex(addr) ..
                                        " page=" ..
                                            page.p ..
                                                " frame=" ..
                                                    page.frame ..
                                                        " phys=" ..
                                                            hex(
                                                                page.frame * self.c.page +
                                                                    addr % self.c.page
                                                            ) ..
                                                                " " .. result
        if victim then
            line = line .. " evict=P" .. victim.pid .. ":" .. victim.p
        end
        if wrote then
            line = line .. " writeback"
        end
        if switched then
            line = line .. " switch"
        end
        emit(line)
        if tick then
            emit("t=" .. self.time .. " tick")
        end
    end
end
function Sim:exit(pid, silent)
    local p = self:process(pid)
    local freed, slots = self:resident(pid), 0
    for _, page in ipairs(p.pages) do
        if page.frame ~= nil then
            self.frames[page.frame] = nil
        end
        page.frame = nil
        self:invalidate(page)
        if page.slot ~= nil then
            self.swap[page.slot] = nil
            page.slot = nil
            slots = slots + 1
        end
    end
    p.exited = true
    self.events[#self.events + 1] = {"exit", pid}
    if not silent then
        emit("EXIT P" .. pid .. " freed=" .. freed .. " slots=" .. slots)
    end
end
function Sim:attributes(cmd, pid, first, last, protection)
    local proc = self:process(pid)
    if first > last or last >= #proc.pages then
        fail("invalid page range")
    end
    for i = first, last do
        if cmd == "PROTECT" then
            proc.pages[i + 1].ro = protection == "RO"
        else
            proc.pages[i + 1].locked = cmd == "LOCK"
        end
    end
    if cmd ~= "PROTECT" then
        self.events[#self.events + 1] = {"attribute", cmd, pid, first, last}
    end
end
function Sim:clean(silent)
    local count = 0
    for i = 0, self.c.frames - 1 do
        local p = self.frames[i]
        if p and p.m == 1 then
            self:writeback(p)
            count = count + 1
        end
    end
    self.events[#self.events + 1] = {"clean"}
    if not silent then
        emit("CLEAN written=" .. count)
    end
end
function Sim:rerun(policy, frames)
    local c = {}
    for k, v in pairs(self.c) do
        c[k] = v
    end
    c.policy, c.frames = policy, frames
    local refs = {}
    for _, e in ipairs(self.events) do
        if e[1] == "access" then
            refs[#refs + 1] = {e[2], e[3], e[4]}
        end
    end
    local s = Sim:new(c, refs)
    for _, pid in ipairs(sortedkeys(self.procs)) do
        s:declare(pid, #self.procs[pid].pages)
    end
    for _, e in ipairs(self.events) do
        if e[1] == "access" then
            s:access(e[2], e[3], e[4], true)
        elseif e[1] == "exit" then
            s:exit(e[2], true)
        elseif e[1] == "clean" then
            s:clean(true)
        else
            s:attributes(e[2], e[3], e[4], e[5])
        end
    end
    return s
end
function Sim:command(w)
    local cmd, pid = w[1], tonumber(w[2])
    if cmd == "PROCESS" then
        self:declare(pid, tonumber(w[3]))
    elseif cmd == "EXIT" then
        self:exit(pid)
    elseif cmd == "PROTECT" or cmd == "LOCK" or cmd == "UNLOCK" then
        self:attributes(cmd, pid, tonumber(w[3]), tonumber(w[4]), w[5])
    elseif cmd == "TRACE" then
        self.trace = w[2] == "ON"
    elseif cmd == "CLEAN" then
        self:clean()
    elseif cmd == "SUMMARY" then
        emit(
            "SUMMARY policy=" .. self.c.policy .. " scope=" .. self.c.scope .. " time=" .. self.time
        )
        local seg, prot = 0, 0
        for _, p in pairs(self.procs) do
            seg = seg + p.segfaults
            prot = prot + p.protfaults
        end
        emit(
            "total faults=" ..
                self.faults ..
                    " zero=" ..
                        self.zero ..
                            " swapin=" ..
                                self.swapin ..
                                    " faultrate=" ..
                                        ratio(self.faults, self.time) ..
                                            " tlbhits=" ..
                                                self.tlbhits ..
                                                    " tlbrate=" ..
                                                        ratio(self.tlbhits, self.time) ..
                                                            " writebacks=" ..
                                                                self.writebacks ..
                                                                    " switches=" ..
                                                                        self.switches ..
                                                                            " segfaults=" ..
                                                                                seg ..
                                                                                    " protfaults=" ..
                                                                                        prot
        )
        for _, id in ipairs(sortedkeys(self.procs)) do
            local p = self.procs[id]
            local line =
                "P" ..
                id ..
                    " accesses=" ..
                        p.accesses ..
                            " faults=" ..
                                p.faults ..
                                    " writebacks=" ..
                                        p.writebacks ..
                                            " segfaults=" ..
                                                p.segfaults ..
                                                    " protfaults=" ..
                                                        p.protfaults ..
                                                            " resident=" ..
                                                                self:resident(id) ..
                                                                    " peak=" .. p.peak
            if self.c.scope == "LOCAL" then
                line = line .. " quota=" .. self:quota(id)
            end
            if p.exited then
                line = line .. " exited"
            end
            emit(line)
        end
    elseif cmd == "FRAMES" then
        local count = 0
        for i = 0, self.c.frames - 1 do
            if self.frames[i] then
                count = count + 1
            end
        end
        emit("FRAMES used=" .. count .. "/" .. self.c.frames)
        for i = 0, self.c.frames - 1 do
            local p = self.frames[i]
            if p then
                emit(
                    i ..
                        " P" ..
                            p.pid ..
                                ":" ..
                                    p.p ..
                                        " R=" ..
                                            p.r ..
                                                " M=" ..
                                                    p.m ..
                                                        " load=" ..
                                                            p.load ..
                                                                " last=" ..
                                                                    p.last ..
                                                                        " uses=" ..
                                                                            p.uses ..
                                                                                " age=" ..
                                                                                    p.age ..
                                                                                        (p.locked and
                                                                                            " locked" or
                                                                                            "")
                )
            else
                emit(i .. " free")
            end
        end
        if self.c.policy == "CLOCK" or self.c.policy == "ECLOCK" or self.c.policy == "WSCLOCK" then
            if self.c.scope == "GLOBAL" then
                emit("hand=" .. self.hand)
            else
                local line = "hand"
                for _, id in ipairs(sortedkeys(self.procs)) do
                    line = line .. " P" .. id .. "=" .. self.procs[id].hand
                end
                emit(line)
            end
        end
    elseif cmd == "PAGETABLE" then
        local p = self:process(pid)
        emit("PAGETABLE P" .. pid .. " pages=" .. #p.pages .. " resident=" .. self:resident(pid))
        for _, page in ipairs(p.pages) do
            if page.ever then
                local state = "zero"
                if page.frame ~= nil then
                    state = "frame=" .. page.frame .. " R=" .. page.r .. " M=" .. page.m
                elseif page.slot ~= nil then
                    state = "swap=" .. page.slot
                end
                emit(
                    page.p ..
                        " " ..
                            state .. (page.ro and " RO" or "") .. (page.locked and " locked" or "")
                )
            end
        end
    elseif cmd == "TLB" then
        local count = 0
        for _, set in ipairs(self.tlb) do
            count = count + #set
        end
        emit("TLB used=" .. count .. "/" .. self.c.tlb .. " sets=" .. self.c.sets)
        for i, set in ipairs(self.tlb) do
            local line = "set " .. (i - 1) .. ":"
            for j = #set, 1, -1 do
                local p = set[j]
                line = line .. " P" .. p.pid .. ":" .. p.p .. "->" .. p.frame
            end
            emit(line)
        end
    elseif cmd == "SWAP" then
        local slots = sortedkeys(self.swap)
        emit("SWAP used=" .. #slots)
        for _, slot in ipairs(slots) do
            local p = self.swap[slot]
            emit(slot .. " P" .. p.pid .. ":" .. p.p)
        end
    elseif cmd == "COMPARE" then
        emit("COMPARE accesses=" .. self.time .. " frames=" .. self.c.frames)
        local results = {}
        for i, policy in ipairs(policies) do
            local s = self:rerun(policy, self.c.frames)
            emit(
                policy ..
                    " faults=" ..
                        s.faults .. " writebacks=" .. s.writebacks .. " tlbhits=" .. s.tlbhits
            )
            results[#results + 1] = {
                policy = policy,
                faults = s.faults,
                writes = s.writebacks,
                order = i
            }
        end
        table.sort(
            results,
            function(a, b)
                if a.faults ~= b.faults then
                    return a.faults < b.faults
                end
                if a.writes ~= b.writes then
                    return a.writes < b.writes
                end
                return a.order < b.order
            end
        )
        local line = "ranking"
        for _, r in ipairs(results) do
            line = line .. " " .. r.policy
        end
        emit(line)
    elseif cmd == "CURVE" then
        local policy, lo, hi = w[2], tonumber(w[3]), tonumber(w[4])
        if not contains(policies, policy) then
            fail("unknown policy")
        end
        if
            lo < 1 or lo > hi or hi > 16 or
                (self.c.scope == "LOCAL" and lo < #sortedkeys(self.procs))
         then
            fail("invalid frame range")
        end
        emit("CURVE " .. policy .. " frames=" .. lo .. ".." .. hi)
        local previous
        for f = lo, hi do
            local faults = self:rerun(policy, f).faults
            emit(
                "F=" ..
                    f ..
                        " faults=" ..
                            faults .. (previous and faults > previous and " ANOMALY" or "")
            )
            previous = faults
        end
    elseif cmd == "EAT" then
        if self.time == 0 then
            emit("EAT accesses=0")
        else
            local total =
                tonumber(w[2]) * self.time + tonumber(w[3]) * (2 * self.time - self.tlbhits) +
                tonumber(w[4]) * (self.swapin + self.writebacks)
            local v = 100 * total // self.time
            emit(
                "EAT accesses=" ..
                    self.time ..
                        " total=" ..
                            total .. " average=" .. string.format("%d.%02d", v // 100, v % 100)
            )
        end
    elseif cmd == "TIMELINE" then
        local window = pid
        if window < 1 then
            fail("invalid window")
        end
        local line = "TIMELINE window=" .. window
        for i = 1, #self.history, window do
            local count = 0
            for j = i, math.min(i + window - 1, #self.history) do
                if self.history[j] then
                    count = count + 1
                end
            end
            line = line .. " " .. count
        end
        emit(line)
    elseif cmd == "WSET" or cmd == "HOT" then
        local p = self:process(pid)
        local n = tonumber(w[3])
        if n < 1 then
            fail(cmd == "WSET" and "invalid window" or "invalid count")
        end
        local counts = {}
        local first = cmd == "WSET" and math.max(1, #p.refs - n + 1) or 1
        for i = first, #p.refs do
            counts[p.refs[i]] = (counts[p.refs[i]] or 0) + 1
        end
        local pages = sortedkeys(counts)
        if cmd == "WSET" then
            local line = "WSET P" .. pid .. " window=" .. n .. " size=" .. #pages
            for _, page in ipairs(pages) do
                line = line .. " " .. page
            end
            emit(line)
        else
            table.sort(
                pages,
                function(a, b)
                    if counts[a] ~= counts[b] then
                        return counts[a] > counts[b]
                    end
                    return a < b
                end
            )
            local line = "HOT P" .. pid
            for i = 1, math.min(n, #pages) do
                local page = pages[i]
                line = line .. " " .. page .. ":" .. counts[page]
            end
            emit(line)
        end
    else
        self:access(tonumber(w[1]), w[2], tonumber(w[3]))
    end
end
local function settings(w)
    local c, seen = {}, {}
    for k, v in pairs(defaults) do
        c[k] = v
    end
    for i = 2, #w do
        local k, value = w[i]:match("^([^=]+)=(.*)$")
        if c[k] == nil then
            fail("unknown key " .. k)
        end
        if seen[k] then
            fail("duplicate key " .. k)
        end
        seen[k] = true
        local valid, n = false, tonumber(value)
        if k == "policy" then
            valid = contains(policies, value) ~= nil
        elseif k == "scope" then
            valid = value == "GLOBAL" or value == "LOCAL"
        elseif k == "asid" then
            valid = value == "ON" or value == "OFF"
        elseif k == "page" then
            valid = n >= 16 and n <= 4096 and (n & (n - 1)) == 0
        else
            local ranges = {
                frames = {1, 16},
                tlb = {1, 8},
                sets = {1, 8},
                tick = {0, 1000},
                tau = {1, 1000},
                seed = {1, 2147483646}
            }
            valid = n >= ranges[k][1] and n <= ranges[k][2]
        end
        if not valid then
            fail("invalid " .. k)
        end
        c[k] = n or value
    end
    if c.tlb % c.sets ~= 0 then
        fail("invalid sets")
    end
    return c
end
local commands = {}
local function add(pid, op, addr)
    commands[#commands + 1] = {tostring(pid), op, hex(addr)}
end
local n = tonumber(io.read())
for _ = 1, n do
    local w = {}
    for word in io.read():gmatch("%S+") do
        w[#w + 1] = word
    end
    if w[1] == "LOOP" then
        for _ = 1, tonumber(w[7]) do
            for i = 0, tonumber(w[6]) - 1 do
                add(w[2], w[3], tonumber(w[4]) + i * tonumber(w[5]))
            end
        end
    elseif w[1] == "RAND" then
        local lo, hi, x = tonumber(w[3]), tonumber(w[4]), tonumber(w[6])
        for _ = 1, tonumber(w[5]) do
            x = 48271 * x % 2147483647
            local addr = lo + x % (hi - lo)
            x = 48271 * x % 2147483647
            add(w[2], x % 100 < tonumber(w[7]) and "W" or "R", addr)
        end
    else
        commands[#commands + 1] = w
    end
end
local sim
for i, w in ipairs(commands) do
    local ok, err =
        pcall(
        function()
            if w[1] == "SYSTEM" then
                sim = nil
                local c = settings(w)
                local refs = {}
                for j = i + 1, #commands do
                    local q = commands[j]
                    if q[1] == "SYSTEM" then
                        break
                    end
                    if q[1]:match("^%d") then
                        refs[#refs + 1] = {tonumber(q[1]), q[2], tonumber(q[3])}
                    end
                end
                sim = Sim:new(c, refs)
                local parts = {"SYSTEM"}
                for _, key in ipairs(keys) do
                    parts[#parts + 1] = key .. "=" .. c[key]
                end
                emit(table.concat(parts, " "))
            elseif sim then
                sim:command(w)
            else
                emit("ERROR no system")
            end
        end
    )
    if not ok then
        emit("ERROR " .. err)
    end
end
