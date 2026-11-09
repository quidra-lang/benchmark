local Input = require("graph_io")
local Layering = require("acyclic_layering")
local Crossing = require("crossing")
local Coordinates = require("coordinates")
local Canvas = require("canvas")
local Layout = {}
Layout.__index = Layout

local function append(items, value)
    items[#items + 1] = value
end

local function extend(items, values)
    for _, value in ipairs(values) do append(items, value) end
end

local function count(items)
    local n = 0
    for _ in pairs(items) do n = n + 1 end
    return n
end

local function reachable(start, neighbors)
    local found, pending = {[start] = true}, {start}
    while #pending > 0 do
        local vertex = table.remove(pending)
        for _, following in ipairs(neighbors[vertex]) do
            if not found[following] then found[following] = true; append(pending, following) end
        end
    end
    return found
end

local function copy_order(orders)
    local result = {}
    for i, layer in ipairs(orders) do result[i] = Input.copy(layer) end
    return result
end

local function order_key(orders)
    local layers = {}
    for _, layer in ipairs(orders) do append(layers, table.concat(layer, ",")) end
    return table.concat(layers, ";")
end

local function segment_key(first, second)
    return first .. ":" .. second
end

function Layout.new(graph)
    local ids = {}
    for id in pairs(graph.nodes) do append(ids, id) end
    table.sort(ids)
    local node_number, labels, names, widths, edges = {}, {}, {}, {}, {}
    for i, id in ipairs(ids) do
        node_number[id], labels[i], names[i], widths[i] = i, graph.nodes[id], tostring(id), #graph.nodes[id] + 2
    end
    for i, pair in ipairs(graph.edges) do
        local source, target = node_number[pair[1]], node_number[pair[2]]
        edges[i] = {number = i, source = source, target = target, upper = source, lower = target, reversed = false,
            transitive = false, chain = {}, span = 0, crossings = 0, route = {}, bends = 0, length = 0}
    end
    return setmetatable({graph = graph, name = graph.name, settings = graph.settings, ids = ids, node_number = node_number,
        labels = labels, node_count = #ids, edges = edges, names = names, widths = widths, drawn = {},
        sweep_records = {}, sift_records = {}, random_state = graph.settings.seed}, Layout)
end

function Layout:analyze_graph()
    local upper, lower, undirected = {}, {}, {}
    for i = 1, self.node_count do upper[i], lower[i], undirected[i] = {}, {}, {} end
    for _, edge in ipairs(self.edges) do
        append(lower[edge.source], edge.target)
        append(upper[edge.target], edge.source)
        append(undirected[edge.source], edge.target)
        append(undirected[edge.target], edge.source)
    end
    self.sources, self.sinks, self.isolated, self.components, self.strong_components = 0, 0, 0, 0, {}
    local remaining = {}
    for v = 1, self.node_count do
        if #upper[v] == 0 and #lower[v] > 0 then self.sources = self.sources + 1 end
        if #lower[v] == 0 and #upper[v] > 0 then self.sinks = self.sinks + 1 end
        if #lower[v] == 0 and #upper[v] == 0 then self.isolated = self.isolated + 1 end
        remaining[v] = true
    end
    for v = 1, self.node_count do
        if remaining[v] then
            for member in pairs(reachable(v, undirected)) do remaining[member] = nil end
            self.components = self.components + 1
        end
    end
    local closure = {}
    for v = 1, self.node_count do closure[v], remaining[v] = reachable(v, lower), true end
    for first = 1, self.node_count do
        if remaining[first] then
            local component = {}
            for vertex = first, self.node_count do
                if remaining[vertex] and closure[first][vertex] and closure[vertex][first] then append(component, vertex) end
            end
            for _, vertex in ipairs(component) do remaining[vertex] = nil end
            if #component >= 2 then append(self.strong_components, component) end
        end
    end
end

function Layout:prepare_dag()
    local original = {}
    for _, edge in ipairs(self.edges) do append(original, {edge.source, edge.target}) end
    self.acyclic = Layering.acyclic_order(self.node_count, original)
    local position = {}
    for i, vertex in ipairs(self.acyclic) do position[vertex] = i end
    local dag = {}
    for _, edge in ipairs(self.edges) do
        if position[edge.source] > position[edge.target] then edge.reversed, edge.upper, edge.lower = true, edge.target, edge.source end
        append(dag, {edge.upper, edge.lower})
    end
    if self.settings.reduce == "on" then
        local _, lower = Layering.neighbors(self.node_count, dag)
        local closure = {}
        for v = 1, self.node_count do closure[v] = reachable(v, lower) end
        for _, edge in ipairs(self.edges) do
            if not edge.reversed then
                for _, following in ipairs(lower[edge.upper]) do
                    if following ~= edge.lower and closure[following][edge.lower] then edge.transitive = true; break end
                end
            end
        end
    end
    for _, edge in ipairs(self.edges) do if not edge.transitive then append(self.drawn, edge) end end
end

function Layout:assign_layers()
    local dag = {}
    for _, edge in ipairs(self.drawn) do append(dag, {edge.upper, edge.lower}) end
    local heights
    heights, self.coffman_labels, self.dummies_before, self.promotion_rounds, self.promotions = Layering.assign(self.node_count, dag, self.settings)
    local highest = 0
    for _, height in ipairs(heights) do highest = math.max(highest, height) end
    local levels, used = {}, {}
    for i, height in ipairs(heights) do levels[i], used[highest - height] = highest - height, true end
    for _, edge in ipairs(self.drawn) do for level = levels[edge.upper] + 1, levels[edge.lower] - 1 do used[level] = true end end
    local number, next_number = {}, 1
    for level = 0, highest do if used[level] then number[level], next_number = next_number, next_number + 1 end end
    self.vertex_layer, self.layer_count = {}, next_number - 1
    for i, level in ipairs(levels) do self.vertex_layer[i] = number[level] end
end

function Layout:insert_dummies()
    for _, edge in ipairs(self.drawn) do
        local first, last = self.vertex_layer[edge.upper], self.vertex_layer[edge.lower]
        edge.span, edge.chain = last - first, {edge.upper}
        for layer = first + 1, last - 1 do
            local vertex = #self.vertex_layer + 1
            self.vertex_layer[vertex], self.names[vertex], self.widths[vertex] = layer, "d" .. (vertex - self.node_count), 1
            append(edge.chain, vertex)
        end
        append(edge.chain, edge.lower)
    end
    self.vertex_count, self.upper, self.lower, self.gaps = #self.vertex_layer, {}, {}, {}
    for i = 1, self.vertex_count do self.upper[i], self.lower[i] = {}, {} end
    for i = 1, self.layer_count - 1 do self.gaps[i] = {} end
    for _, edge in ipairs(self.drawn) do
        for i = 1, #edge.chain - 1 do
            local first, second = edge.chain[i], edge.chain[i + 1]
            append(self.gaps[self.vertex_layer[first]], {first, second, edge.number})
            append(self.lower[first], second)
            append(self.upper[second], first)
        end
    end
end

function Layout:make_initial_order()
    self.initial_order = {}
    for i = 1, self.layer_count do self.initial_order[i] = {} end
    local visited = {}
    local function visit(vertex)
        if visited[vertex] then return end
        visited[vertex] = true
        append(self.initial_order[self.vertex_layer[vertex]], vertex)
        for _, following in ipairs(self.lower[vertex]) do visit(following) end
    end
    for vertex = 1, self.node_count do visit(vertex) end
    self.initial_crossings = Crossing.total(self.gaps, self.initial_order)
end

function Layout:starting_order(run)
    local orders = copy_order(self.initial_order)
    if run > 0 then
        for _, layer in ipairs(orders) do
            for last = #layer, 2, -1 do
                self.random_state = (48271 * self.random_state) % 2147483647
                local chosen = self.random_state % last + 1
                layer[last], layer[chosen] = layer[chosen], layer[last]
            end
        end
    end
    return orders
end

function Layout:reorder_layer(orders, layer, reference)
    local position, current, movable, keys, old_position = Crossing.positions(orders), orders[layer], {}, {}, {}
    for i, vertex in ipairs(current) do
        old_position[vertex] = i
        if #reference[vertex] > 0 then
            append(movable, vertex)
            local neighbors, total = {}, 0
            for _, neighbor in ipairs(reference[vertex]) do append(neighbors, position[neighbor]); total = total + position[neighbor] end
            table.sort(neighbors)
            if self.settings.heuristic == "barycenter" then keys[vertex] = {total, #neighbors}
            else keys[vertex] = {neighbors[(#neighbors - 1) // 2 + 1] + neighbors[#neighbors // 2 + 1], 1} end
        end
    end
    table.sort(movable, function(first, second)
        local a, b = keys[first], keys[second]
        local difference = a[1] * b[2] - b[1] * a[2]
        return difference == 0 and old_position[first] < old_position[second] or difference < 0
    end)
    local reordered, next_vertex = {}, 1
    for _, vertex in ipairs(current) do
        if #reference[vertex] > 0 then append(reordered, movable[next_vertex]); next_vertex = next_vertex + 1 else append(reordered, vertex) end
    end
    orders[layer] = reordered
end

function Layout:adjacent_exchanges(orders)
    local swaps, position = 0, Crossing.positions(orders)
    while true do
        local changed = false
        for _, layer in ipairs(orders) do
            for index = 1, #layer - 1 do
                local first, second = layer[index], layer[index + 1]
                local before = Crossing.adjacent_cost(first, second, self.upper, self.lower, position)
                local after = Crossing.adjacent_cost(second, first, self.upper, self.lower, position)
                if before > after then
                    layer[index], layer[index + 1], position[first], position[second] = second, first, index, index - 1
                    swaps, changed = swaps + 1, true
                end
            end
        end
        if not changed then return swaps end
    end
end

function Layout:perform_sweep(orders, sweep)
    local before = Crossing.positions(orders)
    if sweep % 2 == 1 then
        for layer = 2, self.layer_count do self:reorder_layer(orders, layer, self.upper) end
    else
        for layer = self.layer_count - 1, 1, -1 do self:reorder_layer(orders, layer, self.lower) end
    end
    local after, moved = Crossing.positions(orders), 0
    for vertex = 1, self.vertex_count do if before[vertex] ~= after[vertex] then moved = moved + 1 end end
    local swaps = self:adjacent_exchanges(orders)
    return moved, swaps, Crossing.total(self.gaps, orders)
end

function Layout:run_sweeps(run)
    local orders = self:starting_order(run)
    local crossings = Crossing.total(self.gaps, orders)
    append(self.sweep_records, {run, 0, "initial", 0, 0, crossings})
    local history, best_order, best_count, best_sweep, sweep = {order_key(orders)}, copy_order(orders), crossings, 0, 1
    while crossings ~= 0 and sweep - 1 ~= self.settings.sweeps do
        if sweep - 1 >= 2 and history[#history] == history[#history - 2] then break end
        local moved, swaps
        moved, swaps, crossings = self:perform_sweep(orders, sweep)
        append(self.sweep_records, {run, sweep, sweep % 2 == 1 and "down" or "up", moved, swaps, crossings})
        append(history, order_key(orders))
        if crossings < best_count then best_count, best_order, best_sweep = crossings, copy_order(orders), sweep end
        sweep = sweep + 1
    end
    if self.best_crossings == nil or best_count < self.best_crossings then
        self.best_crossings, self.best_run, self.best_sweep, self.orders = best_count, run, best_sweep, best_order
    end
end

function Layout:sift()
    local round = 0
    while true do
        round = round + 1
        local moves = 0
        for vertex = 1, self.vertex_count do
            local layer, original, remaining = self.vertex_layer[vertex], nil, {}
            for i, other in ipairs(self.orders[self.vertex_layer[vertex]]) do
                if other == vertex then original = i else append(remaining, other) end
            end
            local costs, minimum, first_minimum = {}, nil, nil
            for position = 1, #remaining + 1 do
                local trial = Input.copy(remaining)
                table.insert(trial, position, vertex)
                self.orders[layer] = trial
                local cost = Crossing.local_cost(self.gaps, self.orders, layer)
                costs[position] = cost
                if minimum == nil or cost < minimum then minimum, first_minimum = cost, position end
            end
            local chosen = costs[original] == minimum and original or first_minimum
            self.orders[layer] = Input.copy(remaining)
            table.insert(self.orders[layer], chosen, vertex)
            if chosen ~= original then moves = moves + 1 end
        end
        append(self.sift_records, {round, moves, Crossing.total(self.gaps, self.orders)})
        if moves == 0 then break end
    end
end

function Layout:finish_crossing_counts()
    self.position, self.crossings_by_gap = Crossing.positions(self.orders), Crossing.gap_counts(self.gaps, self.orders)
    self.final_crossings, self.brute_crossings = 0, 0
    for _, value in ipairs(self.crossings_by_gap) do self.final_crossings = self.final_crossings + value end
    for _, segments in ipairs(self.gaps) do
        self.brute_crossings = self.brute_crossings + Crossing.brute(segments, self.position)
        for i, first in ipairs(segments) do
            for j = i + 1, #segments do
                local second = segments[j]
                if (self.position[first[1]] - self.position[second[1]]) * (self.position[first[2]] - self.position[second[2]]) < 0 then
                    self.edges[first[3]].crossings = self.edges[first[3]].crossings + 1
                    self.edges[second[3]].crossings = self.edges[second[3]].crossings + 1
                end
            end
        end
    end
end

function Layout:assign_tracks(segments)
    local bent, upper_counts, buses, bus_order = {}, {}, {}, {}
    for _, segment in ipairs(segments) do
        if self.x[segment[1]] ~= self.x[segment[2]] then append(bent, segment); upper_counts[segment[1]] = (upper_counts[segment[1]] or 0) + 1 end
    end
    for _, segment in ipairs(bent) do
        local p, q, kind, vertex = segment[1], segment[2]
        if upper_counts[p] >= 2 then kind, vertex = 0, p else kind, vertex = 1, q end
        local key = kind .. ":" .. vertex
        if not buses[key] then
            buses[key] = {low = math.maxinteger, high = math.mininteger, kind = kind, coordinate = self.x[vertex], members = {}, order = #bus_order + 1}
            append(bus_order, buses[key])
        end
        local bus = buses[key]
        bus.low, bus.high = math.min(bus.low, self.x[p], self.x[q]), math.max(bus.high, self.x[p], self.x[q])
        append(bus.members, segment)
    end
    table.sort(bus_order, function(a, b)
        if a.low ~= b.low then return a.low < b.low end
        if a.high ~= b.high then return a.high < b.high end
        if a.kind ~= b.kind then return a.kind < b.kind end
        if a.coordinate ~= b.coordinate then return a.coordinate < b.coordinate end
        return a.order < b.order
    end)
    local ends, tracks = {}, {}
    for _, bus in ipairs(bus_order) do
        local chosen = #ends + 1
        for i, finish in ipairs(ends) do if finish + 1 < bus.low then chosen = i; break end end
        ends[chosen] = bus.high
        for _, segment in ipairs(bus.members) do tracks[segment_key(segment[1], segment[2])] = chosen end
    end
    local total, offsets = #ends, {}
    local gap = math.max(self.settings.layer_gap, total + 2)
    for key, track in pairs(tracks) do offsets[key] = track + (gap - 2 - total) // 2 end
    return total, gap, offsets
end

function Layout:route_geometry()
    self.track_counts, self.gap_widths, self.segment_offsets = {}, {}, {}
    for i, segments in ipairs(self.gaps) do
        local offsets
        self.track_counts[i], self.gap_widths[i], offsets = self:assign_tracks(segments)
        for key, value in pairs(offsets) do self.segment_offsets[key] = value end
    end
    local vertical = self.settings.direction == "TB" or self.settings.direction == "BT"
    self.thickness, self.band_starts = {}, {0}
    for i, layer in ipairs(self.orders) do
        local thickness = 1
        if not vertical then for _, vertex in ipairs(layer) do thickness = math.max(thickness, self.widths[vertex]) end end
        self.thickness[i] = thickness
        if i > 1 then self.band_starts[i] = self.band_starts[i - 1] + self.thickness[i - 1] + self.gap_widths[i - 1] end
    end
    self.main_length = self.band_starts[self.layer_count] + self.thickness[self.layer_count]
    self.secondary_length = 0
    for i, value in ipairs(self.x) do self.secondary_length = math.max(self.secondary_length, value + self.coordinates.right[i] + 1) end
    self.canvas = Canvas.new(self.settings.direction, self.main_length, self.secondary_length)
    for _, edge in ipairs(self.drawn) do
        local size = vertical and 1 or self.widths[edge.upper]
        edge.upper_endpoint = {self.band_starts[self.vertex_layer[edge.upper]] + size, self.x[edge.upper]}
        edge.lower_endpoint = {self.band_starts[self.vertex_layer[edge.lower]] - 1, self.x[edge.lower]}
    end
end

function Layout:draw_lines_and_arrows()
    local vertical = self.settings.direction == "TB" or self.settings.direction == "BT"
    for vertex = 1, self.vertex_count do
        local layer = self.vertex_layer[vertex]
        local beginning = self.band_starts[layer]
        local finish = beginning + self.thickness[layer] - 1
        if vertex > self.node_count then self.canvas:main_line(beginning, finish, self.x[vertex])
        elseif not vertical and #self.lower[vertex] > 0 then self.canvas:main_line(beginning + self.widths[vertex], finish, self.x[vertex]) end
    end
    for layer, segments in ipairs(self.gaps) do
        local beginning = self.band_starts[layer] + self.thickness[layer]
        for _, segment in ipairs(segments) do
            local p, q = segment[1], segment[2]
            self.canvas:segment(beginning, self.gap_widths[layer], self.x[p], self.x[q], self.segment_offsets[segment_key(p, q)])
        end
    end
    for _, edge in ipairs(self.drawn) do self.canvas:arrow(edge.reversed and edge.upper_endpoint or edge.lower_endpoint, edge.reversed) end
end

function Layout:build_routes()
    for _, edge in ipairs(self.drawn) do
        local points, bent = {edge.upper_endpoint}, 0
        for i = 1, #edge.chain - 1 do
            local first, second = edge.chain[i], edge.chain[i + 1]
            if self.x[first] ~= self.x[second] then
                local layer = self.vertex_layer[first]
                local main = self.band_starts[layer] + self.thickness[layer] + self.segment_offsets[segment_key(first, second)]
                append(points, {main, self.x[first]})
                append(points, {main, self.x[second]})
                bent = bent + 1
            end
        end
        append(points, edge.lower_endpoint)
        local route = {}
        for _, point in ipairs(points) do append(route, self.canvas:cell(point[1], point[2])) end
        edge.route = {}
        for i = 1, #route do edge.route[i] = route[edge.reversed and #route - i + 1 or i] end
        edge.bends, edge.length = 2 * bent, 1
        for i = 1, #edge.route - 1 do
            local a, b = edge.route[i], edge.route[i + 1]
            edge.length = edge.length + math.abs(a[1] - b[1]) + math.abs(a[2] - b[2])
        end
    end
end

function Layout:find_path()
    if not self.graph.path then return end
    local start, finish = self.node_number[self.graph.path[1]], self.node_number[self.graph.path[2]]
    local following = {}
    for i = 1, self.node_count do following[i] = {} end
    for _, edge in ipairs(self.drawn) do append(following[edge.source], edge.target) end
    for _, neighbors in ipairs(following) do table.sort(neighbors) end
    local parent, pending, head = {[start] = false}, {start}, 1
    while head <= #pending do
        local vertex = pending[head]
        head = head + 1
        for _, neighbor in ipairs(following[vertex]) do
            if parent[neighbor] == nil then parent[neighbor] = vertex; append(pending, neighbor) end
        end
    end
    if parent[finish] ~= nil then
        local reverse, vertex = {}, finish
        while vertex do append(reverse, vertex); vertex = parent[vertex] end
        self.path = {}
        for i = #reverse, 1, -1 do append(self.path, reverse[i]) end
    end
end

function Layout:draw_highlights_and_boxes()
    local on_path, by_endpoints = {}, {}
    if self.path then
        for _, edge in ipairs(self.drawn) do by_endpoints[segment_key(edge.source, edge.target)] = edge end
        for _, vertex in ipairs(self.path) do on_path[vertex] = true end
        for i = 1, #self.path - 1 do self.canvas:highlight_route(by_endpoints[segment_key(self.path[i], self.path[i + 1])].route) end
    end
    for vertex = 1, self.node_count do
        self.canvas:box(self.labels[vertex], self.band_starts[self.vertex_layer[vertex]], self.x[vertex], self.coordinates.left[vertex], on_path[vertex])
    end
end

function Layout:process()
    self:analyze_graph()
    self:prepare_dag()
    self:assign_layers()
    self:insert_dummies()
    self:make_initial_order()
    for run = 0, self.settings.restarts do self:run_sweeps(run) end
    if self.settings.sifting == "on" then self:sift() end
    self:finish_crossing_counts()
    self.coordinates = Coordinates.assign(self.orders, self.upper, self.lower, self.widths, self.node_count, self.settings)
    self.x = self.coordinates.x
    self:route_geometry()
    self:draw_lines_and_arrows()
    self:build_routes()
    self:find_path()
    self:draw_highlights_and_boxes()
end

function Layout:edge_name(edge)
    return self.ids[edge.source] .. "->" .. self.ids[edge.target]
end

function Layout:display_sequence(vertices)
    local names = {}
    for _, vertex in ipairs(vertices) do append(names, self.names[vertex]) end
    return table.concat(names, " ")
end

function Layout:layer_line(layer)
    local first = self.band_starts[layer]
    local last = first + self.thickness[layer] - 1
    if self.settings.direction == "BT" or self.settings.direction == "RL" then first, last = self.main_length - 1 - last, self.main_length - 1 - first end
    local low, high, positions = math.maxinteger, math.mininteger, {}
    for _, vertex in ipairs(self.orders[layer]) do
        low, high = math.min(low, self.x[vertex] - self.coordinates.left[vertex]), math.max(high, self.x[vertex] + self.coordinates.right[vertex])
        append(positions, self.names[vertex] .. "@" .. self.x[vertex])
    end
    return string.format("layer %d band %d %d extent %d %d : %s", layer - 1, first, last, low, high, table.concat(positions, " "))
end

function Layout:vertex_line(vertex)
    local aligned = {}
    for _, variant in ipairs(Coordinates.variants) do append(aligned, variant .. " " .. self.coordinates.aligned[variant][vertex]) end
    return string.format("vertex %s layer %d pos %d %s x %d", self.names[vertex], self.vertex_layer[vertex] - 1,
        self.position[vertex], table.concat(aligned, " "), self.x[vertex])
end

function Layout:edge_line(edge)
    local beginning = "edge " .. self.ids[edge.source] .. " " .. self.ids[edge.target]
    if edge.transitive then return beginning .. " transitive" end
    if edge.reversed then beginning = beginning .. " reversed" end
    local path, route = {}, {}
    for i = 1, #edge.chain do append(path, self.x[edge.chain[edge.reversed and #edge.chain - i + 1 or i]]) end
    for _, point in ipairs(edge.route) do append(route, point[1] .. "," .. point[2]) end
    return beginning .. string.format(" span %d crossings %d bends %d path %s route %s", edge.span, edge.crossings, edge.bends,
        table.concat(path, " "), table.concat(route, " "))
end

function Layout:layout_lines()
    local lines, settings = {"graph " .. self.name}, {}
    for _, name in ipairs(Input.order) do append(settings, name .. "=" .. self.settings[name]) end
    append(lines, "settings " .. table.concat(settings, " "))
    append(lines, "acyclic " .. self:display_sequence(self.acyclic))
    if self.coffman_labels then
        local labels = {}
        for i, label in ipairs(self.coffman_labels) do append(labels, self.names[i] .. ":" .. label) end
        append(lines, "labels " .. table.concat(labels, " "))
    end
    for _, item in ipairs(self.promotions) do append(lines, string.format("promote %d %s %d", item[1], self.names[item[2]], item[3])) end
    for _, item in ipairs(self.sweep_records) do
        local line = string.format("sweep %d %d %s", item[1], item[2], item[3])
        if item[2] ~= 0 then line = line .. string.format(" moved %d swaps %d", item[4], item[5]) end
        append(lines, line .. " crossings " .. item[6])
    end
    append(lines, string.format("best run %d sweep %d crossings %d", self.best_run, self.best_sweep, self.best_crossings))
    for _, item in ipairs(self.sift_records) do append(lines, string.format("sift %d moves %d crossings %d", item[1], item[2], item[3])) end
    for layer = 1, self.layer_count do append(lines, self:layer_line(layer)) end
    for gap, segments in ipairs(self.gaps) do append(lines, string.format("between %d %d segments %d crossings %d tracks %d gap %d",
        gap - 1, gap, #segments, self.crossings_by_gap[gap], self.track_counts[gap], self.gap_widths[gap])) end
    local variants = {}
    for _, variant in ipairs(Coordinates.variants) do append(variants, variant .. "=" .. self.coordinates.blocks[variant] .. "/" .. self.coordinates.widths[variant]) end
    append(lines, string.format("bk conflicts %d %s smallest %s", count(self.coordinates.conflicts), table.concat(variants, " "), self.coordinates.smallest))
    for _, layer in ipairs(self.orders) do for _, vertex in ipairs(layer) do append(lines, self:vertex_line(vertex)) end end
    for _, edge in ipairs(self.edges) do append(lines, self:edge_line(edge)) end
    append(lines, "end")
    return lines
end

function Layout:edge_set_line(name, edges)
    local names = {}
    for _, edge in ipairs(edges) do append(names, self:edge_name(edge)) end
    return name .. " " .. #edges .. (#names > 0 and " " .. table.concat(names, " ") or "")
end

function Layout:statistics_lines()
    local lines = {"graph " .. self.name, string.format("nodes %d edges %d self_loops %d duplicates %d", self.node_count,
        #self.edges, self.graph.self_loops, self.graph.duplicates), string.format("sources %d sinks %d isolated %d components %d",
        self.sources, self.sinks, self.isolated, self.components)}
    for _, component in ipairs(self.strong_components) do append(lines, "scc " .. self:display_sequence(component)) end
    local reversed, transitive = {}, {}
    for _, edge in ipairs(self.edges) do if edge.reversed then append(reversed, edge) end; if edge.transitive then append(transitive, edge) end end
    append(lines, self:edge_set_line("reversed", reversed))
    append(lines, self:edge_set_line("transitive", transitive))
    local max_nodes, max_vertices = 0, 0
    for _, layer in ipairs(self.orders) do
        local nodes = 0
        for _, vertex in ipairs(layer) do if vertex <= self.node_count then nodes = nodes + 1 end end
        max_nodes, max_vertices = math.max(max_nodes, nodes), math.max(max_vertices, #layer)
    end
    append(lines, string.format("layers %d max_nodes %d max_vertices %d", self.layer_count, max_nodes, max_vertices))
    if self.settings.promotion == "on" then append(lines, string.format("promotion rounds %d accepted %d dummies_before %d",
        self.promotion_rounds, #self.promotions, self.dummies_before)) else append(lines, "promotion off") end
    local spans, span_total, span_max, long_edges, vertical = {}, 0, 0, 0, 0
    for _, edge in ipairs(self.drawn) do
        spans[edge.span], span_total, span_max = (spans[edge.span] or 0) + 1, span_total + edge.span, math.max(span_max, edge.span)
        if edge.span >= 2 then
            long_edges = long_edges + 1
            local same = true
            for i = 3, #edge.chain - 1 do if self.x[edge.chain[i]] ~= self.x[edge.chain[2]] then same = false; break end end
            if same then vertical = vertical + 1 end
        end
    end
    append(lines, string.format("dummies %d span_total %d span_max %d", self.vertex_count - self.node_count, span_total, span_max))
    local span_entries = {}
    for span = 1, span_max do if spans[span] then append(span_entries, span .. ":" .. spans[span]) end end
    append(lines, #span_entries == 0 and "spans none" or "spans " .. table.concat(span_entries, " "))
    append(lines, string.format("long_edges %d vertical %d", long_edges, vertical))
    append(lines, string.format("crossings initial %d swept %d best_run %d best_sweep %d final %d brute %d",
        self.initial_crossings, self.best_crossings, self.best_run, self.best_sweep, self.final_crossings, self.brute_crossings))
    local segment_count, straight, offset, route_length, bends, longest = 0, 0, 0, 0, 0, nil
    for _, gap in ipairs(self.gaps) do
        for _, segment in ipairs(gap) do
            segment_count = segment_count + 1
            if self.x[segment[1]] == self.x[segment[2]] then straight = straight + 1 end
            offset = offset + math.abs(self.x[segment[1]] - self.x[segment[2]])
        end
    end
    append(lines, string.format("segments %d straight %d bent %d offset %d", segment_count, straight, segment_count - straight, offset))
    for _, edge in ipairs(self.drawn) do
        route_length, bends = route_length + edge.length, bends + edge.bends
        if not longest or edge.length > longest.length then longest = edge end
    end
    local route_line = string.format("routes length %d bends %d", route_length, bends)
    if longest then route_line = route_line .. " longest " .. self:edge_name(longest) .. " " .. longest.length end
    append(lines, route_line)
    append(lines, string.format("canvas width %d height %d crossing_cells %d", self.canvas.columns, self.canvas.rows, self.canvas:crossing_cells()))
    if self.graph.path then
        local path_line = "path " .. self.graph.path[1] .. " " .. self.graph.path[2]
        append(lines, path_line .. (self.path and " hops " .. (#self.path - 1) .. " : " .. self:display_sequence(self.path) or " none"))
    end
    append(lines, "end")
    return lines
end

local defaults = Input.read_defaults()
local graphs = Input.read_graphs(defaults)
local layouts, statistics, crossings, drawings, totals = {}, {}, {"graph,run,sweep,crossings"}, {}, {}
for _, graph in ipairs(graphs) do
    totals.graphs = (totals.graphs or 0) + 1
    if graph.error then
        local error = {"graph " .. graph.name, string.format("error %s line %d", graph.error.kind, graph.error.line), "end"}
        extend(layouts, error)
        extend(statistics, error)
        append(drawings, {"graph " .. graph.name .. " error " .. graph.error.kind})
        totals.errors = (totals.errors or 0) + 1
    else
        local layout = Layout.new(graph)
        layout:process()
        extend(layouts, layout:layout_lines())
        extend(statistics, layout:statistics_lines())
        for _, item in ipairs(layout.sweep_records) do append(crossings, string.format("%s,%d,%d,%d", layout.name, item[1], item[2], item[6])) end
        local drawing = {string.format("graph %s %dx%d", layout.name, layout.canvas.columns, layout.canvas.rows)}
        extend(drawing, layout.canvas:drawing_lines())
        append(drawings, drawing)
        local values = {laid_out = 1, nodes = layout.node_count, edges = #layout.edges,
            dummies = layout.vertex_count - layout.node_count, crossings_initial = layout.initial_crossings, crossings_final = layout.final_crossings}
        for key, value in pairs(values) do totals[key] = (totals[key] or 0) + value end
    end
end
local entries = {}
for _, name in ipairs({"graphs", "laid_out", "errors", "nodes", "edges", "dummies", "crossings_initial", "crossings_final"}) do append(entries, name .. " " .. (totals[name] or 0)) end
append(statistics, "summary " .. table.concat(entries, " "))
assert(os.execute("mkdir -p output"))
for _, report in ipairs({{"layout.txt", layouts}, {"stats.txt", statistics}, {"crossings.csv", crossings}}) do
    local file = assert(io.open("output/" .. report[1], "wb"))
    for _, line in ipairs(report[2]) do file:write(line, "\n") end
    file:close()
end
local file = assert(io.open("output/drawings.txt", "wb"))
for i, block in ipairs(drawings) do
    if i > 1 then file:write("\n") end
    for _, line in ipairs(block) do file:write(line, "\n") end
end
file:close()
