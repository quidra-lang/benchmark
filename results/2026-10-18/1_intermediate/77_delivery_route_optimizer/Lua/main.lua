local function number(s) return tonumber(s) end
local function words(s)
    local result = {}
    for word in s:gmatch("[^ ]+") do result[#result + 1] = word end
    return result
end
local function copy(p, first, last)
    local result = {}
    for i = first or 1, last or #p do result[#result + 1] = p[i] end
    return result
end
local function append(a, b)
    local result = copy(a)
    for _, id in ipairs(b) do result[#result + 1] = id end
    return result
end
local function reverse(p, first, last)
    local i, j = first or 1, last or #p
    while i < j do p[i], p[j] = p[j], p[i]; i, j = i + 1, j - 1 end
end
local function place(p, at, values)
    local result = copy(p, 1, at)
    for _, id in ipairs(values) do result[#result + 1] = id end
    for i = at + 1, #p do result[#result + 1] = p[i] end
    return result
end
local function label(id) return id == 0 and "D" or tostring(id) end
local function notation(p)
    local list = {"D"}
    for _, id in ipairs(p) do list[#list + 1] = label(id) end
    list[#list + 1] = "D"
    return table.concat(list, "-")
end
local function clock(s) return number(s:sub(1, 2)) * 60 + number(s:sub(4)) end
local function timeText(t) return string.format("%02d:%02d", t // 60, t % 60) end
local W = {stops={}, start=480, output={}}
function W:emit(format, ...) self.output[#self.output + 1] = string.format(format, ...) end
function W:fail(format, ...) error(string.format("error: " .. format, ...), 0) end
function W:ids()
    local ids = {}
    for id in pairs(self.stops) do ids[#ids + 1] = id end
    table.sort(ids)
    return ids
end
function W:distance(a, b)
    local p, q = a == 0 and self.depot or self.stops[a], b == 0 and self.depot or self.stops[b]
    return math.abs(p.x - q.x) + math.abs(p.y - q.y)
end
function W:length(p)
    local total, last = 0, 0
    for _, id in ipairs(p) do total, last = total + self:distance(last, id), id end
    return total + self:distance(last, 0)
end
function W:load(p)
    local total = 0
    for _, id in ipairs(p) do total = total + self.stops[id].demand end
    return total
end
function W:total()
    local total = 0
    for _, p in ipairs(self.routes) do total = total + self:length(p) end
    return total
end
function W:normalize()
    local result = {}
    for _, p in ipairs(self.routes) do
        if #p > 0 then
            if p[1] > p[#p] then reverse(p) end
            result[#result + 1] = p
        end
    end
    local function minimum(p)
        local value = p[1]
        for _, id in ipairs(p) do value = math.min(value, id) end
        return value
    end
    table.sort(result, function(a, b) return minimum(a) < minimum(b) end)
    self.routes = result
end
function W:routeLines()
    for r, p in ipairs(self.routes) do self:emit("route %d: %s load %d length %d", r, notation(p), self:load(p), self:length(p)) end
end
function W:simulate(p, display)
    local result = {travel=self:length(p), wait=0, service=0, violations=0, lateness=0}
    local t, last = self.start, 0
    for _, id in ipairs(p) do
        local item = self.stops[id]
        local arrival = t + self:distance(last, id)
        local wait = item.open and math.max(0, item.open - arrival) or 0
        local late = item.close and math.max(0, arrival - item.close) or 0
        local begin = arrival + wait
        t, last = begin + item.service, id
        result.wait, result.service, result.lateness = result.wait + wait, result.service + item.service, result.lateness + late
        if late > 0 then result.violations = result.violations + 1 end
        if display then self:emit("%d arrive %s wait %d begin %s leave %s %s", id, timeText(arrival), wait, timeText(begin), timeText(t), late > 0 and "late " .. late or "ok") end
    end
    result.returned = t + self:distance(last, 0)
    if display then self:emit("return %s, travel %d, wait %d, service %d, violations %d, lateness %d", timeText(result.returned), result.travel, result.wait, result.service, result.violations, result.lateness) end
    return result
end
function W:twoopt(p, display)
    local moves = 0
    while true do
        local changed = false
        for i = 1, #p - 1 do
            for j = i + 1, #p do
                local a, b = p[i - 1] or 0, p[j + 1] or 0
                local gain = self:distance(a, p[i]) + self:distance(p[j], b) - self:distance(a, p[j]) - self:distance(p[i], b)
                if gain > 0 then
                    if display then self:emit("reverse %d..%d gain %d", p[i], p[j], gain) end
                    reverse(p, i, j); changed = true; moves = moves + 1
                    break
                end
            end
            if changed then break end
        end
        if not changed then return moves end
    end
end
function W:baseCheck()
    if not self.depot then self:fail("no depot") end
    if not next(self.stops) then self:fail("no stops") end
end
function W:capacityCheck(q)
    for _, id in ipairs(self:ids()) do if self.stops[id].demand > q then self:fail("stop %d demand %d exceeds capacity %d", id, self.stops[id].demand, q) end end
end
function W:exact()
    local ids, memo = self:ids(), {}
    local cost
    cost = function(mask, last)
        if mask == 0 then return self:distance(last, 0) end
        local key = mask .. ":" .. last
        if memo[key] then return memo[key] end
        local best = math.huge
        for i, id in ipairs(ids) do
            local bit = 1 << (i - 1)
            if mask & bit ~= 0 then best = math.min(best, self:distance(last, id) + cost(mask ~ bit, id)) end
        end
        memo[key] = best
        return best
    end
    local mask, last, result = (1 << #ids) - 1, 0, {}
    while mask ~= 0 do
        local best = cost(mask, last)
        for i, id in ipairs(ids) do
            local bit = 1 << (i - 1)
            if mask & bit ~= 0 and self:distance(last, id) + cost(mask ~ bit, id) == best then
                result[#result + 1], mask, last = id, mask ~ bit, id
                break
            end
        end
    end
    return result
end
function W:bound()
    local ids, tree, used, edges, mst = self:ids(), {0}, {}, {}, 0
    for _ = 1, #ids do
        local best, candidate, parent = math.huge
        for _, id in ipairs(ids) do
            if not used[id] then
                for _, p in ipairs(tree) do
                    local d = self:distance(p, id)
                    if d < best then best, candidate, parent = d, id, p end
                end
            end
        end
        mst, used[candidate] = mst + best, true
        tree[#tree + 1], edges[#edges + 1] = candidate, label(parent) .. "-" .. candidate
    end
    local one = 2 * self:distance(0, ids[1])
    if #ids > 1 then
        local distances = {}
        for _, id in ipairs(ids) do distances[#distances + 1] = self:distance(0, id) end
        table.sort(distances); one = distances[1] + distances[2]
        used = {[ids[1]]=true}
        for _ = 2, #ids do
            local best, candidate = math.huge
            for _, a in ipairs(ids) do if used[a] then for _, b in ipairs(ids) do
                if not used[b] and self:distance(a, b) < best then best, candidate = self:distance(a, b), b end
            end end end
            one, used[candidate] = one + best, true
        end
    end
    local best = math.max(mst, one)
    self:emit("mst: %s (length %d)", table.concat(edges, " "), mst)
    self:emit("bound: mst %d, one-tree %d, best %d", mst, one, best)
    if not self.tour then self:emit("gap: no tour")
    else
        local length = self:length(self.tour)
        local u = best > 0 and (2000 * (length - best) + best) // (2 * best) or 0
        self:emit("gap: tour %d, %d.%d%%", length, u // 10, u % 10)
    end
end
function W:improve(command)
    local initial, k0, moves = self:total(), #self.routes, 0
    while true do
        local changed = false
        if command == "RELOCATE" then
            for r, a in ipairs(self.routes) do
                for p, c in ipairs(a) do
                    for t, b in ipairs(self.routes) do
                        if t ~= r and self:load(b) + self.stops[c].demand <= self.capacity then
                            for j = 0, #b do
                                local before, after, u, v = a[p - 1] or 0, a[p + 1] or 0, b[j] or 0, b[j + 1] or 0
                                local gain = self:distance(before, c) + self:distance(c, after) - self:distance(before, after) - self:distance(u, c) - self:distance(c, v) + self:distance(u, v)
                                if gain > 0 then
                                    self:emit("relocate %d from route %d to route %d after %s gain %d", c, r, t, label(u), gain)
                                    self.routes[r] = append(copy(a, 1, p - 1), copy(a, p + 1))
                                    self.routes[t] = place(b, j, {c})
                                    changed = true
                                    break
                                end
                            end
                        end
                        if changed then break end
                    end
                    if changed then break end
                end
                if changed then break end
            end
        elseif command == "EXCHANGE" then
            for r, a in ipairs(self.routes) do
                for t = r + 1, #self.routes do
                    local b = self.routes[t]
                    for p, c in ipairs(a) do
                        for j, e in ipairs(b) do
                            if self:load(a) - self.stops[c].demand + self.stops[e].demand <= self.capacity and self:load(b) - self.stops[e].demand + self.stops[c].demand <= self.capacity then
                                local before = self:length(a) + self:length(b)
                                a[p], b[j] = e, c
                                local gain = before - self:length(a) - self:length(b)
                                if gain > 0 then self:emit("exchange %d (route %d) with %d (route %d) gain %d", c, r, e, t, gain); changed = true; break end
                                a[p], b[j] = c, e
                            end
                        end
                        if changed then break end
                    end
                    if changed then break end
                end
                if changed then break end
            end
        else
            for r, a in ipairs(self.routes) do
                for t = r + 1, #self.routes do
                    local b = self.routes[t]
                    for i = 0, #a do
                        for j = 0, #b do
                            local x, y = append(copy(a, 1, i), copy(b, j + 1)), append(copy(b, 1, j), copy(a, i + 1))
                            if self:load(x) <= self.capacity and self:load(y) <= self.capacity then
                                local gain = self:length(a) + self:length(b) - self:length(x) - self:length(y)
                                if gain > 0 then
                                    self:emit("cross route %d after %s with route %d after %s gain %d", r, label(a[i] or 0), t, label(b[j] or 0), gain)
                                    self.routes[r], self.routes[t], changed = x, y, true
                                    break
                                end
                            end
                        end
                        if changed then break end
                    end
                    if changed then break end
                end
                if changed then break end
            end
        end
        if not changed then break end
        moves = moves + 1; self:normalize()
    end
    if command == "EXCHANGE" then self:emit("exchange: moves %d, length %d -> %d", moves, initial, self:total())
    else self:emit("%s: moves %d, routes %d -> %d, length %d -> %d", command:lower(), moves, k0, #self.routes, initial, self:total()) end
end
function W:command(line)
    local args = words(line)
    local command = table.remove(args, 1)
    if command == "DEPOT" then self.depot = {x=number(args[1]), y=number(args[2])}; self:emit("depot at (%d,%d)", self.depot.x, self.depot.y); return
    elseif command == "START" then self.start = clock(args[1]); self:emit("start %s", timeText(self.start)); return
    elseif command == "STOP" then
        local id = number(args[1])
        if self.stops[id] then self:fail("stop %d already exists", id) end
        local item = {x=number(args[2]), y=number(args[3]), demand=number(args[4]), service=number(args[5])}
        if args[6] then item.open, item.close = clock(args[6]), clock(args[7]); if item.open > item.close then self:fail("invalid window") end end
        self.stops[id], self.tour, self.routes = item, nil, nil
        self:emit("stop %d added", id); return
    elseif command == "REMOVE" then
        local id = number(args[1])
        if not self.stops[id] then self:fail("unknown stop %d", id) end
        self.stops[id] = nil
        local function remove(p)
            local result = {}
            for _, value in ipairs(p) do if value ~= id then result[#result + 1] = value end end
            return result
        end
        if not next(self.stops) then self.tour, self.routes = nil, nil
        else
            if self.tour then self.tour = remove(self.tour) end
            if self.routes then for i, p in ipairs(self.routes) do self.routes[i] = remove(p) end; self:normalize() end
        end
        self:emit("stop %d removed", id); return
    elseif command == "LIST" then
        if self.depot then self:emit("depot (%d,%d)", self.depot.x, self.depot.y) else self:emit("depot none") end
        self:emit("start %s", timeText(self.start)); self:emit("stops %d", #self:ids())
        for _, id in ipairs(self:ids()) do
            local item = self.stops[id]
            self:emit("%d at (%d,%d) demand %d service %d window %s", id, item.x, item.y, item.demand, item.service, item.open and timeText(item.open) .. "-" .. timeText(item.close) or "none")
        end
        return
    elseif command == "MATRIX" then
        if not self.depot then self:fail("no depot") end
        local ids, width = append({0}, self:ids()), 1
        for _, a in ipairs(ids) do
            width = math.max(width, #label(a))
            for _, b in ipairs(ids) do width = math.max(width, #tostring(self:distance(a, b))) end
        end
        local row = {string.rep(" ", width)}
        for _, id in ipairs(ids) do row[#row + 1] = string.format("%" .. width .. "s", label(id)) end
        self:emit("%s", table.concat(row, " "))
        for _, a in ipairs(ids) do
            row = {string.format("%" .. width .. "s", label(a))}
            for _, b in ipairs(ids) do row[#row + 1] = string.format("%" .. width .. "d", self:distance(a, b)) end
            self:emit("%s", table.concat(row, " "))
        end
        return
    elseif command == "REPORT" then
        local demand, service, windows = 0, 0, 0
        for _, item in pairs(self.stops) do demand, service, windows = demand + item.demand, service + item.service, windows + (item.open and 1 or 0) end
        self:emit("report: stops %d, demand %d, service %d, windows %d", #self:ids(), demand, service, windows)
        if self.tour then local r = self:simulate(self.tour); self:emit("tour: length %d, return %s, violations %d, lateness %d", r.travel, timeText(r.returned), r.violations, r.lateness)
        else self:emit("tour: none") end
        if self.routes then
            local returned, violations, lateness = 0, 0, 0
            for _, p in ipairs(self.routes) do local r = self:simulate(p); returned, violations, lateness = math.max(returned, r.returned), violations + r.violations, lateness + r.lateness end
            local denominator = #self.routes * self.capacity
            local u = (2000 * demand + denominator) // (2 * denominator)
            self:emit("plan: capacity %d, routes %d, length %d, utilization %d.%d%%, return %s, violations %d, lateness %d", self.capacity, #self.routes, self:total(), u // 10, u % 10, timeText(returned), violations, lateness)
        else self:emit("plan: none") end
        return
    end
    if command == "TOUR" or command == "TWOOPT" or command == "OROPT" or command == "SWAP" or command == "SPLIT" or command == "TIMECHECK" and #args == 0 then
        if not self.tour then self:fail("no tour") end
    elseif command == "ROUTES" or command == "RELOCATE" or command == "EXCHANGE" or command == "CROSS" or command == "ROUTEOPT" or command == "TIMECHECK" then
        if not self.routes then self:fail("no plan") end
    else self:baseCheck() end
    if command == "ORDER" then
        local list, seen = {}, {}
        for _, value in ipairs(args) do local id = number(value); if not self.stops[id] then self:fail("unknown stop %d", id) end; list[#list + 1] = id end
        for _, id in ipairs(list) do if seen[id] then self:fail("duplicate stop %d", id) end; seen[id] = true end
        if #list ~= #self:ids() then self:fail("order has %d stops, expected %d", #list, #self:ids()) end
        self.tour = list; self:emit("order: %s length %d", notation(list), self:length(list))
    elseif command == "NEAREST" or command == "INSERTION" or command == "EXACT" then
        local ids, list, used = self:ids(), {}, {}
        if command == "EXACT" then
            if #ids > 10 then self:fail("too many stops for exact (%d)", #ids) end
            list = self:exact()
        else
            while #list < #ids do
                local best, candidate, at = math.huge
                for _, id in ipairs(ids) do
                    if not used[id] then
                        if command == "NEAREST" then
                            local distance = self:distance(list[#list] or 0, id)
                            if distance < best then best, candidate = distance, id end
                        else
                            for j = 0, #list do
                                local a, b = list[j] or 0, list[j + 1] or 0
                                local increase = self:distance(a, id) + self:distance(id, b) - self:distance(a, b)
                                if increase < best then best, candidate, at = increase, id, j end
                            end
                        end
                    end
                end
                if command == "NEAREST" then list[#list + 1] = candidate else list = place(list, at, {candidate}) end
                used[candidate] = true
            end
        end
        self.tour = list; self:emit("%s: %s length %d", command:lower(), notation(list), self:length(list))
    elseif command == "TOUR" then self:emit("tour: %s length %d", notation(self.tour), self:length(self.tour))
    elseif command == "TWOOPT" then local before = self:length(self.tour); local moves = self:twoopt(self.tour, true); self:emit("twoopt: moves %d, length %d -> %d", moves, before, self:length(self.tour))
    elseif command == "SWAP" or command == "OROPT" then
        local before, moves = self:length(self.tour), 0
        while true do
            local p, changed = self.tour, false
            local length = self:length(p)
            if command == "SWAP" then
                for i = 1, #p - 1 do
                    for j = i + 1, #p do
                        local a, b = p[i], p[j]; p[i], p[j] = b, a
                        local gain = length - self:length(p)
                        if gain > 0 then self:emit("swap %d and %d gain %d", a, b, gain); changed = true; break end
                        p[i], p[j] = a, b
                    end
                    if changed then break end
                end
            else
                for size = 1, 3 do
                    for i = 1, #p - size + 1 do
                        local segment = copy(p, i, i + size - 1)
                        local rest = append(copy(p, 1, i - 1), copy(p, i + size))
                        for j = 0, #rest do
                            if j ~= i - 1 then
                                local candidate = place(rest, j, segment)
                                local gain = length - self:length(candidate)
                                if gain > 0 then
                                    local names = {}; for _, id in ipairs(segment) do names[#names + 1] = label(id) end
                                    self:emit("move %s after %s gain %d", table.concat(names, "-"), label(rest[j] or 0), gain)
                                    self.tour, changed = candidate, true; break
                                end
                            end
                        end
                        if changed then break end
                    end
                    if changed then break end
                end
            end
            if not changed then break end
            moves = moves + 1
        end
        self:emit("%s: moves %d, length %d -> %d", command:lower(), moves, before, self:length(self.tour))
    elseif command == "TIMECHECK" then
        if #args == 0 then self:emit("timecheck tour depart %s", timeText(self.start)); self:simulate(self.tour, true)
        else local r = number(args[1]); if r > #self.routes then self:fail("no route %d", r) end; self:emit("timecheck route %d depart %s", r, timeText(self.start)); self:simulate(self.routes[r], true) end
    elseif command == "BOUND" then self:bound()
    elseif command == "VRP" or command == "SPLIT" or command == "SWEEP" then
        local q = number(args[1]); self:capacityCheck(q)
        local limit = args[2] and number(args[2])
        if command == "VRP" and limit then for _, id in ipairs(self:ids()) do if 2 * self:distance(0, id) > limit then self:fail("stop %d too far for limit %d", id, limit) end end end
        local routes, merges = {}, 0
        if command == "VRP" then
            local ids, savings = self:ids(), {}
            for _, id in ipairs(ids) do routes[#routes + 1] = {id} end
            for i, a in ipairs(ids) do for j = i + 1, #ids do
                local b = ids[j]; local value = self:distance(0, a) + self:distance(0, b) - self:distance(a, b)
                if value > 0 then savings[#savings + 1] = {a=a, b=b, value=value} end
            end end
            table.sort(savings, function(a, b) return a.value > b.value or a.value == b.value and (a.a < b.a or a.a == b.a and a.b < b.b) end)
            for _, saving in ipairs(savings) do
                local r, t
                for k, p in ipairs(routes) do for _, id in ipairs(p) do if id == saving.a then r = k end; if id == saving.b then t = k end end end
                if r ~= t then
                    local a, b = routes[r], routes[t]
                    if (a[1] == saving.a or a[#a] == saving.a) and (b[1] == saving.b or b[#b] == saving.b) and self:load(a) + self:load(b) <= q then
                        a, b = copy(a), copy(b)
                        if a[1] == saving.a then reverse(a) end
                        if b[#b] == saving.b then reverse(b) end
                        local joined = append(a, b)
                        if not limit or self:length(joined) <= limit then routes[r] = joined; table.remove(routes, t); merges = merges + 1 end
                    end
                end
            end
        elseif command == "SPLIT" then
            local p, cost, previous = self.tour, {[0]=0}, {}
            for j = 1, #p do
                cost[j] = math.huge
                for i = 0, j - 1 do
                    local segment = copy(p, i + 1, j)
                    if self:load(segment) <= q then
                        local value = cost[i] + self:length(segment)
                        if value < cost[j] then cost[j], previous[j] = value, i end
                    end
                end
            end
            local j = #p
            while j > 0 do local i = previous[j]; routes[#routes + 1] = copy(p, i + 1, j); j = i end
        else
            local ids = self:ids()
            table.sort(ids, function(a, b)
                local p, qstop = self.stops[a], self.stops[b]
                local ax, ay, bx, by = p.x - self.depot.x, p.y - self.depot.y, qstop.x - self.depot.x, qstop.y - self.depot.y
                local az, bz = ax == 0 and ay == 0, bx == 0 and by == 0
                if az ~= bz then return az end
                if az then return a < b end
                local ah, bh = ay > 0 or ay == 0 and ax > 0, by > 0 or by == 0 and bx > 0
                if ah ~= bh then return ah end
                local cross = ax * by - ay * bx
                if cross ~= 0 then return cross > 0 end
                local da, db = math.abs(ax) + math.abs(ay), math.abs(bx) + math.abs(by)
                return da < db or da == db and a < b
            end)
            local current = {}
            for _, id in ipairs(ids) do
                if self:load(current) + self.stops[id].demand > q then routes[#routes + 1] = current; current = {} end
                current[#current + 1] = id
            end
            routes[#routes + 1] = current
        end
        self.routes, self.capacity = routes, q; self:normalize()
        if command == "VRP" then self:emit("vrp: capacity %d, merges %d, routes %d, length %d", q, merges, #self.routes, self:total())
        else self:emit("%s: capacity %d, routes %d, length %d", command:lower(), q, #self.routes, self:total()) end
        self:routeLines()
    elseif command == "ROUTES" then self:emit("plan: capacity %d, routes %d, length %d", self.capacity, #self.routes, self:total()); self:routeLines()
    elseif command == "RELOCATE" or command == "EXCHANGE" or command == "CROSS" then self:improve(command)
    elseif command == "ROUTEOPT" then
        local before = self:total()
        for r, p in ipairs(self.routes) do local old = self:length(p); local moves = self:twoopt(p, false); self:emit("route %d: moves %d, length %d -> %d", r, moves, old, self:length(p)) end
        self:normalize(); self:emit("routeopt: length %d -> %d", before, self:total())
    end
end
local count = number(io.read("*l"))
for _ = 1, count do
    local ok, message = pcall(function() W:command(io.read("*l")) end)
    if not ok then W:emit("%s", message) end
end
if #W.output > 0 then io.write(table.concat(W.output, "\n"), "\n") end
