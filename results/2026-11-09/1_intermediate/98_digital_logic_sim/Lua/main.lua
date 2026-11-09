local types = {"AND", "OR", "NAND", "NOR", "XOR", "XNOR", "NOT", "BUF", "MUX2", "DFF"}
local counts = {
    BUILD = 1,
    RESET = 0,
    SET = 3,
    APPLY = 2,
    PULSE = 3,
    CLOCK = 4,
    RUN = 1,
    WATCH = 1,
    UNWATCH = 1,
    SHOW = 0,
    CHECK = 2,
    PROBE = 1,
    WAVE = 2,
    HISTORY = 1,
    ACTIVITY = 1,
    STATUS = 0,
    MODULES = 0,
    NETLIST = 1,
    HIERARCHY = 1,
    STATS = 1,
    TRUTHTABLE = 1,
    EQUIV = 2,
    FAULTS = 1,
    CRITICAL = 1,
    PERIOD = 1
}
local function fail(s)
    error(s, 0)
end
local function emit(s)
    io.write(s, "\n")
end
local function has(a, x)
    for _, v in ipairs(a) do
        if v == x then
            return true
        end
    end
    return false
end
local function words(s)
    local a = {}
    for w in s:gmatch("%S+") do
        a[#a + 1] = w
    end
    return a
end
local function slice(a, first, last)
    local b = {}
    for i = first, last or #a do
        b[#b + 1] = a[i]
    end
    return b
end
local function nameOK(s)
    return #s <= 16 and s:match("^[a-z][a-z0-9_]*$") ~= nil
end
local function numberOK(s)
    return #s <= 9 and s:match("^%d+$") and (#s == 1 or s:sub(1, 1) ~= "0")
end
local function number(s, positive)
    if not numberOK(s) or positive and s == "0" then
        fail("bad number " .. s)
    end
    return tonumber(s)
end
local function value(s)
    if not has({"0", "1", "X"}, s) then
        fail("bad value " .. s)
    end
    return s
end
local function bits(r, n)
    local b = ""
    for i = 1, n do
        b = b .. ((r >> (n - i)) & 1)
    end
    return b
end
local function logic(k, a)
    local y = a[1]
    if k == "AND" or k == "NAND" then
        y = has(a, "0") and "0" or has(a, "X") and "X" or "1"
    elseif k == "OR" or k == "NOR" then
        y = has(a, "1") and "1" or has(a, "X") and "X" or "0"
    elseif k == "XOR" or k == "XNOR" then
        local n = 0
        for _, v in ipairs(a) do
            if v == "1" then
                n = n + 1
            end
        end
        y = has(a, "X") and "X" or tostring(n % 2)
    elseif k == "MUX2" then
        y = a[1] == "X" and (a[2] == a[3] and a[2] or "X") or a[a[1] == "0" and 2 or 3]
    end
    if has({"NAND", "NOR", "XNOR", "NOT"}, k) then
        y = ({["0"] = "1", ["1"] = "0", X = "X"})[y]
    end
    return y
end
local Circuit = {}
Circuit.__index = Circuit
function Circuit.new(m)
    local c =
        setmetatable(
        {
            name = m.name,
            inputs = m.inputs,
            outputs = m.outputs,
            gates = {},
            signals = {},
            driver = {},
            readers = {},
            flops = {},
            order = {}
        },
        Circuit
    )
    local function expand(m, p, ports)
        local function actual(s)
            return ports[s] or p .. s
        end
        for _, x in ipairs(m.body) do
            if x.kind then
                local ins = {}
                for _, s in ipairs(x.inputs) do
                    ins[#ins + 1] = actual(s)
                end
                c.gates[#c.gates + 1] = {
                    name = p .. x.name,
                    kind = x.kind,
                    inputs = ins,
                    output = actual(x.output),
                    delay = x.delay
                }
            else
                local mapping = {}
                for _, v in ipairs(x.connections) do
                    mapping[v[1]] = actual(v[2])
                end
                expand(x.module, p .. x.name .. ".", mapping)
            end
        end
    end
    expand(m, "", {})
    for _, s in ipairs(c.inputs) do
        c.signals[#c.signals + 1] = s
    end
    for _, g in ipairs(c.gates) do
        c.signals[#c.signals + 1] = g.output
        c.driver[g.output] = g
        if g.kind == "DFF" then
            c.flops[#c.flops + 1] = g
        end
    end
    for _, s in ipairs(c.signals) do
        c.readers[s] = {}
    end
    for _, g in ipairs(c.gates) do
        local seen = {}
        for _, s in ipairs(g.inputs) do
            if not seen[s] then
                local a = c.readers[s]
                a[#a + 1] = g
                seen[s] = true
            end
        end
    end
    local waiting, ready = {}, {}
    local needed = 0
    for _, g in ipairs(c.gates) do
        if g.kind ~= "DFF" then
            needed = needed + 1
            local seen = {}
            local n = 0
            for _, s in ipairs(g.inputs) do
                if c.driver[s] and c.driver[s].kind ~= "DFF" and not seen[s] then
                    n = n + 1
                    seen[s] = true
                end
            end
            waiting[g] = n
            if n == 0 then
                ready[#ready + 1] = g
            end
        end
    end
    while #ready > 0 do
        local g = table.remove(ready)
        c.order[#c.order + 1] = g
        for _, r in ipairs(c.readers[g.output]) do
            if r.kind ~= "DFF" then
                waiting[r] = waiting[r] - 1
                if waiting[r] == 0 then
                    ready[#ready + 1] = r
                end
            end
        end
    end
    c.loop = #c.order ~= needed
    return c
end
function Circuit:combinational()
    if #self.flops > 0 then
        fail(self.name .. " is not combinational")
    end
    if self.loop then
        fail(self.name .. " has a combinational loop")
    end
    if #self.inputs > 8 then
        fail("too many inputs " .. #self.inputs)
    end
end
function Circuit:evaluate(b, stuck, v)
    local values = {}
    for i, s in ipairs(self.inputs) do
        values[s] = s == stuck and v or b:sub(i, i)
    end
    for _, g in ipairs(self.order) do
        local a = {}
        for _, s in ipairs(g.inputs) do
            a[#a + 1] = values[s]
        end
        values[g.output] = g.output == stuck and v or logic(g.kind, a)
    end
    local out = ""
    for _, s in ipairs(self.outputs) do
        out = out .. values[s]
    end
    return out
end
function Circuit:arrivals(period)
    local late, early, prev = {}, {}, {}
    if period then
        for _, g in ipairs(self.flops) do
            late[g.output] = g.delay
            early[g.output] = g.delay
        end
    else
        for _, s in ipairs(self.inputs) do
            late[s] = 0
            early[s] = 0
        end
    end
    for _, g in ipairs(self.order) do
        local best, minimum
        for _, s in ipairs(g.inputs) do
            if late[s] then
                if not best then
                    best = s
                    minimum = early[s]
                elseif late[s] > late[best] then
                    best = s
                end
                minimum = math.min(minimum, early[s])
            end
        end
        if best then
            late[g.output] = late[best] + g.delay
            early[g.output] = minimum + g.delay
            prev[g.output] = best
        end
    end
    return late, early, prev
end
local Simulation = {}
Simulation.__index = Simulation
function Simulation.new(c)
    local s = setmetatable({c = c, watch = {}}, Simulation)
    s:reset()
    return s
end
function Simulation:reset()
    self.values = {}
    self.history = {}
    for _, s in ipairs(self.c.signals) do
        self.values[s] = "X"
        self.history[s] = {}
    end
    self.time = 0
    self.sequence = 0
    self.processed = 0
    self.queue = {}
    self.halted = false
end
local function before(a, b)
    return a.t < b.t or a.t == b.t and a.id < b.id
end
function Simulation:schedule(t, s, v)
    local e = {t = t, s = s, v = v, id = self.sequence}
    self.sequence = self.sequence + 1
    local i = #self.queue + 1
    while i > 1 do
        local p = i // 2
        if not before(e, self.queue[p]) then
            break
        end
        self.queue[i] = self.queue[p]
        i = p
    end
    self.queue[i] = e
end
function Simulation:pop()
    local result = self.queue[1]
    local last = table.remove(self.queue)
    if #self.queue > 0 then
        local i = 1
        while 2 * i <= #self.queue do
            local j = 2 * i
            if j + 1 <= #self.queue and before(self.queue[j + 1], self.queue[j]) then
                j = j + 1
            end
            if not before(self.queue[j], last) then
                break
            end
            self.queue[i] = self.queue[j]
            i = j
        end
        self.queue[i] = last
    end
    return result
end
function Simulation:describe(a)
    local b = {}
    for _, s in ipairs(a) do
        b[#b + 1] = s .. "=" .. self.values[s]
    end
    return b
end
function Simulation:run(ending)
    local total, glitches = 0, 0
    while #self.queue > 0 and self.queue[1].t < ending do
        local t = self.queue[1].t
        local original = {}
        local count = 0
        while #self.queue > 0 and self.queue[1].t == t do
            if count == 1000 then
                emit("halted: oscillation at time " .. t)
                self.queue = {}
                self.time = t
                self.halted = true
                return
            end
            local e = self:pop()
            count = count + 1
            self.processed = self.processed + 1
            local old = self.values[e.s]
            if old ~= e.v then
                original[e.s] = original[e.s] or old
                self.values[e.s] = e.v
                for _, g in ipairs(self.c.readers[e.s]) do
                    if g.kind ~= "DFF" then
                        local a = {}
                        for _, s in ipairs(g.inputs) do
                            a[#a + 1] = self.values[s]
                        end
                        self:schedule(t + g.delay, g.output, logic(g.kind, a))
                    elseif e.s == g.inputs[1] and old == "0" and e.v == "1" then
                        self:schedule(t + g.delay, g.output, self.values[g.inputs[2]])
                    end
                end
            end
        end
        total = total + count
        for s, v in pairs(original) do
            if self.values[s] == v then
                glitches = glitches + 1
            else
                local h = self.history[s]
                h[#h + 1] = {t, self.values[s]}
            end
        end
        for _, s in ipairs(self.watch) do
            if original[s] and original[s] ~= self.values[s] then
                emit(t .. " " .. s .. " " .. self.values[s])
            end
        end
    end
    self.time = ending
    emit(
        "run " ..
            ending .. " events " .. total .. " glitches " .. glitches .. " pending " .. #self.queue
    )
end
local Simulator = {}
Simulator.__index = Simulator
function Simulator.new()
    return setmetatable({modules = {}, order = {}}, Simulator)
end
function Simulator:lookup(s)
    if not self.modules[s] then
        fail("unknown module " .. s)
    end
    return self.modules[s]
end
function Simulator:signal(s)
    if not self.sim.values[s] then
        fail("unknown signal " .. s)
    end
end
function Simulator:input(s)
    if not has(self.sim.c.inputs, s) then
        fail("not an input " .. s)
    end
end
function Simulator:time(w)
    local t = number(w)
    if t < self.sim.time then
        fail("time " .. t .. " is in the past")
    end
    return t
end
function Simulator:define(header, lines)
    local line = header
    local ok, reason =
        pcall(
        function()
            local w = words(lines[1])
            local outs, split = 0, 0
            for i = 4, #w do
                if w[i] == "OUT" then
                    outs = outs + 1
                    split = i
                end
            end
            if #w < 5 or w[3] ~= "IN" or outs ~= 1 or w[#w] == "OUT" then
                fail("bad module header")
            end
            local name = w[2]
            if #name > 16 or not name:match("^[A-Z][A-Z0-9_]*$") then
                fail("bad module name " .. name)
            end
            if self.modules[name] then
                fail("duplicate module " .. name)
            end
            local ins, outputs = slice(w, 4, split - 1), slice(w, split + 1)
            local seen = {}
            for i = 4, #w do
                if i ~= split then
                    local p = w[i]
                    if not nameOK(p) then
                        fail("bad name " .. p)
                    end
                    if seen[p] then
                        fail("duplicate port " .. p)
                    end
                    seen[p] = true
                end
            end
            local driven, used, body, reads = {}, {}, {}, {}
            for _, s in ipairs(ins) do
                driven[s] = true
            end
            local gates = 0
            for i = 2, #lines do
                line = header + i - 1
                local a = words(lines[i])
                local kind = a[1]
                if has(types, kind) then
                    local arrows = 0
                    for _, x in ipairs(a) do
                        if x == "->" then
                            arrows = arrows + 1
                        end
                    end
                    if #a < 5 or a[#a - 2] ~= "->" or arrows ~= 1 then
                        fail("bad gate syntax")
                    end
                    local n = a[2]
                    if not nameOK(n) then
                        fail("bad name " .. n)
                    end
                    local inputs, output, delay = slice(a, 3, #a - 3), a[#a - 1], a[#a]
                    local low = (kind == "NOT" or kind == "BUF") and 1 or kind == "MUX2" and 3 or 2
                    local high = has({"AND", "OR", "NAND", "NOR", "XOR", "XNOR"}, kind) and 8 or low
                    if #inputs < low or #inputs > high then
                        fail("bad input count " .. #inputs .. " for " .. kind)
                    end
                    for _, s in ipairs(inputs) do
                        if not nameOK(s) then
                            fail("bad name " .. s)
                        end
                    end
                    if not nameOK(output) then
                        fail("bad name " .. output)
                    end
                    if not numberOK(delay) or tonumber(delay) > 1000 then
                        fail("bad delay " .. delay)
                    end
                    if used[n] then
                        fail("duplicate name " .. n)
                    end
                    if driven[output] then
                        fail("multiple drivers for " .. output)
                    end
                    used[n] = true
                    driven[output] = true
                    gates = gates + 1
                    body[#body + 1] = {
                        name = n,
                        kind = kind,
                        inputs = inputs,
                        output = output,
                        delay = tonumber(delay)
                    }
                    for _, s in ipairs(inputs) do
                        reads[#reads + 1] = {line, s}
                    end
                elseif kind == "INST" then
                    if #a < 3 then
                        fail("bad instance syntax")
                    end
                    local n = a[2]
                    if not nameOK(n) then
                        fail("bad name " .. n)
                    end
                    local m = self:lookup(a[3])
                    local connections, seen = {}, {}
                    for j = 4, #a do
                        local word = a[j]
                        local p, s = word:match("^([^=]+)=([^=]+)$")
                        if not p then
                            fail("bad connection " .. word)
                        end
                        if not has(m.inputs, p) and not has(m.outputs, p) then
                            fail("unknown port " .. p)
                        end
                        if seen[p] then
                            fail("duplicate connection " .. p)
                        end
                        if not nameOK(s) then
                            fail("bad name " .. s)
                        end
                        seen[p] = true
                        connections[#connections + 1] = {p, s}
                    end
                    for _, p in ipairs(m.inputs) do
                        if not seen[p] then
                            fail("unconnected input " .. p)
                        end
                    end
                    if used[n] then
                        fail("duplicate name " .. n)
                    end
                    for _, v in ipairs(connections) do
                        if has(m.outputs, v[1]) then
                            if driven[v[2]] then
                                fail("multiple drivers for " .. v[2])
                            end
                            driven[v[2]] = true
                        end
                    end
                    used[n] = true
                    body[#body + 1] = {name = n, module = m, connections = connections}
                    for _, v in ipairs(connections) do
                        if has(m.inputs, v[1]) then
                            reads[#reads + 1] = {line, v[2]}
                        end
                    end
                else
                    fail("unknown statement " .. kind)
                end
            end
            for _, s in ipairs(outputs) do
                reads[#reads + 1] = {header, s}
            end
            for _, r in ipairs(reads) do
                if not driven[r[2]] then
                    line = r[1]
                    fail("undriven signal " .. r[2])
                end
            end
            local m = {name = name, inputs = ins, outputs = outputs, body = body}
            self.modules[name] = m
            self.order[#self.order + 1] = m
            emit(
                "defined " ..
                    name ..
                        " inputs " ..
                            #ins ..
                                " outputs " ..
                                    #outputs ..
                                        " gates " .. gates .. " instances " .. (#body - gates)
            )
        end
    )
    if not ok then
        emit("error: line " .. line .. ": " .. reason)
    end
end
function Simulator:hierarchy(m, depth)
    for _, x in ipairs(m.body) do
        if not x.kind then
            emit(string.rep("  ", depth) .. x.name .. " " .. x.module.name)
            self:hierarchy(x.module, depth + 1)
        end
    end
end
function Simulator:execute(line, w)
    local ok, reason =
        pcall(
        function()
            local cmd = w[1]
            local a = slice(w, 2)
            local n = counts[cmd]
            if not n then
                fail("unknown command " .. cmd)
            end
            if #a < n or not has({"WATCH", "UNWATCH", "SHOW"}, cmd) and #a ~= n then
                fail("wrong argument count")
            end
            if
                has(
                    words(
                        "RESET SET APPLY PULSE CLOCK RUN WATCH UNWATCH SHOW CHECK PROBE WAVE HISTORY ACTIVITY STATUS"
                    ),
                    cmd
                ) and not self.sim
             then
                fail("no circuit")
            end
            local s = self.sim
            if has({"SET", "APPLY", "PULSE", "CLOCK", "RUN"}, cmd) and s.halted then
                fail("simulation halted")
            end
            if cmd == "MODULES" then
                emit("modules " .. #self.order)
                for _, m in ipairs(self.order) do
                    emit(
                        m.name ..
                            " inputs " ..
                                #m.inputs ..
                                    " outputs " .. #m.outputs .. " gates " .. #Circuit.new(m).gates
                    )
                end
                return
            end
            if
                has(
                    words("BUILD NETLIST HIERARCHY STATS TRUTHTABLE EQUIV FAULTS CRITICAL PERIOD"),
                    cmd
                )
             then
                local m = self:lookup(a[1])
                local m2
                if cmd == "EQUIV" then
                    m2 = self:lookup(a[2])
                end
                local c = Circuit.new(m)
                if cmd == "BUILD" then
                    self.sim = Simulation.new(c)
                    emit("built " .. c.name .. " signals " .. #c.signals .. " gates " .. #c.gates)
                elseif cmd == "NETLIST" then
                    emit("netlist " .. c.name .. " gates " .. #c.gates .. " signals " .. #c.signals)
                    for _, g in ipairs(c.gates) do
                        emit(
                            g.name ..
                                " " ..
                                    g.kind ..
                                        " " ..
                                            table.concat(g.inputs, " ") ..
                                                " -> " .. g.output .. " " .. g.delay
                        )
                    end
                elseif cmd == "HIERARCHY" then
                    emit(c.name)
                    self:hierarchy(m, 1)
                elseif cmd == "STATS" then
                    local levels = {}
                    local depth = 0
                    for _, g in ipairs(c.order) do
                        local v = 0
                        for _, x in ipairs(g.inputs) do
                            v = math.max(v, levels[x] or 0)
                        end
                        levels[g.output] = v + 1
                        depth = math.max(depth, v + 1)
                    end
                    emit(
                        "stats " ..
                            c.name ..
                                " gates " ..
                                    #c.gates ..
                                        " signals " ..
                                            #c.signals .. " depth " .. (c.loop and "-" or depth)
                    )
                    local row = {"types"}
                    for _, t in ipairs(types) do
                        local n = 0
                        for _, g in ipairs(c.gates) do
                            if g.kind == t then
                                n = n + 1
                            end
                        end
                        if n > 0 then
                            row[#row + 1] = t
                            row[#row + 1] = n
                        end
                    end
                    emit(table.concat(row, " "))
                    local best = c.signals[1]
                    for _, x in ipairs(c.signals) do
                        if #c.readers[x] > #c.readers[best] then
                            best = x
                        end
                    end
                    emit("max fanout " .. best .. " " .. #c.readers[best])
                elseif cmd == "CRITICAL" or cmd == "PERIOD" then
                    local period = cmd == "PERIOD"
                    if period and #c.flops == 0 then
                        fail(c.name .. " has no flip-flops")
                    end
                    if c.loop then
                        fail(c.name .. " has a combinational loop")
                    end
                    local late, early, prev = c:arrivals(period)
                    local ends = c.outputs
                    local heading = "critical"
                    if period then
                        ends = {}
                        for _, g in ipairs(c.flops) do
                            ends[#ends + 1] = g.inputs[2]
                        end
                        heading = "flip-flops " .. #c.flops .. " period"
                    end
                    local best
                    for _, x in ipairs(ends) do
                        if not period then
                            emit(
                                late[x] and (x .. " min " .. early[x] .. " max " .. late[x]) or
                                    x .. " unreachable"
                            )
                        end
                        if late[x] and (not best or late[x] > late[best]) then
                            best = x
                        end
                    end
                    if not best then
                        emit(heading .. " none")
                    else
                        local path = {best}
                        while prev[path[1]] do
                            table.insert(path, 1, prev[path[1]])
                        end
                        emit(heading .. " " .. late[best] .. ": " .. table.concat(path, " -> "))
                    end
                else
                    c:combinational()
                    local rows, expected = {}, {}
                    for r = 0, (1 << #c.inputs) - 1 do
                        local b = bits(r, #c.inputs)
                        rows[#rows + 1] = b
                        expected[#expected + 1] = c:evaluate(b)
                    end
                    if cmd == "TRUTHTABLE" then
                        local row = {}
                        for _, x in ipairs(c.inputs) do
                            row[#row + 1] = x
                        end
                        row[#row + 1] = "|"
                        for _, x in ipairs(c.outputs) do
                            row[#row + 1] = x
                        end
                        emit(table.concat(row, " "))
                        for r, b in ipairs(rows) do
                            row = {}
                            for x in b:gmatch(".") do
                                row[#row + 1] = x
                            end
                            row[#row + 1] = "|"
                            for x in expected[r]:gmatch(".") do
                                row[#row + 1] = x
                            end
                            emit(table.concat(row, " "))
                        end
                    elseif cmd == "EQUIV" then
                        local d = Circuit.new(m2)
                        d:combinational()
                        if #c.inputs ~= #d.inputs or #c.outputs ~= #d.outputs then
                            fail("port mismatch")
                        end
                        for r, b in ipairs(rows) do
                            local v = d:evaluate(b)
                            if v ~= expected[r] then
                                emit(
                                    "not equivalent at " .. b .. ": " .. expected[r] .. " vs " .. v
                                )
                                return
                            end
                        end
                        emit("equivalent")
                    else
                        local undetected, tests = {}, {}
                        for _, x in ipairs(c.signals) do
                            for _, v in ipairs({"0", "1"}) do
                                local found
                                for r, b in ipairs(rows) do
                                    if c:evaluate(b, x, v) ~= expected[r] then
                                        found = r
                                        break
                                    end
                                end
                                if found then
                                    tests[found] = true
                                else
                                    undetected[#undetected + 1] = x .. "/" .. v
                                end
                            end
                        end
                        local total = 2 * #c.signals
                        emit("faults " .. total .. " detected " .. (total - #undetected))
                        for _, f in ipairs(undetected) do
                            emit("undetected " .. f)
                        end
                        local row = {"tests"}
                        for r, b in ipairs(rows) do
                            if tests[r] then
                                row[#row + 1] = b
                            end
                        end
                        emit(table.concat(row, " "))
                    end
                end
                return
            end
            if cmd == "RESET" then
                s:reset()
                emit("reset")
            elseif cmd == "SET" then
                local t = self:time(a[1])
                self:input(a[2])
                value(a[3])
                s:schedule(t, a[2], a[3])
                emit("set " .. a[2] .. " " .. a[3] .. " at " .. t)
            elseif cmd == "APPLY" then
                local t = self:time(a[1])
                local b = a[2]
                if #b ~= #s.c.inputs or b:find("[^01X]") then
                    fail("bad vector " .. b)
                end
                for i, x in ipairs(s.c.inputs) do
                    s:schedule(t, x, b:sub(i, i))
                end
                emit("apply " .. b .. " at " .. t)
            elseif cmd == "PULSE" or cmd == "CLOCK" then
                self:input(a[1])
                local t = self:time(a[2])
                local width = number(a[3], true)
                if cmd == "PULSE" then
                    s:schedule(t, a[1], "1")
                    s:schedule(t + width, a[1], "0")
                    emit("pulse " .. a[1] .. " " .. t .. " " .. (t + width))
                else
                    local count = number(a[4], true)
                    for i = 0, count - 1 do
                        s:schedule(t + i * width, a[1], tostring(i % 2))
                    end
                    emit(
                        "clock " ..
                            a[1] .. " events " .. count .. " last " .. (t + (count - 1) * width)
                    )
                end
            elseif cmd == "RUN" then
                local t = number(a[1])
                if t <= s.time then
                    fail("time " .. t .. " is not after " .. s.time)
                end
                s:run(t)
            elseif cmd == "WATCH" or cmd == "UNWATCH" then
                local seen = {}
                for _, x in ipairs(a) do
                    self:signal(x)
                    local watched = has(s.watch, x)
                    if cmd == "WATCH" and (watched or seen[x]) then
                        fail("already watched " .. x)
                    end
                    if cmd == "UNWATCH" and (not watched or seen[x]) then
                        fail("not watched " .. x)
                    end
                    seen[x] = true
                end
                if cmd == "WATCH" then
                    for _, x in ipairs(a) do
                        s.watch[#s.watch + 1] = x
                    end
                else
                    local remaining = {}
                    for _, x in ipairs(s.watch) do
                        if not seen[x] then
                            remaining[#remaining + 1] = x
                        end
                    end
                    s.watch = remaining
                end
                emit("watching " .. (#s.watch > 0 and table.concat(s.watch, " ") or "nothing"))
            elseif cmd == "SHOW" then
                for _, x in ipairs(a) do
                    self:signal(x)
                end
                local row = s:describe(a)
                if #a == 0 then
                    row = s:describe(s.c.inputs)
                    row[#row + 1] = "|"
                    for _, x in ipairs(s:describe(s.c.outputs)) do
                        row[#row + 1] = x
                    end
                end
                emit(table.concat(row, " "))
            elseif cmd == "CHECK" then
                self:signal(a[1])
                value(a[2])
                emit(
                    "check " ..
                        a[1] ..
                            "=" ..
                                a[2] ..
                                    " " ..
                                        (s.values[a[1]] == a[2] and "ok" or
                                            "failed (" .. s.values[a[1]] .. ")")
                )
            elseif cmd == "PROBE" then
                local x = a[1]
                self:signal(x)
                local g = s.c.driver[x]
                emit(
                    x ..
                        "=" ..
                            s.values[x] ..
                                " driven by " ..
                                    (g and
                                        g.name ..
                                            " " ..
                                                g.kind ..
                                                    " " ..
                                                        table.concat(s:describe(g.inputs), " ") ..
                                                            " delay " .. g.delay or
                                        "input")
                )
                local row = {"fanout", #s.c.readers[x]}
                for _, g in ipairs(s.c.readers[x]) do
                    row[#row + 1] = g.name
                end
                emit(table.concat(row, " "))
            elseif cmd == "WAVE" then
                local first, last = number(a[1]), number(a[2])
                if not (first < last and last <= s.time) then
                    fail("bad range " .. first .. " " .. last)
                end
                if #s.watch == 0 then
                    fail("nothing watched")
                end
                for _, x in ipairs(s.watch) do
                    local h = s.history[x]
                    local i, v, wave = 1, "X", {}
                    for t = first, last - 1 do
                        while i <= #h and h[i][1] <= t do
                            v = h[i][2]
                            i = i + 1
                        end
                        wave[#wave + 1] = v
                    end
                    emit(x .. " " .. table.concat(wave))
                end
            elseif cmd == "HISTORY" then
                local x = a[1]
                self:signal(x)
                local h = s.history[x]
                local row = {"history", x, "changes", #h}
                for _, v in ipairs(h) do
                    row[#row + 1] = v[1] .. ":" .. v[2]
                end
                emit(table.concat(row, " "))
            elseif cmd == "ACTIVITY" then
                local k = number(a[1], true)
                local ranked = slice(s.c.signals, 1)
                table.sort(
                    ranked,
                    function(x, y)
                        return #s.history[x] > #s.history[y] or
                            #s.history[x] == #s.history[y] and x < y
                    end
                )
                for i = 1, math.min(k, #ranked) do
                    local x = ranked[i]
                    emit(x .. " " .. #s.history[x])
                end
            elseif cmd == "STATUS" then
                emit(
                    "circuit " ..
                        s.c.name ..
                            " time " ..
                                s.time ..
                                    " pending " ..
                                        #s.queue ..
                                            " events " ..
                                                s.processed ..
                                                    " halted " .. (s.halted and "yes" or "no")
                )
                local n = {["0"] = 0, ["1"] = 0, X = 0}
                for _, v in pairs(s.values) do
                    n[v] = n[v] + 1
                end
                emit("values 0:" .. n["0"] .. " 1:" .. n["1"] .. " X:" .. n.X)
            end
        end
    )
    if not ok then
        emit("error: line " .. line .. ": " .. reason)
    end
end
local lines = {}
for line in io.lines() do
    lines[#lines + 1] = line
end
local simulator = Simulator.new()
local i = 1
while i <= #lines and lines[i] ~= "END" do
    local w = words(lines[i])
    if w[1] == "MODULE" then
        local last = i + 1
        while lines[last] ~= "ENDMODULE" do
            last = last + 1
        end
        simulator:define(i, slice(lines, i, last - 1))
        i = last + 1
    else
        simulator:execute(i, w)
        i = i + 1
    end
end
