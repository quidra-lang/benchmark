local output = {}
local function emit(pattern, ...)
    output[#output + 1] = string.format(pattern, ...)
end
local function fail(pattern, ...)
    error(string.format(pattern, ...), 0)
end
local function split(text, separator)
    local result, start = {}, 1
    while true do
        local at = text:find(separator, start, true)
        if not at then
            result[#result + 1] = text:sub(start)
            return result
        end
        result[#result + 1] = text:sub(start, at - 1)
        start = at + #separator
    end
end
local function copy(values)
    return {table.unpack(values)}
end
local function zeros(count)
    local result = {}
    for i = 1, count do
        result[i] = 0
    end
    return result
end

local Graph = {}
Graph.__index = Graph
function Graph.new()
    return setmetatable({names = {}, edges = {}}, Graph)
end
function Graph:add(a, b, capacity, cost)
    self.edges[#self.edges + 1] = {from = a, to = b, capacity = capacity, cost = cost or 0, lower = 0, flow = 0}
end
function Graph:copy()
    local result = Graph.new()
    result.names = copy(self.names)
    for _, edge in ipairs(self.edges) do
        result:add(edge.from, edge.to, edge.capacity, edge.cost)
        result.edges[#result.edges].lower = edge.lower
    end
    return result
end
function Graph:arcs(vertex)
    local result = {}
    for i, edge in ipairs(self.edges) do
        if edge.from == vertex then
            result[#result + 1] = i
        end
    end
    for i, edge in ipairs(self.edges) do
        if edge.to == vertex then
            result[#result + 1] = -i
        end
    end
    return result
end
function Graph:endpoints(arc)
    local edge = self.edges[math.abs(arc)]
    if arc > 0 then
        return edge.from, edge.to
    end
    return edge.to, edge.from
end
function Graph:residual(arc)
    local edge = self.edges[math.abs(arc)]
    return arc > 0 and edge.capacity - edge.flow or edge.flow
end
function Graph:arc_cost(arc)
    local edge = self.edges[math.abs(arc)]
    return arc > 0 and edge.cost or -edge.cost
end
function Graph:push(path, amount)
    for _, arc in ipairs(path) do
        local edge = self.edges[math.abs(arc)]
        edge.flow = edge.flow + (arc > 0 and amount or -amount)
    end
end
function Graph:bottleneck(path)
    local amount = self:residual(path[1])
    for _, arc in ipairs(path) do
        amount = math.min(amount, self:residual(arc))
    end
    return amount
end
function Graph:bfs(source, threshold)
    local levels, parents, queue = {[source] = 0}, {}, {source}
    local at = 1
    while at <= #queue do
        local vertex = queue[at]
        at = at + 1
        for _, arc in ipairs(self:arcs(vertex)) do
            local _, target = self:endpoints(arc)
            if self:residual(arc) >= threshold and levels[target] == nil then
                levels[target], parents[target] = levels[vertex] + 1, arc
                queue[#queue + 1] = target
            end
        end
    end
    return levels, parents
end
function Graph:path(source, target, parents)
    local result = {}
    while target ~= source do
        local arc = parents[target]
        table.insert(result, 1, arc)
        target = self:endpoints(arc)
    end
    return result
end
function Graph:augment(source, target, threshold)
    local levels, parents = self:bfs(source, threshold)
    if levels[target] == nil then
        return nil
    end
    local path = self:path(source, target, parents)
    local amount = self:bottleneck(path)
    self:push(path, amount)
    return {path = path, amount = amount, stage = threshold}
end
function Graph:maximum(source, target, mode)
    local result, phases = {}, 0
    if mode == "DINIC" then
        local adjacency = {}
        for vertex = 1, #self.names do
            adjacency[vertex] = self:arcs(vertex)
        end
        while true do
            local levels = self:bfs(source, 1)
            if levels[target] == nil then
                break
            end
            phases = phases + 1
            local pointers = {}
            for vertex = 1, #self.names do
                pointers[vertex] = 1
            end
            local path, vertex = {}, source
            while true do
                if vertex == target then
                    local amount = self:bottleneck(path)
                    self:push(path, amount)
                    result[#result + 1] = {path = copy(path), amount = amount, stage = phases}
                    path, vertex = {}, source
                elseif pointers[vertex] > #adjacency[vertex] then
                    if vertex == source then
                        break
                    end
                    local arc = table.remove(path)
                    vertex = self:endpoints(arc)
                    pointers[vertex] = pointers[vertex] + 1
                else
                    local arc = adjacency[vertex][pointers[vertex]]
                    local _, target_vertex = self:endpoints(arc)
                    if self:residual(arc) > 0 and levels[target_vertex] == levels[vertex] + 1 then
                        path[#path + 1], vertex = arc, target_vertex
                    else
                        pointers[vertex] = pointers[vertex] + 1
                    end
                end
            end
        end
        return result, phases
    end
    local threshold = 1
    if mode == "SCALING" then
        local largest = 0
        for _, edge in ipairs(self.edges) do
            largest = math.max(largest, edge.capacity)
        end
        while threshold * 2 <= largest do
            threshold = threshold * 2
        end
    end
    while threshold > 0 do
        while true do
            local pushed = self:augment(source, target, threshold)
            if not pushed then
                break
            end
            result[#result + 1] = pushed
        end
        threshold = threshold // 2
    end
    return result, phases
end
function Graph:negative_cycle(use_lower)
    local distance = zeros(#self.names)
    for _ = 1, #self.names do
        local changed = false
        for _, edge in ipairs(self.edges) do
            local capacity = edge.capacity - (use_lower and edge.lower or 0)
            if capacity > 0 and distance[edge.to] > distance[edge.from] + edge.cost then
                distance[edge.to], changed = distance[edge.from] + edge.cost, true
            end
        end
        if not changed then
            return false
        end
    end
    return #self.names > 0
end
function Graph:shortest(source)
    local distance, parents, arcs = {[source] = 0}, {}, {}
    for i = 1, #self.edges do
        if self:residual(i) > 0 then
            arcs[#arcs + 1] = i
        end
    end
    for i = 1, #self.edges do
        if self:residual(-i) > 0 then
            arcs[#arcs + 1] = -i
        end
    end
    while true do
        local changed = false
        for _, arc in ipairs(arcs) do
            local a, b = self:endpoints(arc)
            if distance[a] ~= nil then
                local candidate = distance[a] + self:arc_cost(arc)
                if distance[b] == nil or candidate < distance[b] then
                    distance[b], parents[b], changed = candidate, arc, true
                end
            end
        end
        if not changed then
            return distance, parents
        end
    end
end
function Graph:minimum_cost(source, target, limit)
    local paths, total, cost = {}, 0, 0
    while not limit or total < limit do
        local distance, parents = self:shortest(source)
        if distance[target] == nil then
            break
        end
        local path = self:path(source, target, parents)
        local amount = self:bottleneck(path)
        if limit then
            amount = math.min(amount, limit - total)
        end
        self:push(path, amount)
        total, cost = total + amount, cost + amount * distance[target]
        paths[#paths + 1] = {path = path, amount = amount, unit = distance[target]}
    end
    return paths, total, cost
end
function Graph:balances()
    local incoming, outgoing = zeros(#self.names), zeros(#self.names)
    for _, edge in ipairs(self.edges) do
        outgoing[edge.from] = outgoing[edge.from] + edge.flow
        incoming[edge.to] = incoming[edge.to] + edge.flow
    end
    return incoming, outgoing
end
function Graph:value(source)
    local incoming, outgoing = self:balances()
    return outgoing[source] - incoming[source]
end
function Graph:total_cost()
    local total = 0
    for _, edge in ipairs(self.edges) do
        total = total + edge.flow * edge.cost
    end
    return total
end
function Graph:notation(path, original_edges)
    local source = self:endpoints(path[1])
    local parts = {self.names[source]}
    for _, arc in ipairs(path) do
        if not original_edges or math.abs(arc) <= original_edges then
            local _, target = self:endpoints(arc)
            parts[#parts + 1] = (arc > 0 and "+" or "-") .. math.abs(arc)
            parts[#parts + 1] = self.names[target]
        end
    end
    return table.concat(parts, " ")
end
function Graph:decompose()
    local remaining, balance = {}, zeros(#self.names)
    for i, edge in ipairs(self.edges) do
        remaining[i] = edge.flow
        balance[edge.from] = balance[edge.from] + edge.flow
        balance[edge.to] = balance[edge.to] - edge.flow
    end
    local result = {}
    while true do
        local first
        for i, flow in ipairs(remaining) do
            if flow > 0 then
                first = i
                break
            end
        end
        if not first then
            return result
        end
        local source = self.edges[first].from
        for vertex, amount in ipairs(balance) do
            if amount > 0 then
                source = vertex
                break
            end
        end
        local vertices, path = {source}, {}
        while true do
            local vertex, chosen = vertices[#vertices], nil
            for i, edge in ipairs(self.edges) do
                if edge.from == vertex and remaining[i] > 0 then
                    chosen = i
                    break
                end
            end
            path[#path + 1] = chosen
            local target = self.edges[chosen].to
            local repeated
            for i, held in ipairs(vertices) do
                if held == target then
                    repeated = i
                    break
                end
            end
            if repeated then
                local cycle, amount = {}, remaining[path[repeated]]
                for i = repeated, #path do
                    cycle[#cycle + 1] = path[i]
                    amount = math.min(amount, remaining[path[i]])
                end
                for _, id in ipairs(cycle) do
                    remaining[id] = remaining[id] - amount
                end
                result[#result + 1] = {path = cycle, amount = amount, cycle = true}
                break
            end
            vertices[#vertices + 1] = target
            if balance[target] < 0 then
                local amount = math.min(balance[source], -balance[target])
                for _, id in ipairs(path) do
                    amount = math.min(amount, remaining[id])
                end
                for _, id in ipairs(path) do
                    remaining[id] = remaining[id] - amount
                end
                balance[source], balance[target] = balance[source] - amount, balance[target] + amount
                result[#result + 1] = {path = path, amount = amount, cycle = false}
                break
            end
        end
    end
end

local network, demands, owner, flow_source, flow_target = Graph.new(), {}, "none", nil, nil
local function vertex(name)
    for i, candidate in ipairs(network.names) do
        if candidate == name then
            return i
        end
    end
    fail("UNKNOWN NODE %s", name)
end
local function endpoints_check(a, b)
    local source, target = vertex(a), vertex(b)
    if source == target then
        fail("SAME NODE")
    end
    return source, target
end
local function start(source, target)
    if owner ~= "flow" or flow_source ~= source or flow_target ~= target then
        for _, edge in ipairs(network.edges) do
            edge.flow = 0
        end
    end
    owner, flow_source, flow_target = "flow", source, target
    return network:value(source)
end
local function flow_list()
    for i, edge in ipairs(network.edges) do
        emit("FLOW %d %s %s %d/%d", i, network.names[edge.from], network.names[edge.to], edge.flow, edge.capacity)
    end
end
local function joined(values, separator)
    return #values == 0 and "-" or table.concat(values, separator)
end
local function matching(w)
    local left, right, ids, left_id, right_id = split(w[2], ","), split(w[3], ","), {}, {}, {}
    for i, name in ipairs(left) do
        if ids[name] then
            fail("DUPLICATE VERTEX %s", name)
        end
        ids[name], left_id[name] = true, i
    end
    for i, name in ipairs(right) do
        if ids[name] then
            fail("DUPLICATE VERTEX %s", name)
        end
        ids[name], right_id[name] = true, i
    end
    local pairs, seen = {}, {}
    if w[4] ~= "-" then
        for _, text in ipairs(split(w[4], ",")) do
            local fields = split(text, "-")
            local a, b = left_id[fields[1]], right_id[fields[2]]
            if not a then
                fail("UNKNOWN VERTEX %s", fields[1])
            end
            if not b then
                fail("UNKNOWN VERTEX %s", fields[2])
            end
            if seen[text] then
                fail("DUPLICATE PAIR %s", text)
            end
            seen[text] = true
            pairs[#pairs + 1] = {a, b}
        end
    end
    local mates_a, mates_b = {}, {}
    local function attempt(a, examined)
        for _, pair in ipairs(pairs) do
            local b = pair[2]
            if pair[1] == a and not examined[b] then
                examined[b] = true
                if not mates_b[b] or attempt(mates_b[b], examined) then
                    mates_a[a], mates_b[b] = b, a
                    return true
                end
            end
        end
        return false
    end
    for a = 1, #left do
        attempt(a, {})
    end
    local marked_a, marked_b, queue = {}, {}, {}
    local free_a, free_b, cover, hall_a, hall_b, size = {}, {}, {}, {}, {}, 0
    for a, name in ipairs(left) do
        if not mates_a[a] then
            marked_a[a], queue[#queue + 1], free_a[#free_a + 1] = true, a, name
        else
            size = size + 1
        end
    end
    local at = 1
    while at <= #queue do
        local a = queue[at]
        at = at + 1
        for _, pair in ipairs(pairs) do
            local b = pair[2]
            if pair[1] == a and b ~= mates_a[a] and not marked_b[b] then
                marked_b[b] = true
                if mates_b[b] and not marked_a[mates_b[b]] then
                    marked_a[mates_b[b]], queue[#queue + 1] = true, mates_b[b]
                end
            end
        end
    end
    for a, name in ipairs(left) do
        if marked_a[a] then
            hall_a[#hall_a + 1] = name
        else
            cover[#cover + 1] = name
        end
    end
    for b, name in ipairs(right) do
        if not mates_b[b] then
            free_b[#free_b + 1] = name
        end
        if marked_b[b] then
            cover[#cover + 1], hall_b[#hall_b + 1] = name, name
        end
    end
    emit("MATCH size=%d left=%d right=%d", size, #left, #right)
    for a, name in ipairs(left) do
        if mates_a[a] then
            emit("PAIR %s %s", name, right[mates_a[a]])
        end
    end
    emit("FREE %s %s", joined(free_a, ","), joined(free_b, ","))
    emit("COVER size=%d%s", #cover, #cover > 0 and " " .. table.concat(cover, " ") or "")
    if #free_a > 0 then
        emit("HALL %s %s", joined(hall_a, ","), joined(hall_b, ","))
    end
end
local function assignment(w)
    local size = tonumber(w[3])
    if size < 1 or size > 8 then
        fail("BAD SIZE")
    end
    if #w - 3 ~= size * size then
        fail("BAD LENGTH")
    end
    local mapping, best, used, optimum, count = {}, nil, {}, 0, 0
    local function search(row, total)
        if row > size then
            if not best or (w[2] == "MIN" and total < optimum) or (w[2] == "MAX" and total > optimum) then
                optimum, count, best = total, 0, copy(mapping)
            end
            if total == optimum then
                count = count + 1
            end
            return
        end
        for column = 1, size do
            local text = w[3 + (row - 1) * size + column]
            if not used[column] and text ~= "x" then
                mapping[row], used[column] = column, true
                search(row + 1, total + tonumber(text))
                used[column] = nil
            end
        end
    end
    search(1, 0)
    if not best then
        emit("ASSIGN %s n=%d infeasible", w[2], size)
        return
    end
    emit("ASSIGN %s n=%d total=%d optimal=%d", w[2], size, optimum, count)
    for row, column in ipairs(best) do
        emit("MATE %d %d %s", row, column, w[3 + (row - 1) * size + column])
    end
end

local function command(w)
    local cmd = w[1]
    if cmd == "NODE" then
        local seen = {}
        for _, name in ipairs(network.names) do
            seen[name] = true
        end
        for i = 2, #w do
            if seen[w[i]] then
                fail("DUPLICATE NODE %s", w[i])
            end
            seen[w[i]] = true
        end
        if #network.names + #w - 1 > 20 then
            fail("TOO MANY NODES")
        end
        for i = 2, #w do
            network.names[#network.names + 1], demands[#demands + 1] = w[i], 0
        end
        emit("NODE added=%d total=%d", #w - 1, #network.names)
    elseif cmd == "EDGE" then
        local a, b = vertex(w[2]), vertex(w[3])
        if a == b then
            fail("SELF LOOP")
        end
        if #network.edges == 60 then
            fail("TOO MANY EDGES")
        end
        local cost = tonumber(w[5]) or 0
        network:add(a, b, tonumber(w[4]), cost)
        emit("EDGE %d %s %s cap=%s cost=%d", #network.edges, w[2], w[3], w[4], cost)
    elseif cmd == "LOWER" or cmd == "CAP" or cmd == "COST" then
        local id, value = tonumber(w[2]), tonumber(w[3])
        if id < 1 or id > #network.edges then
            fail("UNKNOWN EDGE %s", w[2])
        end
        local edge = network.edges[id]
        if cmd == "LOWER" then
            if value > edge.capacity then
                fail("BAD BOUND")
            end
            edge.lower = value
            emit("LOWER %d low=%d cap=%d", id, value, edge.capacity)
        elseif cmd == "CAP" then
            if value < edge.lower then
                fail("BAD BOUND")
            end
            if value < edge.flow then
                fail("BELOW FLOW")
            end
            edge.capacity = value
            emit("CAP %d low=%d cap=%d", id, edge.lower, value)
        else
            edge.cost = value
            emit("COST %d cost=%d", id, value)
        end
    elseif cmd == "DEMAND" then
        local at, total = vertex(w[2]), 0
        demands[at] = tonumber(w[3])
        for _, demand in ipairs(demands) do
            total = total + demand
        end
        emit("DEMAND %s %s total=%d", w[2], w[3], total)
    elseif cmd == "RESET" then
        local changed = 0
        for _, edge in ipairs(network.edges) do
            if edge.flow ~= 0 then
                changed = changed + 1
            end
            edge.flow = 0
        end
        owner = "none"
        emit("RESET edges=%d", changed)
    elseif cmd == "CLEAR" then
        emit("CLEAR nodes=%d edges=%d", #network.names, #network.edges)
        network, demands, owner = Graph.new(), {}, "none"
    elseif cmd == "SHOW" then
        emit("NETWORK nodes=%d edges=%d", #network.names, #network.edges)
        if owner == "none" then
            emit("STATE none")
        elseif owner == "circulation" then
            emit("STATE circulation cost=%d", network:total_cost())
        else
            emit("STATE flow %s %s value=%d cost=%d", network.names[flow_source],
                network.names[flow_target], network:value(flow_source), network:total_cost())
        end
        local incoming, outgoing = network:balances()
        for i, name in ipairs(network.names) do
            emit("NODE %s demand=%d out=%d in=%d", name, demands[i], outgoing[i], incoming[i])
        end
        for i, edge in ipairs(network.edges) do
            emit("EDGE %d %s %s cap=%d cost=%d low=%d flow=%d", i, network.names[edge.from],
                network.names[edge.to], edge.capacity, edge.cost, edge.lower, edge.flow)
        end
    elseif cmd == "AUGMENT" or cmd == "MAXFLOW" or cmd == "DINIC" or cmd == "SCALING" or
        cmd == "MINCUT" or cmd == "SENSITIVITY" or cmd == "MINCOST" or cmd == "DISJOINT" then
        local source, target = endpoints_check(w[2], w[3])
        if cmd == "SENSITIVITY" then
            local base = network:copy()
            base:maximum(source, target, "MAXFLOW")
            local value, up, down, ups, downs = base:value(source), {}, {}, 0, 0
            for i, edge in ipairs(network.edges) do
                local changed = network:copy()
                changed.edges[i].capacity = changed.edges[i].capacity + 1
                changed:maximum(source, target, "MAXFLOW")
                up[i] = changed:value(source) > value
                if up[i] then
                    ups = ups + 1
                end
                if edge.capacity > 0 then
                    changed = network:copy()
                    changed.edges[i].capacity = changed.edges[i].capacity - 1
                    changed:maximum(source, target, "MAXFLOW")
                    down[i] = changed:value(source) < value
                    if down[i] then
                        downs = downs + 1
                    end
                end
            end
            emit("SENSITIVITY %s %s value=%d up=%d down=%d", w[2], w[3], value, ups, downs)
            for i, edge in ipairs(network.edges) do
                if up[i] or down[i] then
                    emit("CRITICAL %d %s %s up=%s down=%s", i, network.names[edge.from],
                        network.names[edge.to], up[i] and "yes" or "no", down[i] and "yes" or "no")
                end
            end
        elseif cmd == "MINCOST" then
            if network:negative_cycle(false) then
                fail("NEGATIVE CYCLE")
            end
            local limit = w[4] ~= "MAX" and tonumber(w[4]) or nil
            local working = network:copy()
            local paths, value, cost = working:minimum_cost(source, target, limit)
            if limit and value < limit then
                emit("MINCOST %s %s k=%s infeasible max=%d", w[2], w[3], w[4], value)
                return
            end
            for i, edge in ipairs(network.edges) do
                edge.flow = working.edges[i].flow
            end
            owner, flow_source, flow_target = "flow", source, target
            emit("MINCOST %s %s k=%s flow=%d cost=%d", w[2], w[3], w[4], value, cost)
            for i, pushed in ipairs(paths) do
                emit("AUG %d amount=%d cost=%d %s", i, pushed.amount, pushed.unit, working:notation(pushed.path))
            end
            flow_list()
        elseif cmd == "DISJOINT" then
            local working, entrances, exits = Graph.new(), {}, {}
            for i, name in ipairs(network.names) do
                working.names[#working.names + 1] = name
                entrances[i], exits[i] = #working.names, #working.names
                if w[4] == "VERTEX" and i ~= source and i ~= target then
                    working.names[#working.names + 1], exits[i] = name, #working.names + 1
                end
            end
            for _, edge in ipairs(network.edges) do
                working:add(exits[edge.from], entrances[edge.to], edge.capacity > 0 and 1 or 0, 0)
            end
            if w[4] == "VERTEX" then
                for i = 1, #network.names do
                    if i ~= source and i ~= target then
                        working:add(entrances[i], exits[i], 1, 0)
                    end
                end
            end
            working:maximum(entrances[source], entrances[target], "MAXFLOW")
            local paths = {}
            for _, part in ipairs(working:decompose()) do
                if not part.cycle then
                    paths[#paths + 1] = part
                end
            end
            emit("DISJOINT %s %s %s count=%d", w[2], w[3], w[4], #paths)
            for i, part in ipairs(paths) do
                emit("PATH %d %s", i, working:notation(part.path, #network.edges))
            end
        else
            local initial = start(source, target)
            if cmd == "AUGMENT" then
                local pushed = network:augment(source, target, 1)
                if pushed then
                    emit("AUGMENT %s %s value=%d amount=%d %s", w[2], w[3], network:value(source),
                        pushed.amount, network:notation(pushed.path))
                else
                    emit("AUGMENT %s %s value=%d none", w[2], w[3], network:value(source))
                end
            else
                local paths, phases = network:maximum(source, target, cmd)
                if cmd == "MINCUT" then
                    local reached = network:bfs(source, 1)
                    local a, b, cut = {}, {}, {}
                    for i, name in ipairs(network.names) do
                        local list = reached[i] ~= nil and a or b
                        list[#list + 1] = name
                    end
                    for i, edge in ipairs(network.edges) do
                        if reached[edge.from] ~= nil and reached[edge.to] == nil then
                            cut[#cut + 1] = i
                        end
                    end
                    emit("MINCUT %s %s value=%d edges=%d", w[2], w[3], network:value(source), #cut)
                    emit("SOURCE %s", table.concat(a, " "))
                    emit("SINK %s", table.concat(b, " "))
                    for _, i in ipairs(cut) do
                        local edge = network.edges[i]
                        emit("CUT %d %s %s %d", i, network.names[edge.from], network.names[edge.to], edge.capacity)
                    end
                else
                    emit("%s %s %s value=%d start=%d%s paths=%d", cmd, w[2], w[3], network:value(source),
                        initial, cmd == "DINIC" and " phases=" .. phases or "", #paths)
                    for i, pushed in ipairs(paths) do
                        local stage = cmd == "DINIC" and " phase=" .. pushed.stage or
                            cmd == "SCALING" and " delta=" .. pushed.stage or ""
                        emit("AUG %d%s amount=%d %s", i, stage, pushed.amount, network:notation(pushed.path))
                    end
                    flow_list()
                end
            end
        end
    elseif cmd == "DECOMPOSE" then
        local parts, paths, cycles = network:decompose(), 0, 0
        for _, part in ipairs(parts) do
            if part.cycle then
                cycles = cycles + 1
            else
                paths = paths + 1
            end
        end
        emit("DECOMPOSE paths=%d cycles=%d", paths, cycles)
        paths, cycles = 0, 0
        for _, part in ipairs(parts) do
            local kind, id
            if part.cycle then
                cycles = cycles + 1
                kind, id = "CYCLE", cycles
            else
                paths = paths + 1
                kind, id = "PATH", paths
            end
            emit("%s %d amount=%d %s", kind, id, part.amount, network:notation(part.path))
        end
    elseif cmd == "VERIFY" then
        local violations = {}
        for i, edge in ipairs(network.edges) do
            if edge.flow < edge.lower then
                violations[#violations + 1] = string.format("LOW %d flow=%d low=%d", i, edge.flow, edge.lower)
            end
        end
        local incoming, outgoing = network:balances()
        for i, name in ipairs(network.names) do
            if owner ~= "flow" or (i ~= flow_source and i ~= flow_target) then
                local need = owner == "flow" and 0 or demands[i]
                if incoming[i] - outgoing[i] ~= need then
                    violations[#violations + 1] = string.format("BALANCE %s net=%d need=%d", name, incoming[i] - outgoing[i], need)
                end
            end
        end
        if #violations == 0 then
            emit("VERIFY ok")
        else
            emit("VERIFY violations=%d", #violations)
            for _, text in ipairs(violations) do
                emit("%s", text)
            end
        end
    elseif cmd == "CIRCULATION" then
        if w[2] == "MINCOST" and network:negative_cycle(true) then
            fail("NEGATIVE CYCLE")
        end
        local total = 0
        for _, demand in ipairs(demands) do
            total = total + demand
        end
        if total ~= 0 then
            emit("CIRCULATION infeasible unbalanced=%d", total)
            return
        end
        local working, residual = network:copy(), copy(demands)
        local source, target = #network.names + 1, #network.names + 2
        working.names[source], working.names[target] = "SS", "TT"
        for i, edge in ipairs(network.edges) do
            working.edges[i].capacity = working.edges[i].capacity - edge.lower
            residual[edge.to], residual[edge.from] = residual[edge.to] - edge.lower, residual[edge.from] + edge.lower
        end
        for i, value in ipairs(residual) do
            if value < 0 then
                working:add(source, i, -value, 0)
            end
        end
        local required, sink_edges = 0, {}
        for i, value in ipairs(residual) do
            if value > 0 then
                working:add(i, target, value, 0)
                sink_edges[#sink_edges + 1], required = #working.edges, required + value
            end
        end
        if w[2] == "ANY" then
            working:maximum(source, target, "MAXFLOW")
        else
            working:minimum_cost(source, target, nil)
        end
        local achieved = 0
        for _, i in ipairs(sink_edges) do
            achieved = achieved + working.edges[i].flow
        end
        if achieved < required then
            emit("CIRCULATION infeasible required=%d achieved=%d", required, achieved)
            local reached, cut = working:bfs(source, 1), {}
            for i, name in ipairs(network.names) do
                if reached[i] ~= nil then
                    cut[#cut + 1] = name
                end
            end
            emit("CUT %s", table.concat(cut, " "))
        else
            for i, edge in ipairs(network.edges) do
                edge.flow = edge.lower + working.edges[i].flow
            end
            owner = "circulation"
            emit("CIRCULATION feasible required=%d cost=%d", required, network:total_cost())
            flow_list()
        end
    elseif cmd == "MATCH" then
        matching(w)
    elseif cmd == "ASSIGN" then
        assignment(w)
    end
end

local count = tonumber(io.read("*l"))
for _ = 1, count do
    local words = split(io.read("*l"), " ")
    local ok, message = pcall(command, words)
    if not ok then
        emit("ERROR %s", message)
    end
end
io.write(table.concat(output, "\n"), "\n")
