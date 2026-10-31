local function bad(pattern, ...)
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
local function compare(a, b)
    for i = 1, math.min(#a, #b) do
        if a[i] ~= b[i] then
            return a[i] < b[i] and -1 or 1
        end
    end
    return #a == #b and 0 or #a < #b and -1 or 1
end
local function count_bits(mask)
    local count = 0
    while mask ~= 0 do
        mask = mask & (mask - 1)
        count = count + 1
    end
    return count
end
local function color_count(colors)
    local count = 0
    for _, color in ipairs(colors) do
        count = math.max(count, color + 1)
    end
    return count
end
local function cell_sizes(colors)
    local sizes = {}
    for i = 1, color_count(colors) do
        sizes[i] = 0
    end
    for _, color in ipairs(colors) do
        sizes[color + 1] = sizes[color + 1] + 1
    end
    return sizes
end
local Graph = {}
Graph.__index = Graph
function Graph.new(n)
    local adjacent = {}
    for i = 1, n do
        adjacent[i] = 0
    end
    return setmetatable({n = n, adjacent = adjacent}, Graph)
end
function Graph:has(a, b)
    return self.adjacent[a + 1] & (1 << b) ~= 0
end
function Graph:join(a, b)
    self.adjacent[a + 1] = self.adjacent[a + 1] | (1 << b)
    self.adjacent[b + 1] = self.adjacent[b + 1] | (1 << a)
end
function Graph:edges()
    local result = {}
    for a = 0, self.n - 1 do
        for b = a + 1, self.n - 1 do
            if self:has(a, b) then
                result[#result + 1] = {a, b}
            end
        end
    end
    return result
end
local function degree_colors(g)
    local degrees, unique, seen = {}, {}, {}
    for i, mask in ipairs(g.adjacent) do
        degrees[i] = count_bits(mask)
        seen[degrees[i]] = true
    end
    for value in pairs(seen) do
        unique[#unique + 1] = value
    end
    table.sort(unique)
    local rank = {}
    for i, degree in ipairs(unique) do
        rank[degree] = i - 1
    end
    for i, degree in ipairs(degrees) do
        degrees[i] = rank[degree]
    end
    return degrees
end
local function refine(g, initial)
    local current, rounds = copy(initial), 0
    while true do
        local signatures, vertices = {}, {}
        for v = 0, g.n - 1 do
            local neighbors = {}
            for w = 0, g.n - 1 do
                if g:has(v, w) then
                    neighbors[#neighbors + 1] = current[w + 1]
                end
            end
            table.sort(neighbors)
            local signature = {current[v + 1]}
            for _, color in ipairs(neighbors) do
                signature[#signature + 1] = color
            end
            signatures[v + 1], vertices[v + 1] = signature, v
        end
        table.sort(vertices, function(a, b)
            return compare(signatures[a + 1], signatures[b + 1]) < 0
        end)
        local next_colors, color = {}, 0
        for i, v in ipairs(vertices) do
            if i > 1 and compare(signatures[v + 1], signatures[vertices[i - 1] + 1]) ~= 0 then
                color = color + 1
            end
            next_colors[v + 1] = color
        end
        if color + 1 == color_count(current) then
            return current, rounds
        end
        current, rounds = next_colors, rounds + 1
    end
end
local function individualize(colors, vertex)
    local result, selected = copy(colors), colors[vertex + 1]
    for i, color in ipairs(colors) do
        if i ~= vertex + 1 and color >= selected then
            result[i] = result[i] + 1
        end
    end
    return result
end
function Graph:leaf_text(labels)
    local inverse, result = {}, {}
    for i, label in ipairs(labels) do
        inverse[label + 1] = i - 1
    end
    for a = 0, self.n - 1 do
        for b = a + 1, self.n - 1 do
            result[#result + 1] = self:has(inverse[a + 1], inverse[b + 1]) and "1" or "0"
        end
    end
    return table.concat(result)
end
function Graph:canon()
    if self.canonical then
        return self.canonical
    end
    local result = {nodes = 0, leaves = 0, text = "", best = {}}
    local function visit(colors)
        result.nodes = result.nodes + 1
        local sizes = cell_sizes(colors)
        if #sizes == self.n then
            result.leaves = result.leaves + 1
            local text = self:leaf_text(colors)
            if not result.labels or text > result.text then
                result.text, result.labels, result.best = text, copy(colors), {}
            end
            if text == result.text then
                result.best[#result.best + 1] = copy(colors)
            end
            return
        end
        local selected, size = nil, self.n + 1
        for i, count in ipairs(sizes) do
            if count > 1 and count < size then
                selected, size = i - 1, count
            end
        end
        for i, color in ipairs(colors) do
            if color == selected then
                local next_colors = refine(self, individualize(colors, i - 1))
                visit(next_colors)
            end
        end
    end
    local initial = refine(self, degree_colors(self))
    visit(initial)
    self.canonical = result
    return result
end
local function relabel(g, permutation)
    local result = Graph.new(g.n)
    for _, edge in ipairs(g:edges()) do
        result:join(permutation[edge[1] + 1], permutation[edge[2] + 1])
    end
    return result
end
function Graph:invariants()
    local result = {degrees = {}, sizes = {}, edges = #self:edges(), triangles = 0, components = 0, girth = "none", diameter = "INF", radius = "INF", bipartite = true}
    for i, mask in ipairs(self.adjacent) do
        result.degrees[i] = count_bits(mask)
    end
    table.sort(result.degrees, function(a, b)
        return a > b
    end)
    for a = 0, self.n - 1 do
        for b = a + 1, self.n - 1 do
            for c = b + 1, self.n - 1 do
                if self:has(a, b) and self:has(a, c) and self:has(b, c) then
                    result.triangles = result.triangles + 1
                end
            end
        end
    end
    local reached, coloring, shortest, diameter, radius = {}, {}, nil, 0, self.n
    for start = 0, self.n - 1 do
        local distance, parent, queue, at, eccentricity = {}, {}, {start}, 1, 0
        for i = 1, self.n do
            distance[i], parent[i] = -1, -1
        end
        distance[start + 1] = 0
        while at <= #queue do
            local v = queue[at]
            at = at + 1
            eccentricity = math.max(eccentricity, distance[v + 1])
            for w = 0, self.n - 1 do
                if self:has(v, w) then
                    if distance[w + 1] < 0 then
                        distance[w + 1], parent[w + 1] = distance[v + 1] + 1, v
                        queue[#queue + 1] = w
                    elseif parent[v + 1] ~= w then
                        local length = distance[v + 1] + distance[w + 1] + 1
                        shortest = shortest and math.min(shortest, length) or length
                    end
                end
            end
        end
        if not reached[start + 1] then
            result.components = result.components + 1
            result.sizes[#result.sizes + 1] = #queue
            for _, v in ipairs(queue) do
                reached[v + 1] = true
            end
            coloring[start + 1] = 1
            local pending, position = {start}, 1
            while position <= #pending do
                local v = pending[position]
                position = position + 1
                for w = 0, self.n - 1 do
                    if self:has(v, w) then
                        if not coloring[w + 1] then
                            coloring[w + 1] = -coloring[v + 1]
                            pending[#pending + 1] = w
                        elseif coloring[w + 1] == coloring[v + 1] then
                            result.bipartite = false
                        end
                    end
                end
            end
        end
        diameter, radius = math.max(diameter, eccentricity), math.min(radius, eccentricity)
    end
    table.sort(result.sizes, function(a, b)
        return a > b
    end)
    if shortest then
        result.girth = tostring(shortest)
    end
    if result.components == 1 then
        result.diameter, result.radius = tostring(diameter), tostring(radius)
    end
    return result
end
function Graph:clique()
    local best = {}
    for mask = 1, (1 << self.n) - 1 do
        if count_bits(mask) >= #best then
            local vertices, valid = {}, true
            for v = 0, self.n - 1 do
                if mask & (1 << v) ~= 0 then
                    vertices[#vertices + 1] = v
                    if mask & ~(self.adjacent[v + 1] | (1 << v)) ~= 0 then
                        valid = false
                        break
                    end
                end
            end
            if valid and (#vertices > #best or compare(vertices, best) < 0) then
                best = vertices
            end
        end
    end
    return best
end
function Graph:chromatic()
    local colors = {}
    local function search(v, limit)
        if v == self.n then
            return true
        end
        for color = 0, limit - 1 do
            local valid = true
            for w = 0, v - 1 do
                if self:has(v, w) and colors[w + 1] == color then
                    valid = false
                    break
                end
            end
            if valid then
                colors[v + 1] = color
                if search(v + 1, limit) then
                    return true
                end
            end
        end
        return false
    end
    for limit = 1, self.n do
        if search(0, limit) then
            return limit, colors
        end
    end
end
local function number_word(text)
    return #text >= 1 and #text <= 3 and text:match("^[0-9]+$") ~= nil and (#text == 1 or text:sub(1, 1) ~= "0")
end
local function name_word(text)
    return #text >= 1 and #text <= 8 and text:match("^[a-z][a-z0-9]*$") ~= nil
end
local function edge_word(text)
    local p = split(text, "-")
    return #p == 2 and number_word(p[1]) and number_word(p[2])
end
local function contains(list, item)
    for _, value in ipairs(list) do
        if value == item then
            return true
        end
    end
    return false
end
local function yes(value)
    return value and "yes" or "no"
end
local definitions = {"GRAPH", "CYCLE", "PATH", "COMPLETE", "BIPARTITE", "STAR", "WHEEL", "PETERSEN", "HYPERCUBE", "CIRCULANT", "GRID", "COMPLEMENT", "LINE", "PRODUCT", "UNION", "RELABEL", "INDUCED", "CANONIZE"}
local function dsu(n)
    local result = {parents = {}}
    for i = 1, n do
        result.parents[i] = i - 1
    end
    function result:find(x)
        if self.parents[x + 1] ~= x then
            self.parents[x + 1] = self:find(self.parents[x + 1])
        end
        return self.parents[x + 1]
    end
    function result:union(a, b)
        a, b = self:find(a), self:find(b)
        if a ~= b then
            self.parents[b + 1] = a
        end
    end
    function result:groups()
        local groups, where = {}, {}
        for i = 0, #self.parents - 1 do
            local root = self:find(i)
            if not where[root] then
                groups[#groups + 1] = {}
                where[root] = #groups
            end
            local group = groups[where[root]]
            group[#group + 1] = i
        end
        return groups
    end
    return result
end
local Lab = {}
Lab.__index = Lab
function Lab.new()
    return setmetatable({graphs = {}, output = {}}, Lab)
end
function Lab:emit(pattern, ...)
    self.output[#self.output + 1] = string.format(pattern, ...)
end
function Lab:automorphisms(name, g)
    local data, edges = g:canon(), g:edges()
    local vertices, edge_sets, inverse, edge_numbers = dsu(g.n), dsu(#edges), {}, {}
    for i, label in ipairs(data.labels) do
        inverse[label + 1] = i - 1
    end
    for i, edge in ipairs(edges) do
        edge_numbers[edge[1] .. "," .. edge[2]] = i - 1
    end
    for _, labeling in ipairs(data.best) do
        local sigma = {}
        for i, label in ipairs(labeling) do
            sigma[i] = inverse[label + 1]
            vertices:union(i - 1, sigma[i])
        end
        for i, edge in ipairs(edges) do
            local a, b = sigma[edge[1] + 1], sigma[edge[2] + 1]
            if a > b then
                a, b = b, a
            end
            edge_sets:union(i - 1, edge_numbers[a .. "," .. b])
        end
    end
    local vertex_orbits, edge_orbits = vertices:groups(), edge_sets:groups()
    self:emit("aut %s order %d", name, #data.best)
    self:emit("vertex orbits %d", #vertex_orbits)
    for _, orbit in ipairs(vertex_orbits) do
        self:emit("orbit %s", table.concat(orbit, " "))
    end
    self:emit("edge orbits %d", #edge_orbits)
    for _, orbit in ipairs(edge_orbits) do
        local words = {}
        for _, index in ipairs(orbit) do
            local edge = edges[index + 1]
            words[#words + 1] = edge[1] .. "-" .. edge[2]
        end
        self:emit("orbit %s", table.concat(words, " "))
    end
    self:emit("transitive vertex %s edge %s", yes(#vertex_orbits == 1), yes(#edge_orbits == 1))
end
function Lab:subiso(a_name, b_name, pattern, target)
    local embeddings, induced, examples, mapping, used = 0, 0, {}, {}, {}
    local function search(v, is_induced)
        if v == pattern.n then
            embeddings = embeddings + 1
            if is_induced then
                induced = induced + 1
            end
            if #examples < 5 then
                examples[#examples + 1] = {mapping = copy(mapping), induced = is_induced}
            end
            return
        end
        for w = 0, target.n - 1 do
            if not used[w + 1] then
                local valid, next_induced = true, is_induced
                for u = 0, v - 1 do
                    if pattern:has(u, v) and not target:has(mapping[u + 1], w) then
                        valid = false
                        break
                    end
                    if not pattern:has(u, v) and target:has(mapping[u + 1], w) then
                        next_induced = false
                    end
                end
                if valid then
                    mapping[v + 1], used[w + 1] = w, true
                    search(v + 1, next_induced)
                    used[w + 1] = nil
                end
            end
        end
    end
    if pattern.n <= target.n then
        search(0, true)
    end
    local order = #pattern:canon().best
    self:emit("subiso %s %s embeddings %d induced %d", a_name, b_name, embeddings, induced)
    self:emit("copies %d induced %d", embeddings // order, induced // order)
    for _, example in ipairs(examples) do
        self:emit("embedding %s%s", table.concat(example.mapping, " "), example.induced and " induced" or "")
    end
end
function Lab:command(words)
    local command, args = words[1], {}
    for i = 2, #words do
        args[#args + 1] = words[i]
    end
    local defining = contains(definitions, command)
    if not defining and not contains({"DELETE", "LIST", "SHOW", "INVARIANTS", "REFINE", "CANON", "ISO", "AUT", "SUBISO", "CLASSIFY"}, command) then
        bad("unknown command %s", command)
    end
    local minimum, maximum = 1, 1
    if command == "LIST" then
        minimum, maximum = 0, 0
    elseif command == "GRAPH" or command == "RELABEL" or command == "REFINE" then
        minimum, maximum = command == "REFINE" and 1 or 2, nil
    elseif command == "CIRCULANT" or command == "INDUCED" then
        minimum, maximum = 3, nil
    elseif contains({"BIPARTITE", "GRID", "PRODUCT", "UNION"}, command) then
        minimum, maximum = 3, 3
    elseif contains({"CYCLE", "PATH", "COMPLETE", "STAR", "WHEEL", "HYPERCUBE", "COMPLEMENT", "LINE", "CANONIZE", "ISO", "SUBISO"}, command) then
        minimum, maximum = 2, 2
    end
    if #args < minimum or maximum and #args > maximum then
        bad("bad arguments")
    end
    local name_positions, existing = {}, {}
    if defining then
        name_positions[1] = true
    end
    if contains({"COMPLEMENT", "LINE", "RELABEL", "INDUCED", "CANONIZE"}, command) then
        existing = {2}
    elseif command == "PRODUCT" or command == "UNION" then
        existing = {2, 3}
    elseif contains({"DELETE", "SHOW", "INVARIANTS", "REFINE", "CANON", "AUT"}, command) then
        existing = {1}
    elseif command == "ISO" or command == "SUBISO" then
        existing = {1, 2}
    end
    for _, i in ipairs(existing) do
        name_positions[i] = true
    end
    for i, arg in ipairs(args) do
        local valid
        if name_positions[i] then
            valid = name_word(arg)
        elseif command == "GRAPH" and i > 2 then
            valid = edge_word(arg)
        else
            valid = number_word(arg)
        end
        if not valid then
            bad("bad arguments")
        end
    end
    for _, i in ipairs(existing) do
        if not self.graphs[args[i]] then
            bad("no graph %s", args[i])
        end
    end
    local g
    if defining then
        local function source(i)
            return self.graphs[args[i]]
        end
        if contains({"GRAPH", "CYCLE", "PATH", "COMPLETE", "STAR", "WHEEL", "HYPERCUBE", "CIRCULANT"}, command) then
            local n, lower, upper = tonumber(args[2]), 1, 16
            if command == "CYCLE" or command == "CIRCULANT" then
                lower = 3
            end
            if command == "WHEEL" then
                lower, upper = 3, 15
            elseif command == "STAR" then
                upper = 15
            elseif command == "HYPERCUBE" then
                upper = 4
            end
            if n < lower then
                bad("bad value")
            end
            if n > upper then
                bad("too large")
            end
            if command == "STAR" or command == "WHEEL" then
                n = n + 1
            elseif command == "HYPERCUBE" then
                n = 1 << n
            end
            g = Graph.new(n)
            if command == "GRAPH" then
                for i = 3, #args do
                    local fields = split(args[i], "-")
                    local a, b = tonumber(fields[1]), tonumber(fields[2])
                    if a >= n or b >= n or a == b then
                        bad("bad edge %s", args[i])
                    end
                    if g:has(a, b) then
                        bad("duplicate edge %s", args[i])
                    end
                    g:join(a, b)
                end
            elseif command == "CYCLE" then
                for v = 0, n - 1 do
                    g:join(v, (v + 1) % n)
                end
            elseif command == "PATH" then
                for v = 0, n - 2 do
                    g:join(v, v + 1)
                end
            elseif command == "COMPLETE" then
                for a = 0, n - 1 do
                    for b = a + 1, n - 1 do
                        g:join(a, b)
                    end
                end
            elseif command == "STAR" or command == "WHEEL" then
                for v = 1, n - 1 do
                    g:join(0, v)
                    if command == "WHEEL" then
                        g:join(v, v == n - 1 and 1 or v + 1)
                    end
                end
            elseif command == "HYPERCUBE" then
                for v = 0, n - 1 do
                    local bit = 1
                    while bit < n do
                        g:join(v, v ~ bit)
                        bit = bit << 1
                    end
                end
            else
                local previous = 0
                for i = 3, #args do
                    local jump = tonumber(args[i])
                    if jump <= previous or 2 * jump > n then
                        bad("bad value")
                    end
                    for v = 0, n - 1 do
                        g:join(v, (v + jump) % n)
                    end
                    previous = jump
                end
            end
        elseif command == "BIPARTITE" or command == "GRID" then
            local a, b = tonumber(args[2]), tonumber(args[3])
            if a == 0 or b == 0 then
                bad("bad value")
            end
            local n = command == "GRID" and a * b or a + b
            if n > 16 then
                bad("too large")
            end
            g = Graph.new(n)
            for x = 0, a - 1 do
                for y = 0, b - 1 do
                    if command == "BIPARTITE" then
                        g:join(x, a + y)
                    else
                        if y + 1 < b then
                            g:join(x * b + y, x * b + y + 1)
                        end
                        if x + 1 < a then
                            g:join(x * b + y, (x + 1) * b + y)
                        end
                    end
                end
            end
        elseif command == "PETERSEN" then
            g = Graph.new(10)
            for i = 0, 4 do
                g:join(i, (i + 1) % 5)
                g:join(i, i + 5)
                g:join(i + 5, 5 + (i + 2) % 5)
            end
        elseif command == "COMPLEMENT" then
            local a = source(2)
            g = Graph.new(a.n)
            for x = 0, a.n - 1 do
                for y = x + 1, a.n - 1 do
                    if not a:has(x, y) then
                        g:join(x, y)
                    end
                end
            end
        elseif command == "LINE" then
            local edges = source(2):edges()
            if #edges == 0 then
                bad("no edges")
            end
            if #edges > 16 then
                bad("too large")
            end
            g = Graph.new(#edges)
            for i, a in ipairs(edges) do
                for j = i + 1, #edges do
                    local b = edges[j]
                    if a[1] == b[1] or a[1] == b[2] or a[2] == b[1] or a[2] == b[2] then
                        g:join(i - 1, j - 1)
                    end
                end
            end
        elseif command == "PRODUCT" or command == "UNION" then
            local a, b = source(2), source(3)
            local n = command == "PRODUCT" and a.n * b.n or a.n + b.n
            if n > 16 then
                bad("too large")
            end
            g = Graph.new(n)
            if command == "UNION" then
                for _, edge in ipairs(a:edges()) do
                    g:join(edge[1], edge[2])
                end
                for _, edge in ipairs(b:edges()) do
                    g:join(edge[1] + a.n, edge[2] + a.n)
                end
            else
                for x = 0, a.n - 1 do
                    for _, edge in ipairs(b:edges()) do
                        g:join(x * b.n + edge[1], x * b.n + edge[2])
                    end
                end
                for y = 0, b.n - 1 do
                    for _, edge in ipairs(a:edges()) do
                        g:join(edge[1] * b.n + y, edge[2] * b.n + y)
                    end
                end
            end
        elseif command == "RELABEL" or command == "INDUCED" then
            local a, values, seen = source(2), {}, {}
            if command == "RELABEL" and #args - 2 ~= a.n then
                bad("bad permutation")
            end
            for i = 3, #args do
                local value = tonumber(args[i])
                if value >= a.n or seen[value] then
                    bad(command == "RELABEL" and "bad permutation" or "bad vertices")
                end
                seen[value] = true
                values[#values + 1] = value
            end
            if command == "RELABEL" then
                g = relabel(a, values)
            else
                g = Graph.new(#values)
                for i, x in ipairs(values) do
                    for j = i + 1, #values do
                        if a:has(x, values[j]) then
                            g:join(i - 1, j - 1)
                        end
                    end
                end
            end
        else
            g = relabel(source(2), source(2):canon().labels)
        end
        local action = self.graphs[args[1]] and "redefined" or "defined"
        self.graphs[args[1]] = g
        self:emit("%s %s n %d m %d", action, args[1], g.n, #g:edges())
        return
    end
    if #existing > 0 then
        g = self.graphs[args[1]]
    end
    if command == "DELETE" then
        self.graphs[args[1]] = nil
        self:emit("deleted %s", args[1])
    elseif command == "LIST" then
        local names = {}
        for name in pairs(self.graphs) do
            names[#names + 1] = name
        end
        table.sort(names)
        self:emit("graphs %d", #names)
        for _, name in ipairs(names) do
            local graph = self.graphs[name]
            self:emit("%s n %d m %d", name, graph.n, #graph:edges())
        end
    elseif command == "SHOW" then
        self:emit("graph %s n %d m %d", args[1], g.n, #g:edges())
        for v = 0, g.n - 1 do
            local neighbors = {}
            for w = 0, g.n - 1 do
                if g:has(v, w) then
                    neighbors[#neighbors + 1] = w
                end
            end
            self:emit("%d:%s", v, #neighbors == 0 and "" or " " .. table.concat(neighbors, " "))
        end
    elseif command == "INVARIANTS" then
        local data = g:invariants()
        self:emit("invariants %s", args[1])
        self:emit("degrees %s", table.concat(data.degrees, " "))
        self:emit("edges %d triangles %d", data.edges, data.triangles)
        self:emit("components %d sizes %s", data.components, table.concat(data.sizes, " "))
        self:emit("girth %s diameter %s radius %s", data.girth, data.diameter, data.radius)
        self:emit("bipartite %s", yes(data.bipartite))
        if g.n > 12 then
            self:emit("clique -")
            self:emit("chromatic -")
        else
            local clique = g:clique()
            local chromatic, colors = g:chromatic()
            self:emit("clique %d %s", #clique, table.concat(clique, " "))
            self:emit("chromatic %d %s", chromatic, table.concat(colors, " "))
        end
    elseif command == "REFINE" then
        for i = 2, #args do
            if tonumber(args[i]) >= g.n then
                bad("bad vertices")
            end
        end
        local colors, rounds = refine(g, degree_colors(g))
        for i = 2, #args do
            local v = tonumber(args[i])
            if cell_sizes(colors)[colors[v + 1] + 1] == 1 then
                bad("singleton %d", v)
            end
            local next_colors, count = refine(g, individualize(colors, v))
            colors, rounds = next_colors, rounds + count
        end
        self:emit("refine %s rounds %d cells %d", args[1], rounds, color_count(colors))
        for color = 0, color_count(colors) - 1 do
            local vertices = {}
            for i, c in ipairs(colors) do
                if c == color then
                    vertices[#vertices + 1] = i - 1
                end
            end
            self:emit("%d: %s", color, table.concat(vertices, " "))
        end
    elseif command == "CANON" then
        local data = g:canon()
        self:emit("canon %s nodes %d leaves %d", args[1], data.nodes, data.leaves)
        self:emit("labels %s", table.concat(data.labels, " "))
        self:emit("string %s", data.text == "" and "-" or data.text)
    elseif command == "ISO" then
        local b = self.graphs[args[2]]
        local a_data, b_data = g:invariants(), b:invariants()
        local message
        if g.n ~= b.n then
            message = string.format("vertices %d %d", g.n, b.n)
        elseif a_data.edges ~= b_data.edges then
            message = string.format("edges %d %d", a_data.edges, b_data.edges)
        elseif compare(a_data.degrees, b_data.degrees) ~= 0 then
            message = "degrees"
        elseif a_data.triangles ~= b_data.triangles then
            message = string.format("triangles %d %d", a_data.triangles, b_data.triangles)
        elseif a_data.components ~= b_data.components then
            message = string.format("components %d %d", a_data.components, b_data.components)
        elseif a_data.girth ~= b_data.girth then
            message = "girth " .. a_data.girth .. " " .. b_data.girth
        elseif a_data.diameter ~= b_data.diameter then
            message = "diameter " .. a_data.diameter .. " " .. b_data.diameter
        elseif a_data.bipartite ~= b_data.bipartite then
            message = "bipartite " .. yes(a_data.bipartite) .. " " .. yes(b_data.bipartite)
        else
            local ac, ar = refine(g, degree_colors(g))
            local bc, br = refine(b, degree_colors(b))
            if ar ~= br or compare(cell_sizes(ac), cell_sizes(bc)) ~= 0 then
                message = "refinement"
            elseif g:canon().text ~= b:canon().text then
                message = "canonical"
            end
        end
        if message then
            self:emit("not isomorphic %s", message)
        else
            local a, other, inverse, mapping = g:canon(), b:canon(), {}, {}
            for i, label in ipairs(other.labels) do
                inverse[label + 1] = i - 1
            end
            for i, label in ipairs(a.labels) do
                mapping[i] = inverse[label + 1]
            end
            self:emit("isomorphic")
            self:emit("mapping %s", table.concat(mapping, " "))
        end
    elseif command == "AUT" then
        self:automorphisms(args[1], g)
    elseif command == "SUBISO" then
        self:subiso(args[1], args[2], g, self.graphs[args[2]])
    elseif command == "CLASSIFY" then
        local n = tonumber(args[1])
        if n == 0 then
            bad("bad value")
        end
        if n > 5 then
            bad("too large")
        end
        local current, levels, total = {[string.rep("0", n * (n - 1) // 2)] = true}, {}, 0
        for _ = 0, n * (n - 1) // 2 do
            local level = {}
            for text in pairs(current) do
                level[#level + 1] = text
            end
            table.sort(level)
            levels[#levels + 1] = level
            total = total + #level
            local next_level = {}
            for _, text in ipairs(level) do
                local source, index = Graph.new(n), 1
                for a = 0, n - 1 do
                    for b = a + 1, n - 1 do
                        if text:sub(index, index) == "1" then
                            source:join(a, b)
                        end
                        index = index + 1
                    end
                end
                for a = 0, n - 1 do
                    for b = a + 1, n - 1 do
                        if not source:has(a, b) then
                            local changed = Graph.new(n)
                            changed.adjacent = copy(source.adjacent)
                            changed:join(a, b)
                            next_level[changed:canon().text] = true
                        end
                    end
                end
            end
            current = next_level
        end
        self:emit("classify %d total %d", n, total)
        for i, level in ipairs(levels) do
            local output = {}
            for j, text in ipairs(level) do
                output[j] = text == "" and "-" or text
            end
            self:emit("edges %d count %d %s", i - 1, #level, table.concat(output, " "))
        end
    end
end
local lab = Lab.new()
local n = tonumber(io.read("*l"))
for _ = 1, n do
    local line = io.read("*l")
    local ok, message = pcall(Lab.command, lab, split(line, " "))
    if not ok then
        lab:emit("error: %s", message)
    end
end
io.write(table.concat(lab.output, "\n"), "\n")
