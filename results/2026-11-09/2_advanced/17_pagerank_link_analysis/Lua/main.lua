local directory = arg[0]:match("^(.*[/\\])") or "./"
package.path = directory .. "?.lua;" .. package.path
local input = require("graph_io")
local components = require("components")
local pagerank = require("pagerank")
local hits = require("hits")
local report = require("report")
local regions = {"CORE", "IN", "OUT", "TUBE", "IN_TENDRIL", "OUT_TENDRIL", "OTHER"}
local quantities = {"in_degree", "pagerank", "cheirank", "authority", "hub", "trustrank", "harmonic"}

local function map(values, transform)
    local result = {}; for i, value in ipairs(values) do result[i] = transform(value, i) end; return result
end
local function zeros(n, value) if value == nil then value = 0 end; local values = {}; for i = 1, n do values[i] = value end; return values end
local function range(n) local values = {}; for i = 1, n do values[i] = i end; return values end
local function lists(n) local values = {}; for i = 1, n do values[i] = {} end; return values end
local function take(values, limit) local result = {}; for i = 1, math.min(#values, limit) do result[i] = values[i] end; return result end
local function select_indices(n, predicate) local values = {}; for i = 1, n do if predicate(i) then values[#values + 1] = i end end; return values end
local function total(values) local value = 0.0; for _, item in ipairs(values) do value = value + item end; return value end
local function append(lines, extra) for _, line in ipairs(extra) do lines[#lines + 1] = line end end
local function joined(prefix, values) return prefix .. (#values > 0 and " " .. table.concat(values, " ") or "") end
local function blocks(sections)
    local lines = {}; for i, section in ipairs(sections) do if i > 1 then lines[#lines + 1] = "" end; append(lines, section) end; return lines
end
local function rank_order(values)
    local order = range(#values)
    table.sort(order, function(a, b) local x, y = report.scaled(values[a]), report.scaled(values[b]); return x > y or x == y and a < b end)
    return order
end
local function positions(order) local rank = {}; for i, node in ipairs(order) do rank[node] = i end; return rank end
local function top_list(values, limit)
    local order = {}; for _, node in ipairs(rank_order(values)) do if report.scaled(values[node]) > 0 then order[#order + 1] = node; if #order == limit then break end end end; return order
end
local function ranked_counts(counts, limit)
    local order = select_indices(#counts, function(i) return counts[i] > 0 end)
    table.sort(order, function(a, b) return counts[a] > counts[b] or counts[a] == counts[b] and a < b end)
    return take(order, limit)
end
local function distribution(values)
    local counts, keys = {}, {}; for _, value in ipairs(values) do if not counts[value] then keys[#keys + 1] = value; counts[value] = 0 end; counts[value] = counts[value] + 1 end
    table.sort(keys); return map(keys, function(value) return value .. " " .. counts[value] end)
end
local function kendall(first, second)
    local result = 0
    for i = 1, #first do for j = i + 1, #first do
        local x, y = first[i] - first[j], second[i] - second[j]
        if x ~= 0 and y ~= 0 then result = result + ((x > 0) == (y > 0) and 1 or -1) end
    end end
    return report.fraction(result, #first * (#first - 1) // 2)
end

local Graph = {}; Graph.__index = Graph
function Graph.new(pages, links)
    table.sort(links, function(a, b) return a[1] < b[1] or a[1] == b[1] and a[2] < b[2] end)
    local self = setmetatable({pages = pages, n = #pages, links = links, successors = lists(#pages), predecessors = lists(#pages), present = lists(#pages)}, Graph)
    for _, edge in ipairs(links) do table.insert(self.successors[edge[1]], edge[2]); table.insert(self.predecessors[edge[2]], edge[1]); self.present[edge[1]][edge[2]] = true end
    return self
end
function Graph:intra(source, target) return self.pages[source].host == self.pages[target].host end
function Graph:edges(reverse)
    local groups = reverse and self.successors or self.predecessors
    return map(groups, function(group) return map(group, function(source) return {source, 1} end) end)
end
function Graph:ids(nodes) return map(nodes, function(node) return self.pages[node].id end) end
function Graph:describe(rank, node, value)
    local page = self.pages[node]; return rank .. " " .. page.id .. " " .. value .. " " .. page.host .. " " .. page.title
end
function Graph:dangling() return select_indices(self.n, function(i) return #self.successors[i] == 0 end) end

local function undirected(graph)
    local adjacent, neighbors = lists(graph.n), lists(graph.n)
    for _, edge in ipairs(graph.links) do adjacent[edge[1]][edge[2]], adjacent[edge[2]][edge[1]] = true, true end
    local closed, possible, eligible, local_sum, edge_count = 0, 0, 0, 0.0, 0
    for i = 1, graph.n do
        neighbors[i] = select_indices(graph.n, function(j) return adjacent[i][j] end)
        local degree, triangles = #neighbors[i], 0
        edge_count = edge_count + degree
        if degree >= 2 then
            for a, first in ipairs(neighbors[i]) do for b = a + 1, degree do if adjacent[first][neighbors[i][b]] then triangles = triangles + 1 end end end
            local pairs = degree * (degree - 1) // 2
            closed, possible, eligible, local_sum = closed + triangles, possible + pairs, eligible + 1, local_sum + triangles / pairs
        end
    end
    local remaining, removed, core, level, left = map(neighbors, function(group) return #group end), zeros(graph.n, false), zeros(graph.n), 0, graph.n
    while left > 0 do
        local candidate
        for i = 1, graph.n do if not removed[i] and remaining[i] <= level then candidate = i; break end end
        if not candidate then level = level + 1
        else
            removed[candidate], core[candidate], left = true, level, left - 1
            for _, neighbor in ipairs(neighbors[candidate]) do if not removed[neighbor] then remaining[neighbor] = remaining[neighbor] - 1 end end
        end
    end
    local labels, sizes = components.weak(neighbors), zeros(graph.n)
    for _, label in ipairs(labels) do sizes[label] = sizes[label] + 1 end
    return {neighbors = neighbors, edges = edge_count // 2, closed = closed, possible = possible, eligible = eligible, average = local_sum / eligible, core = core, degeneracy = math.max(table.unpack(core)), weak_count = math.max(table.unpack(labels)), weak_largest = math.max(table.unpack(sizes))}
end

local function component_table(graph)
    local groups = components.strong(graph.successors)
    for _, group in ipairs(groups) do table.sort(group) end
    table.sort(groups, function(a, b) return a[1] < b[1] end)
    local labels, incoming, outgoing, successors, pending, depth = {}, zeros(#groups), zeros(#groups), lists(#groups), zeros(#groups), zeros(#groups)
    for label, group in ipairs(groups) do for _, node in ipairs(group) do labels[node] = label end end
    local present, edges = lists(#groups), 0
    for _, edge in ipairs(graph.links) do
        local a, b = labels[edge[1]], labels[edge[2]]
        if a ~= b then
            outgoing[a], incoming[b] = outgoing[a] + 1, incoming[b] + 1
            if not present[a][b] then present[a][b] = true; successors[a][#successors[a] + 1] = b; pending[b], edges = pending[b] + 1, edges + 1 end
        end
    end
    local ready = select_indices(#groups, function(i) return pending[i] == 0 end)
    while #ready > 0 do
        local node = table.remove(ready)
        for _, target in ipairs(successors[node]) do depth[target] = math.max(depth[target], depth[node] + 1); pending[target] = pending[target] - 1; if pending[target] == 0 then ready[#ready + 1] = target end end
    end
    local core, singletons = 1, 0
    for i, group in ipairs(groups) do if #group > #groups[core] then core = i end; if #group == 1 then singletons = singletons + 1 end end
    return {groups = groups, labels = labels, incoming = incoming, outgoing = outgoing, edges = edges, depth = math.max(table.unpack(depth)), core = core, singletons = singletons}
end

local function bowtie(graph, core)
    local forward, backward = components.reachable(graph.successors, core), components.reachable(graph.predecessors, core)
    local in_core, region = zeros(graph.n, false), zeros(graph.n, 7)
    for _, node in ipairs(core) do in_core[node] = true end
    for i = 1, graph.n do if in_core[i] then region[i] = 1 elseif backward[i] then region[i] = 2 elseif forward[i] then region[i] = 3 end end
    local from_in = components.reachable(graph.successors, select_indices(graph.n, function(i) return region[i] == 2 end))
    local to_out = components.reachable(graph.predecessors, select_indices(graph.n, function(i) return region[i] == 3 end))
    for i = 1, graph.n do if region[i] == 7 then if from_in[i] and to_out[i] then region[i] = 4 elseif from_in[i] then region[i] = 5 elseif to_out[i] then region[i] = 6 end end end
    return region
end

local function distance_stats(graph)
    local stats = {pairs = 0, total = 0, diameter = 0, histogram = zeros(graph.n), harmonic = zeros(graph.n, 0.0)}
    for source = 1, graph.n do
        local distance = components.bfs(graph.successors, {source})
        for target, steps in ipairs(distance) do if target ~= source and steps >= 0 then
            stats.pairs, stats.total = stats.pairs + 1, stats.total + steps
            stats.histogram[steps], stats.harmonic[target] = stats.histogram[steps] + 1, stats.harmonic[target] + 1 / steps
            if steps > stats.diameter then stats.diameter, stats.source, stats.target = steps, source, target end
        end end
    end
    local reached = 0
    for steps = 1, stats.diameter do reached = reached + stats.histogram[steps]; if 10 * reached >= 9 * stats.pairs then stats.effective = steps; break end end
    return stats
end

local function salsa(count, links)
    local degree, targets, neighbors = zeros(count), lists(count), lists(count)
    for _, edge in ipairs(links) do degree[edge[2]] = degree[edge[2]] + 1; table.insert(targets[edge[1]], edge[2]) end
    for _, group in ipairs(targets) do for i = 1, #group - 1 do table.insert(neighbors[group[i]], group[i + 1]); table.insert(neighbors[group[i + 1]], group[i]) end end
    local labels, sizes, mass, side = components.weak(neighbors), zeros(count), zeros(count), 0
    for node, value in ipairs(degree) do if value > 0 then local label = labels[node]; side, sizes[label], mass[label] = side + 1, sizes[label] + 1, mass[label] + value end end
    return map(degree, function(value, node) return value == 0 and 0.0 or (sizes[labels[node]] * value) / (side * mass[labels[node]]) end)
end

local Analysis = {}; Analysis.__index = Analysis
function Analysis.new()
    local self = setmetatable({}, Analysis)
    self.pages, self.records, self.queries, self.p = input.read()
    local n, indices, accepted, seen = #self.pages, {}, {}, {}
    for i, page in ipairs(self.pages) do indices[page.id] = i end
    self.index, self.ignored = indices, {}
    for _, record in ipairs(self.records) do
        local a, b, reason = indices[record.source], indices[record.target], nil
        if not a or not b then reason = "unknown"
        elseif a == b then reason = "self"
        elseif seen[a] and seen[a][b] then reason = "duplicate"
        else seen[a] = seen[a] or {}; seen[a][b] = true; accepted[#accepted + 1] = {a, b} end
        if reason then self.ignored[#self.ignored + 1] = {record, reason} end
    end
    self.graph = Graph.new(self.pages, accepted)
    self.undirected, self.table = undirected(self.graph), component_table(self.graph)
    self.region = bowtie(self.graph, self.table.groups[self.table.core])
    self.distance = distance_stats(self.graph)
    local p, everyone = self.p, range(n)
    self.trusted = map(p.TRUSTED, function(id) return indices[id] end); table.sort(self.trusted)
    self.pr = pagerank.run(self.graph:edges(), everyone, p.DAMPING, p.PAGERANK_ITERATIONS, p.TOLERANCE)
    self.chei = pagerank.run(self.graph:edges(true), everyone, p.DAMPING, p.PAGERANK_ITERATIONS, p.TOLERANCE)
    self.trust = pagerank.run(self.graph:edges(), self.trusted, p.DAMPING, p.PAGERANK_ITERATIONS, p.TOLERANCE)
    self.order, self.rank = rank_order(self.pr.values), positions(rank_order(self.pr.values))
    self.chei_rank = positions(rank_order(self.chei.values))
    self.ratio = map(self.pr.values, function(value, i) return self.trust.values[i] / value end)
    self.trust_distance = components.bfs(self.graph.successors, self.trusted)
    local inter = {}; for _, edge in ipairs(self.graph.links) do if not self.graph:intra(edge[1], edge[2]) then inter[#inter + 1] = edge end end
    self.authority, self.hub = hits.run(n, everyone, inter, p.HITS_ITERATIONS)
    self.sweeps = {}
    for _, damping in ipairs(p.DAMPING_SWEEP) do
        local trial = pagerank.run(self.graph:edges(), everyone, damping, p.PAGERANK_ITERATIONS, p.TOLERANCE)
        local order = rank_order(trial.values)
        local rank, overlap, footrule, shift = positions(order), 0, 0, 1
        for i = 1, n do
            if rank[i] <= p.TOP_K and self.rank[i] <= p.TOP_K then overlap = overlap + 1 end
            footrule = footrule + math.abs(rank[i] - self.rank[i])
            if math.abs(rank[i] - self.rank[i]) > math.abs(rank[shift] - self.rank[shift]) then shift = i end
        end
        self.sweeps[#self.sweeps + 1] = {damping = damping, run = trial, overlap = overlap, footrule = footrule, shift = shift, shift_rank = rank[shift], top = take(order, p.TOP_K), correlation = kendall(map(self.pr.values, function(value) return report.scaled(value) end), map(trial.values, function(value) return report.scaled(value) end))}
    end
    self.suspects, self.suspect_hosts = {}, {}
    for _, node in ipairs(take(self.order, p.SPAM_TOP)) do if report.scaled(self.ratio[node], 4) / 10000 < p.SPAM_THRESHOLD then self.suspects[#self.suspects + 1] = node; self.suspect_hosts[self.pages[node].host] = true end end
    self.removed = 0
    if #self.suspects > 0 then
        local kept = {}; for _, edge in ipairs(self.graph.links) do if self.graph:intra(edge[1], edge[2]) and self.suspect_hosts[self.pages[edge[1]].host] then self.removed = self.removed + 1 else kept[#kept + 1] = edge end end
        local graph = Graph.new(self.pages, kept)
        self.demoted = pagerank.run(graph:edges(), everyone, p.DAMPING, p.PAGERANK_ITERATIONS, p.TOLERANCE)
        self.demoted_rank = positions(rank_order(self.demoted.values))
    end
    self.results = map(self.queries, function(query) return self:query(query) end)
    self:hosts()
    return self
end

function Analysis:query(query)
    local graph, p, result = self.graph, self.p, {query = query, matches = {}}
    for _, node in ipairs(self.order) do
        local present = {}; for _, word in ipairs(self.pages[node].words) do present[word] = true end
        local matches = true
        for _, word in ipairs(query.words) do if word:sub(1, 1) == "-" then if present[word:sub(2)] then matches = false end elseif not present[word] then matches = false end end
        if matches then result.matches[#result.matches + 1] = node end
    end
    local root, base = take(result.matches, p.ROOT_LIMIT), zeros(graph.n, false)
    for _, node in ipairs(root) do
        base[node] = true
        for _, neighbor in ipairs(take(graph.successors[node], p.NEIGHBOR_LIMIT)) do base[neighbor] = true end
        for _, neighbor in ipairs(take(graph.predecessors[node], p.NEIGHBOR_LIMIT)) do base[neighbor] = true end
    end
    result.root_size, result.base, result.links, result.dropped = #root, select_indices(graph.n, function(i) return base[i] end), {}, 0
    for _, edge in ipairs(graph.links) do if base[edge[1]] and base[edge[2]] then if graph:intra(edge[1], edge[2]) then result.dropped = result.dropped + 1 else result.links[#result.links + 1] = edge end end end
    local seeds = map(query.seeds, function(id) return self.index[id] end); table.sort(seeds)
    result.personalized = pagerank.run(graph:edges(), seeds, p.DAMPING, p.PAGERANK_ITERATIONS, p.TOLERANCE)
    local reached = components.reachable(graph.successors, seeds)
    result.reach = #select_indices(graph.n, function(i) return reached[i] end)
    result.seed_mass = total(map(seeds, function(i) return result.personalized.values[i] end))
    result.personal_top = top_list(result.personalized.values, p.TOP_K)
    result.global_overlap = 0; for _, i in ipairs(result.personal_top) do if self.rank[i] <= p.TOP_K then result.global_overlap = result.global_overlap + 1 end end
    if #result.links > 0 then
        result.authority, result.hub = hits.run(graph.n, result.base, result.links, p.HITS_ITERATIONS)
        result.salsa_authority = salsa(graph.n, result.links)
        result.salsa_hub = salsa(graph.n, map(result.links, function(edge) return {edge[2], edge[1]} end))
        result.authority_top, result.hub_top = top_list(result.authority, p.TOP_K), top_list(result.hub, p.TOP_K)
        result.sa_top, result.sh_top = top_list(result.salsa_authority, p.TOP_K), top_list(result.salsa_hub, p.TOP_K)
        local sa, sh, hosts = {}, {}, {}
        for _, node in ipairs(result.sa_top) do sa[node] = true end; for _, node in ipairs(result.sh_top) do sh[node] = true end
        result.authority_overlap, result.hub_overlap, result.authority_hosts = 0, 0, 0
        for _, node in ipairs(result.authority_top) do
            if sa[node] then result.authority_overlap = result.authority_overlap + 1 end
            if not hosts[self.pages[node].host] then hosts[self.pages[node].host] = true; result.authority_hosts = result.authority_hosts + 1 end
        end
        for _, node in ipairs(result.hub_top) do if sh[node] then result.hub_overlap = result.hub_overlap + 1 end end
        result.cited, result.citing = result.authority_top[1], result.hub_top[1]
        result.cocitation, result.coupling = zeros(graph.n), zeros(graph.n)
        for _, source in ipairs(graph.predecessors[result.cited]) do for _, target in ipairs(graph.successors[source]) do if target ~= result.cited then result.cocitation[target] = result.cocitation[target] + 1 end end end
        for _, target in ipairs(graph.successors[result.citing]) do for _, source in ipairs(graph.predecessors[target]) do if source ~= result.citing then result.coupling[source] = result.coupling[source] + 1 end end end
        result.related, result.similar = ranked_counts(result.cocitation, p.TOP_K), ranked_counts(result.coupling, p.TOP_K)
    end
    return result
end

function Analysis:hosts()
    local graph, p, names, seen = self.graph, self.p, {}, {}
    for _, page in ipairs(self.pages) do if not seen[page.host] then names[#names + 1], seen[page.host] = page.host, true end end
    table.sort(names)
    local index = {}; for i, name in ipairs(names) do index[name] = i end
    local host = {names = names, members = lists(#names), weight = {}, internal = zeros(#names), outgoing = zeros(#names), incoming = zeros(#names), edges = {}}
    for i = 1, #names do host.weight[i] = zeros(#names) end
    for node, page in ipairs(self.pages) do table.insert(host.members[index[page.host]], node) end
    for _, edge in ipairs(graph.links) do
        local a, b = index[self.pages[edge[1]].host], index[self.pages[edge[2]].host]
        if a == b then host.internal[a] = host.internal[a] + 1 else host.weight[a][b], host.outgoing[a], host.incoming[b] = host.weight[a][b] + 1, host.outgoing[a] + 1, host.incoming[b] + 1 end
    end
    local adjacency, in_edges = lists(#names), lists(#names)
    host.reciprocal = 0
    for a = 1, #names do for b = 1, #names do if host.weight[a][b] > 0 then
        host.edges[#host.edges + 1] = {a, b}; table.insert(adjacency[a], b); table.insert(in_edges[b], {a, host.weight[a][b]})
        if host.weight[b][a] > 0 then host.reciprocal = host.reciprocal + 1 end
    end end end
    local groups = components.strong(adjacency)
    host.component_count, host.largest = #groups, math.max(table.unpack(map(groups, function(group) return #group end)))
    host.run = pagerank.run(in_edges, range(#names), p.DAMPING, p.PAGERANK_ITERATIONS, p.TOLERANCE)
    host.rank = positions(rank_order(host.run.values))
    local heavy = map(host.edges, function(edge) return edge end)
    table.sort(heavy, function(a, b) local x, y = host.weight[a[1]][a[2]], host.weight[b[1]][b[2]]; return x > y or x == y and (a[1] < b[1] or a[1] == b[1] and a[2] < b[2]) end)
    host.heavy, self.host_graph = take(heavy, p.TOP_K), host
end

function Analysis:rank_lines(nodes, values)
    return map(nodes, function(node, rank) return self.graph:describe(rank, node, report.fixed(values[node])) end)
end
function Analysis:representative(nodes)
    local best = nodes[1]; for _, node in ipairs(nodes) do if self.rank[node] < self.rank[best] then best = node end end; return best
end
function Analysis:graph_stats()
    local graph, u, t, d = self.graph, self.undirected, self.table, self.distance
    local reasons = {unknown = 0, self = 0, duplicate = 0}
    for _, ignored in ipairs(self.ignored) do reasons[ignored[2]] = reasons[ignored[2]] + 1 end
    local intra, reciprocal = 0, 0
    for _, edge in ipairs(graph.links) do if graph:intra(edge[1], edge[2]) then intra = intra + 1 end; if graph.present[edge[2]][edge[1]] then reciprocal = reciprocal + 1 end end
    local indegree, outdegree = map(graph.predecessors, function(group) return #group end), map(graph.successors, function(group) return #group end)
    local max_in, max_out = math.max(table.unpack(indegree)), math.max(table.unpack(outdegree))
    local lines = {"pages " .. graph.n, "hosts " .. #self.host_graph.names, "link_rows " .. #self.records, "links " .. #graph.links, "ignored_unknown " .. reasons.unknown, "ignored_self " .. reasons.self, "ignored_duplicate " .. reasons.duplicate}
    for _, ignored in ipairs(self.ignored) do local record = ignored[1]; lines[#lines + 1] = "ignored line " .. record.line .. " " .. record.source .. "," .. record.target .. " " .. ignored[2] end
    append(lines, {"intra_host_links " .. intra, "inter_host_links " .. #graph.links - intra, "mean_degree " .. report.fixed(#graph.links / graph.n, 4), "reciprocity " .. report.fraction(reciprocal, #graph.links)})
    local dangling, no_in = graph:dangling(), select_indices(graph.n, function(i) return indegree[i] == 0 end)
    append(lines, {joined("dangling " .. #dangling, graph:ids(dangling)), joined("no_in_links " .. #no_in, graph:ids(no_in)), joined("max_in_degree " .. max_in .. " pages", graph:ids(select_indices(graph.n, function(i) return indegree[i] == max_in end))), joined("max_out_degree " .. max_out .. " pages", graph:ids(select_indices(graph.n, function(i) return outdegree[i] == max_out end)))})
    append(lines, {"", "in_degree_distribution"}); append(lines, distribution(indegree)); append(lines, {"", "out_degree_distribution"}); append(lines, distribution(outdegree))
    append(lines, {"", "undirected_links " .. u.edges, "transitivity " .. report.fraction(u.closed, u.possible), "average_clustering " .. report.fixed(u.average, 4) .. " pages " .. u.eligible, "degeneracy " .. u.degeneracy .. " pages " .. #select_indices(graph.n, function(i) return u.core[i] == u.degeneracy end), "core_distribution"}); append(lines, distribution(u.core))
    append(lines, {"", "strong_components " .. #t.groups .. " largest " .. #t.groups[t.core] .. " singletons " .. t.singletons .. " condensation_links " .. t.edges, "weak_components " .. u.weak_count .. " largest " .. u.weak_largest, "condensation_depth " .. t.depth})
    for i, group in ipairs(t.groups) do if #group >= 2 then lines[#lines + 1] = "scc " .. i .. " size " .. #group .. " min " .. self.pages[group[1]].id .. " incoming " .. t.incoming[i] .. " outgoing " .. t.outgoing[i] .. " pagerank " .. report.fixed(total(map(group, function(node) return self.pr.values[node] end))) .. (t.outgoing[i] == 0 and " sink" or "") end end
    append(lines, {"", "bowtie core_scc " .. t.core})
    for i, name in ipairs(regions) do
        local members = select_indices(graph.n, function(node) return self.region[node] == i end)
        local text = name .. " " .. #members .. " pagerank " .. report.fixed(total(map(members, function(node) return self.pr.values[node] end)))
        if #members > 0 then text = text .. " top " .. self.pages[self:representative(members)].id end
        if #members > 0 and #members <= 10 then text = joined(text .. " pages", graph:ids(members)) end
        lines[#lines + 1] = text
    end
    local counts = {}; for i = 1, 7 do counts[i] = zeros(7) end
    for _, edge in ipairs(graph.links) do local a, b = self.region[edge[1]], self.region[edge[2]]; counts[a][b] = counts[a][b] + 1 end
    lines[#lines + 1] = "region_links"; for a = 1, 7 do for b = 1, 7 do if counts[a][b] > 0 then lines[#lines + 1] = regions[a] .. " " .. regions[b] .. " " .. counts[a][b] end end end
    append(lines, {"", "distances", "reachable_pairs " .. d.pairs, "average " .. report.fraction(d.total, d.pairs), "diameter " .. d.diameter .. " from " .. self.pages[d.source].id .. " to " .. self.pages[d.target].id, "effective_diameter " .. d.effective})
    for steps = 1, d.diameter do lines[#lines + 1] = steps .. " " .. d.histogram[steps] end
    return lines
end

function Analysis:pagerank_csv()
    local lines = {"id,in_degree,out_degree,scc,region,kcore,harmonic,pagerank,pagerank_rank,cheirank,cheirank_rank,authority,hub,trustrank,trust_ratio,trust_distance"}
    for node, page in ipairs(self.pages) do lines[#lines + 1] = table.concat({page.id, #self.graph.predecessors[node], #self.graph.successors[node], self.table.labels[node], regions[self.region[node]], self.undirected.core[node], report.fixed(self.distance.harmonic[node]), report.fixed(self.pr.values[node]), self.rank[node], report.fixed(self.chei.values[node]), self.chei_rank[node], report.fixed(self.authority[node]), report.fixed(self.hub[node]), report.fixed(self.trust.values[node]), report.fixed(self.ratio[node], 4), self.trust_distance[node]}, ",") end
    return lines
end

function Analysis:rankings()
    local graph, p, sections = self.graph, self.p, {}
    local values = {self.pr.values, self.chei.values, self.authority, self.hub, self.trust.values, self.distance.harmonic}
    local names = {"pagerank", "cheirank", "authority", "hub", "trustrank", "harmonic"}
    for i, name in ipairs(names) do
        local nodes = top_list(values[i], p.TOP_K)
        local lines = {name .. " top " .. p.TOP_K}; append(lines, self:rank_lines(nodes, values[i]))
        if i == 1 then
            lines[#lines + 1] = "dangling_mass " .. report.fixed(total(map(graph:dangling(), function(node) return self.pr.values[node] end)))
            for _, node in ipairs(nodes) do
                local contributors = map(graph.predecessors[node], function(source) return source end)
                local function contribution(source) return (p.DAMPING * self.pr.values[source]) / #graph.successors[source] end
                table.sort(contributors, function(a, b) local x, y = report.scaled(contribution(a)), report.scaled(contribution(b)); return x > y or x == y and a < b end)
                local parts = {"contributors", self.pages[node].id}; for _, source in ipairs(take(contributors, 3)) do append(parts, {self.pages[source].id, report.fixed(contribution(source))}) end
                lines[#lines + 1] = table.concat(parts, " ")
            end
        end
        sections[#sections + 1] = lines
    end
    local series = {map(graph.predecessors, function(group) return #group end)}
    for _, scores in ipairs({self.pr.values, self.chei.values, self.authority, self.hub, self.trust.values, self.distance.harmonic}) do series[#series + 1] = map(scores, function(value) return report.scaled(value) end) end
    local correlations = {"correlation"}; for a = 1, 7 do for b = a + 1, 7 do correlations[#correlations + 1] = quantities[a] .. " " .. quantities[b] .. " " .. kendall(series[a], series[b]) end end
    sections[#sections + 1] = correlations
    local sweep_lines = {"damping_sweep"}
    for _, sweep in ipairs(self.sweeps) do append(sweep_lines, {"damping " .. report.fixed(sweep.damping, 4) .. " overlap " .. sweep.overlap .. " footrule " .. sweep.footrule .. " kendall " .. sweep.correlation .. " largest_shift " .. self.pages[sweep.shift].id .. " " .. self.rank[sweep.shift] .. " " .. sweep.shift_rank, joined("top", graph:ids(sweep.top))}) end
    sections[#sections + 1] = sweep_lines
    local spam = {"spam top " .. p.SPAM_TOP .. " threshold " .. report.fixed(p.SPAM_THRESHOLD, 4)}
    for _, node in ipairs(self.suspects) do spam[#spam + 1] = "suspect " .. self.pages[node].id .. " rank " .. self.rank[node] .. " pagerank " .. report.fixed(self.pr.values[node]) .. " trustrank " .. report.fixed(self.trust.values[node]) .. " trust_ratio " .. report.fixed(self.ratio[node], 4) .. " trust_distance " .. self.trust_distance[node] .. " kcore " .. self.undirected.core[node] .. " " .. self.pages[node].host end
    append(spam, {"count " .. #self.suspects, "trust_by_distance"})
    local seen, distances = {}, {}; for _, distance in ipairs(self.trust_distance) do if distance >= 0 and not seen[distance] then seen[distance] = true; distances[#distances + 1] = distance end end; table.sort(distances)
    for _, distance in ipairs(self.trust_distance) do if distance == -1 then distances[#distances + 1] = -1; break end end
    for _, distance in ipairs(distances) do
        local members = select_indices(graph.n, function(node) return self.trust_distance[node] == distance end)
        spam[#spam + 1] = (distance == -1 and "unreachable" or distance) .. " pages " .. #members .. " trustrank " .. report.fixed(total(map(members, function(node) return self.trust.values[node] end))) .. " pagerank " .. report.fixed(total(map(members, function(node) return self.pr.values[node] end)))
    end
    sections[#sections + 1] = spam
    local demotion = {"demotion none"}
    if self.demoted then
        local hosts = {}; for host in pairs(self.suspect_hosts) do hosts[#hosts + 1] = host end; table.sort(hosts)
        demotion = {"demotion hosts " .. table.concat(hosts, " ") .. " removed_links " .. self.removed}
        for rank, node in ipairs(top_list(self.demoted.values, p.TOP_K)) do demotion[#demotion + 1] = graph:describe(rank, node, report.fixed(self.demoted.values[node]) .. " was " .. self.rank[node]) end
        for _, node in ipairs(self.suspects) do demotion[#demotion + 1] = "suspect " .. self.pages[node].id .. " before " .. self.rank[node] .. " after " .. self.demoted_rank[node] end
    end
    sections[#sections + 1] = demotion
    local host = self.host_graph
    local host_lines = {"host_graph hosts " .. #host.names .. " links " .. #host.edges .. " reciprocal " .. host.reciprocal .. " strong_components " .. host.component_count .. " largest " .. host.largest, "host_links top " .. p.TOP_K}
    for _, edge in ipairs(host.heavy) do host_lines[#host_lines + 1] = host.names[edge[1]] .. " " .. host.names[edge[2]] .. " " .. host.weight[edge[1]][edge[2]] end
    sections[#sections + 1] = host_lines
    return blocks(sections)
end

function Analysis:convergence()
    local p, damping = self.p, report.fixed(self.p.DAMPING, 4)
    local lines = {"iterations " .. p.PAGERANK_ITERATIONS .. " tolerance " .. report.fixed(p.TOLERANCE, 10)}
    local function add(heading, result)
        append(lines, {"", heading})
        for step = 10, #result.changes, 10 do lines[#lines + 1] = "iteration " .. step .. " l1 " .. report.fixed(result.changes[step], 10) end
        lines[#lines + 1] = "converged_at " .. (result.converged or "none")
    end
    add("pagerank damping " .. damping, self.pr); add("cheirank damping " .. damping, self.chei); add("trustrank damping " .. damping .. " seeds " .. #p.TRUSTED, self.trust)
    for _, sweep in ipairs(self.sweeps) do add("sweep damping " .. report.fixed(sweep.damping, 4), sweep.run) end
    if self.demoted then add("demoted damping " .. damping, self.demoted) end
    for _, result in ipairs(self.results) do add("personalized query " .. result.query.number .. " damping " .. damping, result.personalized) end
    add("host_pagerank damping " .. damping .. " hosts " .. #self.host_graph.names, self.host_graph.run)
    return lines
end

function Analysis:query_lines(result)
    local query, graph, p = result.query, self.graph, self.p
    local lines = {"query " .. query.number .. " words " .. table.concat(query.words, " ") .. " seeds " .. table.concat(query.seeds, " "), "matched " .. #result.matches .. " root " .. result.root_size .. " base " .. #result.base .. " links " .. #result.links .. " dropped_intra_host " .. result.dropped, "results"}
    append(lines, self:rank_lines(take(result.matches, p.TOP_K), self.pr.values))
    lines[#lines + 1] = "personalized reach " .. result.reach .. " seed_mass " .. report.fixed(result.seed_mass)
    append(lines, self:rank_lines(result.personal_top, result.personalized.values)); lines[#lines + 1] = "overlap_with_global " .. result.global_overlap
    if #result.links == 0 then lines[#lines + 1] = "hits none"; return lines end
    for _, item in ipairs({{"hits authorities", result.authority_top, result.authority}, {"hits hubs", result.hub_top, result.hub}, {"salsa authorities", result.sa_top, result.salsa_authority}, {"salsa hubs", result.sh_top, result.salsa_hub}}) do lines[#lines + 1] = item[1]; append(lines, self:rank_lines(item[2], item[3])) end
    append(lines, {"hits_salsa_overlap authorities " .. result.authority_overlap .. " hubs " .. result.hub_overlap .. " authority_hosts " .. result.authority_hosts, "related_to " .. self.pages[result.cited].id .. " citing " .. #graph.predecessors[result.cited]})
    for rank, node in ipairs(result.related) do lines[#lines + 1] = graph:describe(rank, node, result.cocitation[node]) end
    lines[#lines + 1] = "coupled_to " .. self.pages[result.citing].id .. " cited " .. #graph.successors[result.citing]
    for rank, node in ipairs(result.similar) do lines[#lines + 1] = graph:describe(rank, node, result.coupling[node]) end
    return lines
end

function Analysis:hosts_csv()
    local host, lines = self.host_graph, {"host,pages,core_pages,internal_links,internal_density,outgoing_links,incoming_links,dangling_pages,page_score_sum,top_page,score,rank"}
    for i, name in ipairs(host.names) do
        local members, core, dangling = host.members[i], 0, 0
        for _, node in ipairs(members) do if self.region[node] == 1 then core = core + 1 end; if #self.graph.successors[node] == 0 then dangling = dangling + 1 end end
        local density = #members >= 2 and host.internal[i] / (#members * (#members - 1)) or 0.0
        lines[#lines + 1] = table.concat({name, #members, core, host.internal[i], report.fixed(density, 4), host.outgoing[i], host.incoming[i], dangling, report.fixed(total(map(members, function(node) return self.pr.values[node] end))), self.pages[self:representative(members)].id, report.fixed(host.run.values[i]), host.rank[i]}, ",")
    end
    return lines
end

local analysis = Analysis.new()
os.execute("mkdir -p output")
report.write("graph_stats.txt", analysis:graph_stats())
report.write("pagerank.csv", analysis:pagerank_csv())
report.write("rankings.txt", analysis:rankings())
report.write("convergence.txt", analysis:convergence())
report.write("queries.txt", blocks(map(analysis.results, function(result) return analysis:query_lines(result) end)))
report.write("hosts.csv", analysis:hosts_csv())
