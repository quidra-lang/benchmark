local predicates = require("predicates")
local triangulation = require("triangulation")
local voronoi = require("voronoi")
local proximity = require("proximity")
local plot = require("plot")
local function words(values)
    return table.concat(values, " ")
end
local function real(value)
    local result = string.format("%.3f", value)
    return result == "-0.000" and "0.000" or result
end
local function append(target, source)
    for _, value in ipairs(source) do
        target[#target + 1] = value
    end
end
local function fields(line)
    local result = {}
    for value in line:gmatch("%S+") do
        result[#result + 1] = value
    end
    return result
end
local function zeros(count)
    local result = {}
    for i = 1, count do
        result[i] = 0
    end
    return result
end
local function read_points()
    local points, rejected, accepted, line_count = {}, {}, {}, 0
    for line in io.lines("input/points.txt") do
        line_count = line_count + 1
        if #line > 0 and line:sub(1, 1) ~= "#" then
            local values = fields(line)
            if #values ~= 2 or not values[1]:match("^%-?%d+$") or not values[2]:match("^%-?%d+$") then
                rejected[#rejected + 1] = "reject " .. line_count .. " format"
            else
                local x, y = tonumber(values[1]), tonumber(values[2])
                local key = x .. ":" .. y
                if x < 0 or x > 1000 or y < 0 or y > 1000 then
                    rejected[#rejected + 1] = "reject " .. line_count .. " range"
                elseif accepted[key] then
                    rejected[#rejected + 1] = "reject " .. line_count .. " duplicate " .. accepted[key]
                else
                    points[#points + 1] = {x, y}
                    accepted[key] = #points
                end
            end
        end
    end
    return points, line_count, rejected
end
local function read_params()
    local params = {plot = {61, 31}, plot_layers = {"edges", "hull", "sites"}, sections = {"summary"}, alpha = {}, queries = {}}
    for line in io.lines("input/params.txt") do
        if #line > 0 and line:sub(1, 1) ~= "#" then
            local values = fields(line)
            local name = table.remove(values, 1)
            if name == "query" then
                params.queries[#params.queries + 1] = line:sub(7)
            else
                if name == "plot" or name == "alpha" then
                    for i, value in ipairs(values) do
                        values[i] = tonumber(value)
                    end
                end
                params[name] = values
            end
        end
    end
    return params
end
local Report = {}
Report.__index = Report
local function report(points, line_count, rejected, params)
    return setmetatable({points = points, n = #points, line_count = line_count, rejected = rejected,
        params = params, shortest_paths = {}}, Report)
end
function Report:build()
    local points, n = self.points, self.n
    self.mesh = triangulation.new(points)
    self.insertions = {}
    for site = 4, n do
        local insertion = self.mesh:insert(site)
        insertion.site = site
        self.insertions[#self.insertions + 1] = insertion
    end
    self.triangles = self.mesh:triangles()
    self.edge_triangles, self.edge_index = {}, {}
    for site = 1, n do
        self.edge_triangles[site], self.edge_index[site] = {}, {}
    end
    for number, triangle in ipairs(self.triangles) do
        local a, b, c = table.unpack(triangle)
        self.edge_triangles[a][b], self.edge_triangles[b][c], self.edge_triangles[c][a] = number, number, number
    end
    self.edges, self.length2 = {}, {}
    for i = 1, n - 1 do
        for j = i + 1, n do
            if self.mesh.directed[i][j] or self.mesh.directed[j][i] then
                local index = #self.edges + 1
                self.edges[index], self.length2[index] = {i, j}, predicates.d2(points[i], points[j])
                self.edge_index[i][j], self.edge_index[j][i] = index, index
            end
        end
    end
    self.hull_next, self.hull_prev = {}, {}
    local start
    for _, edge in ipairs(self.mesh:hull_edges()) do
        self.hull_next[edge[1]], self.hull_prev[edge[2]] = edge[2], edge[1]
        start = start and math.min(start, edge[1]) or edge[1]
    end
    self.hull, self.hull_edges = {start}, {}
    while self.hull_next[self.hull[#self.hull]] ~= start do
        self.hull[#self.hull + 1] = self.hull_next[self.hull[#self.hull]]
    end
    self.hull_perimeter, self.hull_area2 = 0.0, 0
    for i, u in ipairs(self.hull) do
        local v = self.hull[i % #self.hull + 1]
        self.hull_edges[#self.hull_edges + 1] = {u, v}
        self.hull_perimeter = self.hull_perimeter + math.sqrt(predicates.d2(points[u], points[v]))
        self.hull_area2 = self.hull_area2 + (points[u][1] * points[v][2] - points[v][1] * points[u][2])
    end
    local adjacent = {}
    for site = 1, n do
        adjacent[site] = {}
    end
    for _, edge in ipairs(self.edges) do
        local i, j = table.unpack(edge)
        adjacent[i][#adjacent[i] + 1], adjacent[j][#adjacent[j] + 1] = j, i
    end
    self.neighbors, self.degree = {}, {}
    for site = 1, n do
        self.neighbors[site] = voronoi.neighbors(site, adjacent[site], self.mesh.directed, self.hull_next)
        self.degree[site] = #self.neighbors[site]
    end
end
function Report:analyze_triangles()
    self.area2, self.kind, self.min_angles, self.max_angles = {}, {}, {}, {}
    self.kind_counts, self.angle_bins, self.min_angle_total = {acute = 0, right = 0, obtuse = 0}, zeros(6), 0.0
    for number, triangle in ipairs(self.triangles) do
        local a, b, c = self.points[triangle[1]], self.points[triangle[2]], self.points[triangle[3]]
        local area = predicates.orient(a, b, c)
        local products = {predicates.dot(a, b, c), predicates.dot(b, c, a), predicates.dot(c, a, b)}
        local lengths = {predicates.d2(b, c), predicates.d2(c, a), predicates.d2(a, b)}
        local kind = "acute"
        if products[1] == 0 or products[2] == 0 or products[3] == 0 then
            kind = "right"
        elseif math.min(table.unpack(products)) < 0 then
            kind = "obtuse"
        end
        local shortest, longest = 1, 1
        for i = 2, 3 do
            if lengths[i] < lengths[shortest] then
                shortest = i
            end
            if lengths[i] > lengths[longest] then
                longest = i
            end
        end
        local minimum = math.atan(area, products[shortest]) * 180.0 / math.pi
        local maximum = math.atan(area, products[longest]) * 180.0 / math.pi
        self.area2[number], self.kind[number], self.min_angles[number], self.max_angles[number] = area, kind, minimum, maximum
        self.kind_counts[kind] = self.kind_counts[kind] + 1
        local bin = math.floor(minimum / 10.0) + 1
        self.angle_bins[bin] = self.angle_bins[bin] + 1
        self.min_angle_total = self.min_angle_total + minimum
        if not self.minimum_triangle or minimum < self.min_angles[self.minimum_triangle] then
            self.minimum_triangle = number
        end
        if not self.maximum_triangle or maximum > self.max_angles[self.maximum_triangle] then
            self.maximum_triangle = number
        end
    end
end
function Report:analyze_voronoi()
    self.centers, self.radius2, self.positions = {}, {}, {}
    self.position_counts, self.duals = {inside = 0, on = 0, outside = 0}, {}
    self.empty_candidates, self.empty_vertex = {}, nil
    for number, triangle in ipairs(self.triangles) do
        local a, b, c = self.points[triangle[1]], self.points[triangle[2]], self.points[triangle[3]]
        local center = predicates.center(a, b, c)
        local position = voronoi.position(center, self.points, self.hull)
        self.centers[number], self.positions[number], self.radius2[number] = center, position, voronoi.radius2(a, b, c)
        self.position_counts[position] = self.position_counts[position] + 1
        if position == "inside" then
            self.empty_candidates[#self.empty_candidates + 1] = number
            if not self.empty_vertex or self.radius2[number] > self.radius2[self.empty_vertex] then
                self.empty_vertex = number
            end
        end
    end
    for index, edge in ipairs(self.edges) do
        local i, j = table.unpack(edge)
        local left, right = self.edge_triangles[i][j], self.edge_triangles[j][i]
        if left and right then
            self.duals[index] = "segment " .. left .. " " .. right
        else
            local u, v = i, j
            if not left then
                u, v = j, i
            end
            self.duals[index] = "ray " .. (left or right) .. " " .. words(voronoi.outward(self.points, u, v))
        end
    end
    self.cells, self.cell_total, self.clip_total, self.largest_cell = {}, 0.0, 0.0, nil
    for site = 1, self.n do
        local vertices, centers = {}, {}
        for _, other in ipairs(self.neighbors[site]) do
            local number = self.edge_triangles[site][other]
            if number then
                vertices[#vertices + 1], centers[#centers + 1] = number, self.centers[number]
            end
        end
        local cell = {vertices = vertices, clip = voronoi.clipped_area(self.points, site, self.neighbors[site])}
        if self.hull_next[site] then
            cell.incoming = voronoi.outward(self.points, site, self.hull_next[site])
            cell.outgoing = voronoi.outward(self.points, self.hull_prev[site], site)
        else
            cell.area = voronoi.bounded_area(self.points[site], centers)
            self.cell_total = self.cell_total + cell.area
            if not self.largest_cell or cell.area > self.cells[self.largest_cell].area then
                self.largest_cell = site
            end
        end
        self.clip_total = self.clip_total + cell.clip
        self.cells[site] = cell
    end
end
function Report:analyze_proximity()
    self.nearest = proximity.nearest(self.points, self.neighbors)
    self.mutual_pairs = {}
    for site, other in ipairs(self.nearest) do
        if site < other and self.nearest[other] == site then
            self.mutual_pairs[#self.mutual_pairs + 1] = {site, other}
        end
    end
    self.closest = 1
    for index = 2, #self.edges do
        if self.length2[index] < self.length2[self.closest] then
            self.closest = index
        end
    end
    self.components = proximity.components(self.nearest)
    self.component_number, self.component_pairs = {}, {}
    for number, group in ipairs(self.components) do
        for _, site in ipairs(group) do
            self.component_number[site] = number
            local other = self.nearest[site]
            if site < other and self.nearest[other] == site then
                self.component_pairs[number] = {site, other}
            end
        end
    end
    self.mst = proximity.kruskal(self.points, self.edges)
    self.mst_set, self.gabriel, self.rng, self.mst_length = {}, {}, {}, 0.0
    self.graph_degrees = {gg = zeros(self.n), rng = zeros(self.n), mst = zeros(self.n)}
    for _, edge in ipairs(self.mst) do
        local i, j = table.unpack(edge)
        self.mst_set[self.edge_index[i][j]] = true
        self.mst_length = self.mst_length + math.sqrt(predicates.d2(self.points[i], self.points[j]))
        self.graph_degrees.mst[i], self.graph_degrees.mst[j] = self.graph_degrees.mst[i] + 1, self.graph_degrees.mst[j] + 1
    end
    self.gabriel_count, self.rng_count = 0, 0
    for index, edge in ipairs(self.edges) do
        local i, j = table.unpack(edge)
        if proximity.gabriel(self.points, edge, self.mesh.directed) then
            self.gabriel[index], self.gabriel_count = true, self.gabriel_count + 1
            self.graph_degrees.gg[i], self.graph_degrees.gg[j] = self.graph_degrees.gg[i] + 1, self.graph_degrees.gg[j] + 1
        end
        if proximity.relative(self.points, edge) then
            self.rng[index], self.rng_count = true, self.rng_count + 1
            self.graph_degrees.rng[i], self.graph_degrees.rng[j] = self.graph_degrees.rng[i] + 1, self.graph_degrees.rng[j] + 1
        end
    end
end
local function circle_basis(points, basis)
    if #basis == 3 and predicates.orient(points[basis[1]], points[basis[2]], points[basis[3]]) < 0 then
        basis[2], basis[3] = basis[3], basis[2]
    end
    return basis
end
local function circle_value(points, basis, point)
    if #basis == 1 then
        return -predicates.d2(points[basis[1]], point)
    elseif #basis == 2 then
        return -predicates.dot(point, points[basis[1]], points[basis[2]])
    end
    return predicates.incircle(points[basis[1]], points[basis[2]], points[basis[3]], point)
end
function Report:enclosing_circle()
    local points, basis = self.points, nil
    for i, site in ipairs(self.hull) do
        if not basis or circle_value(points, basis, points[site]) < 0 then
            basis = {site}
            for j = 1, i - 1 do
                local second = self.hull[j]
                if circle_value(points, basis, points[second]) < 0 then
                    basis = {site, second}
                    for k = 1, j - 1 do
                        local third = self.hull[k]
                        if circle_value(points, basis, points[third]) < 0 then
                            basis = circle_basis(points, {site, second, third})
                        end
                    end
                end
            end
        end
    end
    local boundary = {}
    for site = 1, self.n do
        if circle_value(points, basis, points[site]) == 0 then
            boundary[#boundary + 1] = site
        end
    end
    local diameter
    for i = 1, #boundary - 1 do
        for j = i + 1, #boundary do
            local a, b, valid = boundary[i], boundary[j], true
            for _, other in ipairs(boundary) do
                if predicates.dot(points[other], points[a], points[b]) ~= 0 then
                    valid = false
                end
            end
            if valid then
                diameter = {a, b}
                break
            end
        end
        if diameter then
            break
        end
    end
    if diameter then
        local a, b = points[diameter[1]], points[diameter[2]]
        self.enclosing_center = {a[1] + b[1], a[2] + b[2], 2}
        self.enclosing_radius2 = predicates.d2(a, b) / 4.0
    else
        local ordered = circle_basis(points, {table.unpack(boundary)})
        local a, b, c = points[ordered[1]], points[ordered[2]], points[ordered[3]]
        self.enclosing_center, self.enclosing_radius2 = predicates.center(a, b, c), voronoi.radius2(a, b, c)
    end
    self.enclosing_sites = boundary
end
function Report:analyze_extent()
    local points = self.points
    self.diameter, self.diameter2 = {1, 2}, predicates.d2(points[1], points[2])
    for i = 1, self.n - 1 do
        for j = i + 1, self.n do
            local value = predicates.d2(points[i], points[j])
            if value > self.diameter2 then
                self.diameter, self.diameter2 = {i, j}, value
            end
        end
    end
    for _, edge in ipairs(self.hull_edges) do
        local a, b = points[edge[1]], points[edge[2]]
        local maximum = 0
        for _, site in ipairs(self.hull) do
            maximum = math.max(maximum, predicates.orient(a, b, points[site]))
        end
        local width = maximum / math.sqrt(predicates.d2(a, b))
        if not self.width or width < self.width then
            self.width, self.width_edge = width, edge
        end
    end
    self:enclosing_circle()
end
function Report:analyze_layers()
    local remaining = {}
    for site = 1, self.n do
        remaining[site] = site
    end
    self.layers, self.depth = {}, {}
    while #remaining > 0 do
        local layer
        if #remaining <= 2 then
            layer = {table.unpack(remaining)}
            table.sort(layer)
        else
            local ordered = {table.unpack(remaining)}
            table.sort(ordered, function(a, b)
                if self.points[a][1] ~= self.points[b][1] then
                    return self.points[a][1] < self.points[b][1]
                end
                return self.points[a][2] < self.points[b][2]
            end)
            local lower, upper = {}, {}
            for _, site in ipairs(ordered) do
                while #lower >= 2 and predicates.orient(self.points[lower[#lower - 1]], self.points[lower[#lower]], self.points[site]) <= 0 do
                    table.remove(lower)
                end
                lower[#lower + 1] = site
            end
            for i = #ordered, 1, -1 do
                local site = ordered[i]
                while #upper >= 2 and predicates.orient(self.points[upper[#upper - 1]], self.points[upper[#upper]], self.points[site]) <= 0 do
                    table.remove(upper)
                end
                upper[#upper + 1] = site
            end
            table.remove(lower)
            table.remove(upper)
            append(lower, upper)
            local start = 1
            for i = 2, #lower do
                if lower[i] < lower[start] then
                    start = i
                end
            end
            layer = {}
            for offset = 0, #lower - 1 do
                layer[#layer + 1] = lower[(start + offset - 1) % #lower + 1]
            end
        end
        self.layers[#self.layers + 1] = layer
        local removed = {}
        for _, site in ipairs(layer) do
            self.depth[site], removed[site] = #self.layers, true
        end
        local following = {}
        for _, site in ipairs(remaining) do
            if not removed[site] then
                following[#following + 1] = site
            end
        end
        remaining = following
    end
end
function Report:shortest_from(site)
    if not self.shortest_paths[site] then
        local distances, previous = proximity.dijkstra(self.points, self.neighbors, site)
        self.shortest_paths[site] = {distances, previous}
    end
    return table.unpack(self.shortest_paths[site])
end
function Report:analyze_spanner()
    local total = 0.0
    self.pair_count = self.n * (self.n - 1) // 2
    for i = 1, self.n - 1 do
        local distances = self:shortest_from(i)
        for j = i + 1, self.n do
            local length = distances[j]
            local distance = math.sqrt(predicates.d2(self.points[i], self.points[j]))
            local stretch = length / distance
            total = total + stretch
            if not self.maximum_stretch or stretch > self.maximum_stretch then
                self.maximum_stretch, self.stretch_pair, self.stretch_length, self.stretch_distance = stretch, {i, j}, length, distance
            end
        end
    end
    self.mean_stretch = total / self.pair_count
end
function Report:analyze_alpha()
    self.alpha_results = {}
    for _, alpha in ipairs(self.params.alpha) do
        local faces, area2, incidence, selected = 0, 0, zeros(#self.edges), {}
        for number, triangle in ipairs(self.triangles) do
            if self.radius2[number] <= alpha then
                faces, area2 = faces + 1, area2 + self.area2[number]
                local a, b, c = table.unpack(triangle)
                for _, edge in ipairs({{a, b}, {b, c}, {c, a}}) do
                    local index = self.edge_index[edge[1]][edge[2]]
                    incidence[index], selected[index] = incidence[index] + 1, true
                end
            end
        end
        for index = 1, #self.edges do
            if self.gabriel[index] and self.length2[index] <= 4 * alpha then
                selected[index] = true
            end
        end
        local sets, incident = proximity.sets(self.n), {}
        local edges, boundary, dangling, isolated = 0, 0, 0, 0
        for index, edge in ipairs(self.edges) do
            if selected[index] then
                edges = edges + 1
                boundary = boundary + (incidence[index] == 1 and 1 or 0)
                dangling = dangling + (incidence[index] == 0 and 1 or 0)
                sets:union(edge[1], edge[2])
                incident[edge[1]], incident[edge[2]] = true, true
            end
        end
        for site = 1, self.n do
            isolated = isolated + (not incident[site] and 1 or 0)
        end
        self.alpha_results[#self.alpha_results + 1] = {alpha = alpha, faces = faces, edges = edges, boundary = boundary,
            dangling = dangling, isolated = isolated, components = sets.count, holes = sets.count - (self.n - edges + faces), area2 = area2}
    end
end
function Report:locate(query)
    local nearest, best = 1, predicates.d2(self.points[1], query)
    for site = 2, self.n do
        local distance = predicates.d2(self.points[site], query)
        if distance < best then
            nearest, best = site, distance
        end
    end
    local location = "outside"
    if best == 0 then
        location = "vertex " .. nearest
    else
        for _, edge in ipairs(self.edges) do
            local a, b = self.points[edge[1]], self.points[edge[2]]
            if predicates.orient(a, b, query) == 0 and predicates.dot(query, a, b) < 0 then
                location = "edge " .. words(edge)
                break
            end
        end
        if location == "outside" then
            for _, triangle in ipairs(self.triangles) do
                local a, b, c = self.points[triangle[1]], self.points[triangle[2]], self.points[triangle[3]]
                if predicates.orient(a, b, query) > 0 and predicates.orient(b, c, query) > 0 and predicates.orient(c, a, query) > 0 then
                    location = "triangle " .. words(triangle)
                    break
                end
            end
        end
    end
    return location .. " nearest " .. nearest .. " d2 " .. best
end
function Report:answer(query)
    local values = fields(query)
    local name = table.remove(values, 1)
    for i, value in ipairs(values) do
        values[i] = tonumber(value)
    end
    if name == "route" or name == "path" or name == "neighbors" or name == "edge" then
        for _, site in ipairs(values) do
            if site < 1 or site > self.n then
                return query .. " error unknown_site"
            end
        end
        if name == "edge" and values[1] == values[2] then
            return query .. " error same_site"
        end
    end
    local answer
    if name == "locate" then
        answer = self:locate(values)
    elseif name == "walk" then
        local path, outside = self.mesh:walk(values, self.triangles, self.edge_triangles)
        local stopping = outside and "outside " .. words(outside) or "triangle " .. path[#path]
        answer = "steps " .. #path - 1 .. " " .. stopping .. " path " .. words(path)
    elseif name == "natural" then
        local count, sites, sequence = 0, {}, {}
        for _, triangle in ipairs(self.triangles) do
            if predicates.incircle(self.points[triangle[1]], self.points[triangle[2]], self.points[triangle[3]], values) > 0 then
                count = count + 1
                for _, site in ipairs(triangle) do
                    sites[site] = true
                end
            end
        end
        for site = 1, self.n do
            if sites[site] then
                sequence[#sequence + 1] = site
            end
        end
        answer = "triangles " .. count .. " sites " .. (#sequence > 0 and words(sequence) or "-")
    elseif name == "route" then
        local path, length = proximity.route(self.points, self.neighbors, values[1], values[2])
        answer = "hops " .. #path - 1 .. " length " .. real(length) .. " path " .. words(path)
    elseif name == "path" then
        local first, second = table.unpack(values)
        local distances, previous = self:shortest_from(first)
        local reverse, path = {second}, {}
        while reverse[#reverse] ~= first do
            reverse[#reverse + 1] = previous[reverse[#reverse]]
        end
        for i = #reverse, 1, -1 do
            path[#path + 1] = reverse[i]
        end
        local stretch = first == second and "-" or real(distances[second] / math.sqrt(predicates.d2(self.points[first], self.points[second])))
        answer = "length " .. real(distances[second]) .. " stretch " .. stretch .. " hops " .. #path - 1 .. " sites " .. words(path)
    elseif name == "neighbors" then
        answer = "degree " .. self.degree[values[1]] .. " sites " .. words(self.neighbors[values[1]])
    else
        local i, j = table.unpack(values)
        local index = self.edge_index[i][j]
        if index then
            answer = "delaunay len2 " .. self.length2[index] .. " gabriel " .. (self.gabriel[index] and "yes" or "no") ..
                " rng " .. (self.rng[index] and "yes" or "no") .. " mst " .. (self.mst_set[index] and "yes" or "no") .. " dual " .. self.duals[index]
        else
            local crossings = {}
            local a, b = self.points[i], self.points[j]
            for _, edge in ipairs(self.edges) do
                local p, q = self.points[edge[1]], self.points[edge[2]]
                if predicates.orient(a, b, p) * predicates.orient(a, b, q) < 0 and predicates.orient(p, q, a) * predicates.orient(p, q, b) < 0 then
                    crossings[#crossings + 1] = edge[1] .. "-" .. edge[2]
                end
            end
            answer = "missing crossings " .. #crossings .. (#crossings > 0 and " " .. words(crossings) or "")
        end
    end
    return query .. " " .. answer
end
function Report:draw()
    local canvas = plot.new(table.unpack(self.params.plot))
    for _, layer in ipairs(self.params.plot_layers) do
        if layer == "sites" then
            for _, point in ipairs(self.points) do
                canvas:mark(point, "o")
            end
        elseif layer == "circle" then
            if self.empty_vertex then
                canvas:mark(self.centers[self.empty_vertex], "@")
            end
        else
            local edges = layer == "edges" and self.edges or layer == "mst" and self.mst or self.hull_edges
            local character = layer == "edges" and "." or layer == "mst" and "*" or "#"
            for _, edge in ipairs(edges) do
                canvas:line(self.points[edge[1]], self.points[edge[2]], character)
            end
        end
    end
    self.delaunay_plot = canvas:framed()
    canvas = plot.new(table.unpack(self.params.plot))
    canvas:voronoi(self.points)
    self.voronoi_plot = canvas:framed()
end
function Report:section_input()
    local lines = {"lines " .. self.line_count, "accepted " .. self.n, "rejected " .. #self.rejected}
    append(lines, self.rejected)
    return lines
end
function Report:section_summary()
    local flips, outside, maximum = 0, 0, nil
    for _, insertion in ipairs(self.insertions) do
        flips = flips + insertion.flips
        outside = outside + (insertion.kind == "outside" and 1 or 0)
        if not maximum or insertion.flips > maximum.flips then
            maximum = insertion
        end
    end
    return {"sites " .. self.n, "triangles " .. #self.triangles, "edges " .. #self.edges, "hull_vertices " .. #self.hull,
        "interior_sites " .. self.n - #self.hull, "euler " .. self.n - #self.edges + #self.triangles, "flips " .. flips,
        "outside_insertions " .. outside, maximum and "max_flips " .. maximum.site .. " " .. maximum.flips or "max_flips none",
        "acute " .. self.kind_counts.acute, "right " .. self.kind_counts.right, "obtuse " .. self.kind_counts.obtuse}
end
function Report:section_insertions()
    local lines = {"init " .. words(self.mesh.initial)}
    for _, insertion in ipairs(self.insertions) do
        local description = insertion.kind == "inside" and "inside " .. words(insertion.containing) or "outside " .. insertion.visible
        lines[#lines + 1] = "insert " .. insertion.site .. " " .. description .. " flips " .. insertion.flips ..
            " triangles " .. insertion.triangles .. " hull " .. insertion.hull
    end
    return lines
end
function Report:section_triangles()
    local lines = {}
    for number, triangle in ipairs(self.triangles) do
        local a, b, c = table.unpack(triangle)
        local adjacent = {self.edge_triangles[c][b] or "-", self.edge_triangles[a][c] or "-", self.edge_triangles[b][a] or "-"}
        lines[#lines + 1] = "tri " .. number .. " " .. words(triangle) .. " area2 " .. self.area2[number] .. " " ..
            self.kind[number] .. " adj " .. words(adjacent)
    end
    return lines
end
function Report:section_edges()
    local lines = {}
    for index, edge in ipairs(self.edges) do
        local i, j = table.unpack(edge)
        local left, right = self.edge_triangles[i][j], self.edge_triangles[j][i]
        lines[#lines + 1] = "edge " .. words(edge) .. " " .. (left and right and "inner" or "hull") ..
            " len2 " .. self.length2[index] .. " left " .. (left or "-") .. " right " .. (right or "-")
    end
    return lines
end
function Report:section_hull()
    return {"hull_vertices " .. #self.hull, "order " .. words(self.hull), "perimeter " .. real(self.hull_perimeter), "area2 " .. self.hull_area2}
end
function Report:section_convex_layers()
    local lines = {"layers " .. #self.layers}
    for number, layer in ipairs(self.layers) do
        lines[#lines + 1] = "layer " .. number .. " size " .. #layer .. " sites " .. words(layer)
    end
    return lines
end
function Report:section_quality()
    local minimum, maximum = self.minimum_triangle, self.maximum_triangle
    local lines = {"min_angle " .. real(self.min_angles[minimum]) .. " tri " .. minimum,
        "max_angle " .. real(self.max_angles[maximum]) .. " tri " .. maximum, "mean_min_angle " .. real(self.min_angle_total / #self.triangles)}
    for bin, count in ipairs(self.angle_bins) do
        lines[#lines + 1] = "bin " .. (bin - 1) * 10 .. " " .. bin * 10 .. " " .. count
    end
    return lines
end
function Report:section_vertices()
    local lines = {"inside " .. self.position_counts.inside, "on " .. self.position_counts.on, "outside " .. self.position_counts.outside}
    for number, center in ipairs(self.centers) do
        lines[#lines + 1] = "v " .. number .. " " .. predicates.fraction(center[1], center[3]) .. " " ..
            predicates.fraction(center[2], center[3]) .. " r " .. real(math.sqrt(self.radius2[number])) .. " " .. self.positions[number]
    end
    return lines
end
function Report:section_voronoi_edges()
    local lines = {"segments " .. #self.edges - #self.hull, "rays " .. #self.hull}
    for index, edge in ipairs(self.edges) do
        lines[#lines + 1] = "ve " .. words(edge) .. " " .. self.duals[index]
    end
    return lines
end
function Report:section_cells()
    local lines = {"bounded " .. self.n - #self.hull, "unbounded " .. #self.hull, "total_area " .. real(self.cell_total), "clip_total " .. real(self.clip_total)}
    lines[#lines + 1] = self.largest_cell and "largest " .. self.largest_cell .. " area " .. real(self.cells[self.largest_cell].area) or "largest none"
    for site, cell in ipairs(self.cells) do
        if cell.area then
            lines[#lines + 1] = "cell " .. site .. " bounded " .. #cell.vertices .. " area " .. real(cell.area) ..
                " clip " .. real(cell.clip) .. " vertices " .. words(cell.vertices)
        else
            lines[#lines + 1] = "cell " .. site .. " unbounded " .. #cell.vertices .. " clip " .. real(cell.clip) ..
                " from " .. words(cell.incoming) .. " vertices " .. words(cell.vertices) .. " to " .. words(cell.outgoing)
        end
    end
    return lines
end
function Report:section_nearest()
    local lines = {"mutual_pairs " .. #self.mutual_pairs, "closest_pair " .. words(self.edges[self.closest]) .. " d2 " .. self.length2[self.closest]}
    for site, other in ipairs(self.nearest) do
        lines[#lines + 1] = "nn " .. site .. " " .. other .. " d2 " .. predicates.d2(self.points[site], self.points[other]) ..
            " " .. (self.nearest[other] == site and "mutual" or "-")
    end
    return lines
end
function Report:section_components()
    local lines = {"components " .. #self.components}
    for number, group in ipairs(self.components) do
        lines[#lines + 1] = "component " .. number .. " size " .. #group .. " pair " .. words(self.component_pairs[number]) .. " sites " .. words(group)
    end
    return lines
end
function Report:section_mst()
    local longest = self.mst[#self.mst]
    local lines = {"edges " .. self.n - 1, "total_length " .. real(self.mst_length),
        "longest " .. words(longest) .. " len2 " .. predicates.d2(self.points[longest[1]], self.points[longest[2]])}
    for _, edge in ipairs(self.mst) do
        lines[#lines + 1] = "mst " .. words(edge) .. " len2 " .. predicates.d2(self.points[edge[1]], self.points[edge[2]])
    end
    return lines
end
function Report:section_proximity()
    local lines = {"delaunay " .. #self.edges, "gabriel " .. self.gabriel_count, "rng " .. self.rng_count,
        "mst " .. self.n - 1, "nn " .. self.n - #self.mutual_pairs}
    for index, edge in ipairs(self.edges) do
        if self.rng[index] and not self.mst_set[index] then
            lines[#lines + 1] = "rng_extra " .. words(edge) .. " len2 " .. self.length2[index]
        end
    end
    return lines
end
function Report:section_degrees()
    local counts, values = {}, {}
    for _, degree in ipairs(self.degree) do
        if not counts[degree] then
            counts[degree] = 0
            values[#values + 1] = degree
        end
        counts[degree] = counts[degree] + 1
    end
    table.sort(values)
    local lines = {"min " .. values[1], "max " .. values[#values]}
    for _, degree in ipairs(values) do
        lines[#lines + 1] = "degree " .. degree .. " count " .. counts[degree]
    end
    return lines
end
function Report:section_empty_circle()
    local lines = {"candidates " .. #self.empty_candidates}
    if not self.empty_vertex then
        lines[#lines + 1] = "none"
    else
        local number, center = self.empty_vertex, self.centers[self.empty_vertex]
        append(lines, {"vertex " .. number, "center " .. predicates.fraction(center[1], center[3]) .. " " .. predicates.fraction(center[2], center[3]),
            "radius " .. real(math.sqrt(self.radius2[number])), "sites " .. words(self.triangles[number])})
    end
    return lines
end
function Report:section_extent()
    local center = self.enclosing_center
    return {"diameter " .. words(self.diameter) .. " d2 " .. self.diameter2, "width " .. real(self.width) .. " edge " .. words(self.width_edge),
        "enclosing_center " .. predicates.fraction(center[1], center[3]) .. " " .. predicates.fraction(center[2], center[3]),
        "enclosing_radius " .. real(math.sqrt(self.enclosing_radius2)), "enclosing_sites " .. words(self.enclosing_sites)}
end
function Report:section_spanner()
    return {"pairs " .. self.pair_count, "max_stretch " .. real(self.maximum_stretch) .. " pair " .. words(self.stretch_pair) ..
        " length " .. real(self.stretch_length) .. " distance " .. real(self.stretch_distance), "mean_stretch " .. real(self.mean_stretch)}
end
function Report:section_alpha()
    local lines = {}
    for _, value in ipairs(self.alpha_results) do
        lines[#lines + 1] = "alpha " .. value.alpha .. " triangles " .. value.faces .. " edges " .. value.edges ..
            " boundary " .. value.boundary .. " dangling " .. value.dangling .. " isolated " .. value.isolated ..
            " components " .. value.components .. " holes " .. value.holes .. " area2 " .. value.area2
    end
    return lines
end
function Report:section_sites()
    local lines = {}
    for site, point in ipairs(self.points) do
        lines[#lines + 1] = "site " .. site .. " " .. words(point) .. " " .. (self.hull_next[site] and "hull" or "inner") ..
            " dt " .. self.degree[site] .. " gg " .. self.graph_degrees.gg[site] .. " rng " .. self.graph_degrees.rng[site] ..
            " mst " .. self.graph_degrees.mst[site] .. " nn " .. self.nearest[site] .. " comp " .. self.component_number[site] .. " depth " .. self.depth[site]
    end
    return lines
end
function Report:section_queries()
    local lines = {}
    for _, query in ipairs(self.params.queries) do
        lines[#lines + 1] = self:answer(query)
    end
    return lines
end
function Report:section_delaunay_plot()
    return self.delaunay_plot
end
function Report:section_voronoi_plot()
    return self.voronoi_plot
end
function Report:write()
    local assignments = {
        ["triangulation.txt"] = {"input", "summary", "insertions", "triangles", "edges", "hull", "convex_layers", "quality"},
        ["voronoi.txt"] = {"vertices", "voronoi_edges", "cells"},
        ["derived.txt"] = {"nearest", "components", "mst", "proximity", "degrees", "empty_circle", "extent", "spanner", "alpha", "sites", "queries"},
        ["plot.txt"] = {"delaunay_plot", "voronoi_plot"}
    }
    local owners, contents = {}, {}
    for name, sections in pairs(assignments) do
        contents[name] = {}
        for _, section in ipairs(sections) do
            owners[section] = name
        end
    end
    for _, section in ipairs(self.params.sections) do
        local lines = contents[owners[section]]
        lines[#lines + 1] = "[" .. section .. "]"
        append(lines, self["section_" .. section](self))
    end
    for name, lines in pairs(contents) do
        local file = assert(io.open("output/" .. name, "w"))
        if #lines > 0 then
            file:write(table.concat(lines, "\n"), "\n")
        end
        file:close()
    end
end
local points, line_count, rejected = read_points()
local result = report(points, line_count, rejected, read_params())
result:build()
result:analyze_triangles()
result:analyze_voronoi()
result:analyze_proximity()
result:analyze_extent()
result:analyze_layers()
result:analyze_spanner()
result:analyze_alpha()
result:draw()
result:write()
