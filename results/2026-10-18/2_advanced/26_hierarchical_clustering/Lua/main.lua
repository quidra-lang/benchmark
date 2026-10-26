local dataset = require("dataset")
local distances = require("distances")
local agglomerative = require("agglomerative")
local dendrogram = require("dendrogram")
local validation = require("validation")

local function map(values, transform)
    local result = {}
    for i, value in ipairs(values) do result[i] = transform(value, i) end
    return result
end

local function range(count)
    local values = {}
    for i = 1, count do values[i] = i end
    return values
end

local function append(first, second)
    for _, value in ipairs(second) do first[#first + 1] = value end
    return first
end

local function real(value)
    if value == nil then return "-" end
    local text = string.format("%.4f", value)
    return text == "-0.0000" and "0.0000" or text
end

local function reals(values) return table.concat(map(values, real), " ") end
local function integers(values) return table.concat(map(values, tostring), " ") end
local function rounded(value) return tonumber(real(value)) end
local function ari_value(ari) return ari[1] / ari[2] end
local function ari_text(ari) return ari[1] .. "/" .. ari[2] .. " " .. real(ari_value(ari)) end
local function ari_greater(a, b) return a[1] * b[2] > b[1] * a[2] end
local function maximum(values) return math.max(table.unpack(values)) end
local function minimum(values) return math.min(table.unpack(values)) end

local function pair_values(matrix)
    local values = {}
    for i = 1, #matrix do for j = i + 1, #matrix do values[#values + 1] = matrix[i][j] end end
    return values
end

local function histogram_bin(value, largest) return math.min(9, math.floor(10 * value / largest)) end

local function centroid(vectors)
    local center = {}
    for f = 1, #vectors[1] do center[f] = distances.sum(map(vectors, function(row) return row[f] end)) / #vectors end
    return center
end

local function cluster_members(partition, groups)
    local members = map(range(groups), function() return {} end)
    for i, number in ipairs(partition) do members[number][#members[number] + 1] = i end
    return members
end

local function majority_class(row)
    local best = 1
    for t = 2, #row do if row[t] > row[best] then best = t end end
    return best
end

local function join_parts(parts)
    local lines = {}
    for _, part in ipairs(parts) do
        if #lines > 0 then lines[#lines + 1] = "" end
        append(lines, part)
    end
    return lines
end

local Tree = {}
Tree.__index = Tree

function Tree.new(merges, count)
    local self = setmetatable({merges = merges, count = count}, Tree)
    self.heights = map(merges, function(merge) return merge.height end)
    self.children = dendrogram.children(merges, count)
    self.order = dendrogram.order(self.children, count)
    self.members = map(range(count), function(i) return {i} end)
    self.depths = map(range(count), function() return 0 end)
    self.subtree_heights = {}
    for step, merge in ipairs(merges) do
        self.members[count + step] = append(map(self.members[merge.a + 1], function(i) return i end), self.members[merge.b + 1])
        self.depths[count + step] = 1 + math.max(self.depths[merge.a + 1], self.depths[merge.b + 1])
        self.subtree_heights[step] = math.max(merge.height, self:subtree_height(merge.a), self:subtree_height(merge.b))
    end
    return self
end

function Tree:height_of(node) return node < self.count and 0.0 or self.heights[node - self.count + 1] end
function Tree:subtree_height(node) return node < self.count and 0.0 or self.subtree_heights[node - self.count + 1] end

function Tree:partition(selected)
    local owner, numbers, groups = range(self.count), {}, 0
    for step, chosen in ipairs(selected) do
        if chosen then for _, i in ipairs(self.members[self.count + step]) do owner[i] = self.count + step end end
    end
    for _, i in ipairs(self.order) do
        if not numbers[owner[i]] then groups = groups + 1; numbers[owner[i]] = groups end
    end
    return map(owner, function(node) return numbers[node] end)
end

function Tree:cut_height(height) return self:partition(map(self.subtree_heights, function(value) return value <= height end)) end
function Tree:cut_into(k) return self:partition(map(self.merges, function(_, step) return step <= self.count - k end)) end

function Tree:cophenetic()
    local matrix = map(range(self.count), function() return map(range(self.count), function() return 0.0 end) end)
    for _, merge in ipairs(self.merges) do
        for _, i in ipairs(self.members[merge.a + 1]) do
            for _, j in ipairs(self.members[merge.b + 1]) do matrix[i][j], matrix[j][i] = merge.height, merge.height end
        end
    end
    return matrix
end

function Tree:joining_heights()
    local values = {}
    for _, merge in ipairs(self.merges) do
        for _, child in ipairs({merge.a, merge.b}) do if child < self.count then values[child + 1] = merge.height end end
    end
    return values
end

function Tree:height_sequence(step, depth)
    if depth == 0 then return {} end
    local merge = self.merges[step]
    local sequence = {merge.height}
    for _, child in ipairs({merge.a, merge.b}) do
        if child >= self.count then append(sequence, self:height_sequence(child - self.count + 1, depth - 1)) end
    end
    return sequence
end

function Tree:newick(node, idents)
    if node < self.count then return idents[node + 1] end
    local height, branches = self:height_of(node), {}
    for _, child in ipairs(self.children[node - self.count + 1]) do branches[#branches + 1] = self:newick(child, idents) .. ":" .. real(height - self:height_of(child)) end
    return "(" .. table.concat(branches, ",") .. ")"
end

local function evaluation_text(cut)
    return "sizes " .. integers(cut.sizes) .. " silhouette " .. real(cut.silhouette) .. " dunn " .. real(cut.dunn) .. " wss " .. real(cut.wss) .. " ch " .. real(cut.ch) .. " ari " .. ari_text(cut.ari)
end

local Study = {}
Study.__index = Study

function Study.new(names, observations, settings)
    local self = setmetatable({names = names, settings = settings, count = #observations}, Study)
    self.idents = map(observations, function(row) return row.ident end)
    self.labels = map(observations, function(row) return row.label end)
    local present = {}
    self.classes = {}
    for _, label in ipairs(self.labels) do if not present[label] then self.classes[#self.classes + 1], present[label] = label, true end end
    table.sort(self.classes)
    self.targets = map(self.labels, function(label)
        for t, class in ipairs(self.classes) do if label == class then return t end end
    end)
    self.raw = map(observations, function(row) return row.values end)
    self.means, self.deviations = distances.statistics(self.raw)
    self.vectors = settings.standardize == "yes" and distances.standardize(self.raw, self.means, self.deviations) or self.raw
    self.distances = distances.matrix(self.vectors, settings.distance)
    self.distance_pairs = pair_values(self.distances)
    self.distance_max = maximum(self.distance_pairs)
    self.neighbors = map(range(self.count), function(i) return self:nearest_neighbor(i) end)
    self.results = map(settings.linkages, function(method) return self:analyse(method) end)
    self.chosen, self.position = 1, 1
    for r, result in ipairs(self.results) do
        for p, cut in ipairs(result.count_cuts) do
            if ari_greater(cut.ari, self.results[self.chosen].count_cuts[self.position].ari) then self.chosen, self.position = r, p end
        end
    end
    self.kappa = settings.cut_counts[self.position]
    self.selected_cut = self.results[self.chosen].count_cuts[self.position]
    self.selected = self.selected_cut.partition
    self.members = cluster_members(self.selected, self.kappa)
    self.silhouettes = validation.silhouettes(self.selected, self.kappa, self.distances)
    self.table = self:class_table(self.selected)
    self.majority = map(self.table, majority_class)
    return self
end

function Study:nearest_neighbor(i)
    local best
    for j = 1, self.count do if j ~= i and (not best or self.distances[i][j] < self.distances[i][best]) then best = j end end
    return best
end

function Study:class_table(partition) return validation.contingency(partition, self.targets, maximum(partition), #self.classes) end
function Study:label_ari(partition) return validation.ari(self:class_table(partition)) end
function Study:matches(partition) return distances.sum(map(self:class_table(partition), maximum)) end
function Study:partition_ari(first, second) return validation.ari(validation.contingency(first, second, maximum(first), maximum(second))) end

function Study:mean_silhouette(partition, delta)
    if maximum(partition) < 2 then return nil end
    return distances.sum(validation.silhouettes(partition, maximum(partition), delta)) / #partition
end

function Study:centroids(partition)
    return map(cluster_members(partition, maximum(partition)), function(group)
        return centroid(map(group, function(i) return self.vectors[i] end))
    end)
end

function Study:within(partition)
    local centers = self:centroids(partition)
    return distances.sum(map(partition, function(g, i) return distances.squared(self.vectors[i], centers[g]) end))
end

function Study:evaluate(partition)
    local groups, diameter, separation = maximum(partition), 0.0, nil
    local members = cluster_members(partition, groups)
    local sizes = map(members, function(group) return #group end)
    local wss, ch = self:within(partition), nil
    for i = 1, self.count do
        for j = i + 1, self.count do
            local value = self.distances[i][j]
            if partition[i] == partition[j] then diameter = math.max(diameter, value)
            elseif not separation or value < separation then separation = value end
        end
    end
    if 2 <= groups and groups < self.count then
        local overall, centers = centroid(self.vectors), self:centroids(partition)
        local bss = distances.sum(map(sizes, function(size, g) return size * distances.squared(centers[g], overall) end))
        ch = (bss / (groups - 1)) / (wss / (self.count - groups))
    end
    return {partition = partition, sizes = sizes, silhouette = self:mean_silhouette(partition, self.distances), dunn = groups >= 2 and diameter > 0 and separation / diameter or nil, wss = wss, ch = ch, ari = self:label_ari(partition)}
end

function Study:analyse(method)
    local tree = Tree.new(agglomerative.agglomerate(self.distances, method), self.count)
    local cophenetic = pair_values(tree:cophenetic())
    return {method = method, tree = tree, cophenetic = cophenetic, correlation = validation.correlation(self.distance_pairs, cophenetic), height_cuts = map(self.settings.cut_heights, function(height) return self:evaluate(tree:cut_height(height)) end), count_cuts = map(self.settings.cut_counts, function(k) return self:evaluate(tree:cut_into(k)) end), label_partition = tree:cut_into(#self.classes)}
end

function Study:linkage_table()
    local lines = {"method,step,a,b,height,size"}
    for _, result in ipairs(self.results) do
        for step, merge in ipairs(result.tree.merges) do lines[#lines + 1] = table.concat({result.method, step, merge.a, merge.b, real(merge.height), merge.size}, ",") end
    end
    return lines
end

function Study:clusters_table()
    local header = {"id", "label"}
    for _, result in ipairs(self.results) do
        for j = 1, #self.settings.cut_heights do header[#header + 1] = result.method .. "_h" .. j end
        for _, k in ipairs(self.settings.cut_counts) do header[#header + 1] = result.method .. "_k" .. k end
    end
    local lines = {table.concat(header, ",")}
    for i = 1, self.count do
        local fields = {self.idents[i], self.labels[i]}
        for _, result in ipairs(self.results) do
            for _, cuts in ipairs({result.height_cuts, result.count_cuts}) do for _, cut in ipairs(cuts) do fields[#fields + 1] = cut.partition[i] end end
        end
        lines[#lines + 1] = table.concat(fields, ",")
    end
    return lines
end

function Study:dendrogram_report()
    local blocks = {}
    for _, result in ipairs(self.results) do
        local tree, width = result.tree, self.settings.width
        local highest = maximum(tree.heights)
        local cuts = map(self.settings.cut_heights, function(height) return dendrogram.column(height, highest, width) end)
        local lines = {"dendrogram " .. result.method .. " height_max " .. real(highest) .. " width " .. width}
        append(lines, dendrogram.rows(tree, self.idents, self.labels, highest, cuts, width))
        for j, height in ipairs(self.settings.cut_heights) do lines[#lines + 1] = "cut " .. real(height) .. " column " .. (cuts[j] <= width and cuts[j] or "-") end
        blocks[#blocks + 1] = lines
    end
    return join_parts(blocks)
end

function Study:trees_report()
    return map(self.results, function(result) return result.method .. " " .. result.tree:newick(2 * self.count - 2, self.idents) .. ";" end)
end

function Study:pair_text(i, j) return real(self.distances[i][j]) .. " " .. self.idents[i] .. " " .. self.idents[j] end

function Study:data_part()
    local n, settings = self.count, self.settings
    local lines = {"data n " .. n .. " features " .. #self.names .. " classes " .. #self.classes .. " distance " .. settings.distance .. " standardize " .. settings.standardize}
    for f, name in ipairs(self.names) do lines[#lines + 1] = "feature " .. name .. " mean " .. real(self.means[f]) .. " sd " .. real(self.deviations[f]) end
    local small, large = {1, 2}, {1, 2}
    for i = 1, n do
        for j = i + 1, n do
            if self.distances[i][j] < self.distances[small[1]][small[2]] then small = {i, j} end
            if self.distances[i][j] > self.distances[large[1]][large[2]] then large = {i, j} end
        end
    end
    lines[#lines + 1] = "distances pairs " .. #self.distance_pairs .. " min " .. self:pair_text(small[1], small[2]) .. " max " .. self:pair_text(large[1], large[2]) .. " mean " .. real(distances.sum(self.distance_pairs) / #self.distance_pairs)
    local nearest, reciprocal = 0.0, 0
    for i = 1, n do
        nearest = nearest + self.distances[i][self.neighbors[i]]
        if i < self.neighbors[i] and self.neighbors[self.neighbors[i]] == i then reciprocal = reciprocal + 1 end
    end
    lines[#lines + 1] = "nearest_neighbors mean " .. real(nearest / n) .. " reciprocal_pairs " .. reciprocal
    lines[#lines + 1] = "labels " .. evaluation_text(self:evaluate(self.targets))
    return lines
end

function Study:correlation_part()
    local columns = map(self.names, function(_, f) return map(self.raw, function(row) return row[f] end) end)
    local lines = {"correlation " .. table.concat(self.names, " ")}
    for f, name in ipairs(self.names) do lines[#lines + 1] = name .. " " .. reals(map(columns, function(column) return validation.correlation(columns[f], column) end)) end
    return lines
end

function Study:histogram_part()
    local counts = map(range(10), function() return 0 end)
    for _, value in ipairs(self.distance_pairs) do local b = histogram_bin(value, self.distance_max) + 1; counts[b] = counts[b] + 1 end
    local lines, highest = {"histogram"}, maximum(counts)
    for b = 0, 9 do
        local count = counts[b + 1]
        local line = real(b * self.distance_max / 10) .. " " .. real((b + 1) * self.distance_max / 10) .. " " .. count
        local length = count * 50 // highest
        lines[#lines + 1] = line .. (length > 0 and " " .. string.rep("#", length) or "")
    end
    return lines
end

function Study:linkage_part(result)
    local tree, settings, n = result.tree, self.settings, self.count
    local path, inversions, lines = 0.0, {}, {"linkage " .. result.method}
    for r = 1, n - 1 do path = path + self.distances[tree.order[r]][tree.order[r + 1]] end
    for step = 2, n - 1 do if tree.heights[step] < tree.heights[step - 1] then inversions[#inversions + 1] = step end end
    lines[#lines + 1] = "cophenetic " .. real(result.correlation) .. " leaf_path " .. real(path)
    lines[#lines + 1] = "heights min " .. real(minimum(tree.heights)) .. " max " .. real(maximum(tree.heights)) .. " inversions " .. #inversions
    for _, step in ipairs(inversions) do lines[#lines + 1] = "inversion step " .. step .. " height " .. real(tree.heights[step]) .. " previous " .. real(tree.heights[step - 1]) end
    local ordered = map(tree.subtree_heights, function(value) return value end)
    table.sort(ordered)
    local gaps, suggested = {}, 2
    for k = 2, settings.gap_max_k do gaps[k - 1] = ordered[n - k + 1] - ordered[n - k] end
    for k = 3, settings.gap_max_k do if rounded(gaps[k - 1]) > rounded(gaps[suggested - 1]) then suggested = k end end
    lines[#lines + 1], lines[#lines + 2] = "gaps " .. reals(gaps), "suggested_k " .. suggested
    local joining, late = tree:joining_heights(), range(n)
    table.sort(late, function(a, b) return joining[a] ~= joining[b] and joining[a] > joining[b] or joining[a] == joining[b] and a < b end)
    local joiners = {}
    for r = 1, settings.list_size do local i = late[r]; joiners[r] = self.idents[i] .. ":" .. real(joining[i]) end
    lines[#lines + 1] = "late_joiners " .. table.concat(joiners, " ")
    local kinds = {0, 0, 0}
    for _, merge in ipairs(tree.merges) do
        local leaves = (merge.a < n and 1 or 0) + (merge.b < n and 1 or 0)
        kinds[3 - leaves] = kinds[3 - leaves] + 1
    end
    lines[#lines + 1] = "merges leaf_leaf " .. kinds[1] .. " leaf_cluster " .. kinds[2] .. " cluster_cluster " .. kinds[3] .. " depth " .. tree.depths[2 * n - 1]
    local matches = self:matches(result.label_partition)
    lines[#lines + 1] = "label_cut k " .. #self.classes .. " purity " .. math.tointeger(matches) .. "/" .. n .. " " .. real(matches / n)
    lines[#lines + 1] = "inconsistency depth " .. settings.inconsistency_depth_text
    for step = n - settings.inconsistency_count, n - 1 do
        local sequence = tree:height_sequence(step, settings.inconsistency_depth)
        local mean, sd, coefficient = distances.sum(sequence) / #sequence, 0.0, 0.0
        if #sequence >= 2 then
            sd = math.sqrt(distances.sum(map(sequence, function(value) return (value - mean) * (value - mean) end)) / (#sequence - 1))
            coefficient = (tree.heights[step] - mean) / sd
        end
        lines[#lines + 1] = "step " .. step .. " height " .. real(tree.heights[step]) .. " mean " .. real(mean) .. " sd " .. real(sd) .. " count " .. #sequence .. " coefficient " .. real(coefficient)
    end
    for j, height in ipairs(settings.cut_heights) do lines[#lines + 1] = "cut height " .. real(height) .. " clusters " .. #result.height_cuts[j].sizes .. " " .. evaluation_text(result.height_cuts[j]) end
    for j, k in ipairs(settings.cut_counts) do lines[#lines + 1] = "cut k " .. k .. " " .. evaluation_text(result.count_cuts[j]) end
    return lines
end

function Study:mst_part(single)
    local edges, n = agglomerative.mst(self.distances), self.count
    local weights = map(edges, function(edge) return edge.weight end)
    local total = distances.sum(weights)
    table.sort(weights)
    local match, linked, nearest = true, {}, 0
    for i = 1, n do linked[i] = {} end
    for i, edge in ipairs(edges) do
        if math.abs(weights[i] - single.tree.heights[i]) > 0.000000001 then match = false end
        linked[edge.parent][edge.child], linked[edge.child][edge.parent] = true, true
    end
    for i = 1, n do if linked[i][self.neighbors[i]] then nearest = nearest + 1 end end
    local lines = {"mst total " .. real(total) .. " heights " .. (match and "match" or "mismatch") .. " nn_edges " .. nearest .. "/" .. n}
    local numbers = range(#edges)
    table.sort(numbers, function(a, b) return edges[a].weight ~= edges[b].weight and edges[a].weight < edges[b].weight or edges[a].weight == edges[b].weight and a < b end)
    for position, k in ipairs(self.settings.cut_counts) do
        local component = range(n)
        for s = 1, n - k do
            local edge = edges[numbers[s]]
            local old, new = component[edge.child], component[edge.parent]
            for u = 1, n do if component[u] == old then component[u] = new end end
        end
        local agrees, partition = true, single.count_cuts[position].partition
        for i = 1, n do for j = i + 1, n do if (component[i] == component[j]) ~= (partition[i] == partition[j]) then agrees = false end end end
        lines[#lines + 1] = "mst partition k " .. k .. " " .. (agrees and "match" or "mismatch")
    end
    return lines
end

function Study:compare_part()
    local method, labels = self.settings.compare_linkage, #self.classes
    local lines = {"compare linkage " .. method .. " k " .. labels}
    for _, kind in ipairs(distances.types) do
        local delta = distances.matrix(self.vectors, kind)
        local tree = Tree.new(agglomerative.agglomerate(delta, method), self.count)
        local partition = tree:cut_into(labels)
        lines[#lines + 1] = "metric " .. kind .. " cophenetic " .. real(validation.correlation(pair_values(delta), pair_values(tree:cophenetic()))) .. " silhouette " .. real(self:mean_silhouette(partition, delta)) .. " ari " .. ari_text(self:label_ari(partition))
    end
    return lines
end

function Study:comparison_parts()
    local methods = table.concat(map(self.results, function(result) return result.method end), " ")
    local cophenetic, agreement = {"cophenetic_matrix", "linkage " .. methods}, {"agreement k " .. #self.classes, "linkage " .. methods}
    for _, first in ipairs(self.results) do
        cophenetic[#cophenetic + 1] = first.method .. " " .. reals(map(self.results, function(second) return validation.correlation(first.cophenetic, second.cophenetic) end))
        agreement[#agreement + 1] = first.method .. " " .. reals(map(self.results, function(second) return ari_value(self:partition_ari(first.label_partition, second.label_partition)) end))
    end
    return cophenetic, agreement
end

function Study:summary_part()
    local ranking = range(#self.results)
    table.sort(ranking, function(a, b)
        local x, y = rounded(self.results[a].correlation), rounded(self.results[b].correlation)
        return x ~= y and x > y or x == y and a < b
    end)
    local lines = {"summary", "cophenetic_ranking " .. table.concat(map(ranking, function(i) return self.results[i].method end), " ")}
    for p, k in ipairs(self.settings.cut_counts) do
        local best = self.results[1]
        for r = 2, #self.results do if ari_greater(self.results[r].count_cuts[p].ari, best.count_cuts[p].ari) then best = self.results[r] end end
        lines[#lines + 1] = "best_ari k " .. k .. " " .. best.method .. " " .. ari_text(best.count_cuts[p].ari)
    end
    for _, result in ipairs(self.results) do
        local best = 1
        for p = 2, #self.settings.cut_counts do if rounded(result.count_cuts[p].silhouette) > rounded(result.count_cuts[best].silhouette) then best = p end end
        lines[#lines + 1] = "best_silhouette " .. result.method .. " k " .. self.settings.cut_counts[best] .. " " .. real(result.count_cuts[best].silhouette)
    end
    lines[#lines + 1] = "selected " .. self.results[self.chosen].method .. " k " .. self.kappa
    return lines
end

function Study:validation_report()
    local parts = {self:data_part(), self:correlation_part(), self:histogram_part()}
    for _, result in ipairs(self.results) do parts[#parts + 1] = self:linkage_part(result) end
    for _, result in ipairs(self.results) do if result.method == "single" then parts[#parts + 1] = self:mst_part(result) end end
    parts[#parts + 1] = self:compare_part()
    local cophenetic, agreement = self:comparison_parts()
    append(parts, {cophenetic, agreement, self:summary_part()})
    return join_parts(parts)
end

function Study:separation(first, second)
    local best = math.huge
    for _, i in ipairs(first) do for _, j in ipairs(second) do best = math.min(best, self.distances[i][j]) end end
    return best
end

function Study:cluster_lines(g)
    local group, majority = self.members[g], self.majority[g]
    local size, majority_count = #group, self.table[g][majority]
    local silhouette = distances.sum(map(group, function(i) return self.silhouettes[i] end)) / size
    local means = map(self.names, function(_, f) return distances.sum(map(group, function(i) return self.raw[i][f] end)) / size end)
    local medoid, medoid_sum, widest = nil, 0.0, nil
    for position, i in ipairs(group) do
        local total = distances.sum(map(group, function(j) return self.distances[i][j] end))
        if not medoid or total < medoid_sum then medoid, medoid_sum = i, total end
        for q = position + 1, #group do
            local j = group[q]
            if not widest or self.distances[i][j] > self.distances[widest[1]][widest[2]] then widest = {i, j} end
        end
    end
    local nearest, separation = nil, 0.0
    for h = 1, self.kappa do
        if h ~= g then
            local value = self:separation(group, self.members[h])
            if not nearest or value < separation then nearest, separation = h, value end
        end
    end
    return {"cluster " .. g .. " size " .. size .. " silhouette " .. real(silhouette) .. " majority " .. self.classes[majority] .. " purity " .. majority_count .. "/" .. size .. " " .. real(majority_count / size), "  mean " .. reals(means), "  medoid " .. self.idents[medoid] .. " diameter " .. (widest and self:pair_text(widest[1], widest[2]) or "0.0000 - -") .. " nearest " .. nearest .. " separation " .. real(separation)}
end

function Study:selection_part()
    local lines = {"selected linkage " .. self.results[self.chosen].method .. " k " .. self.kappa .. " ari " .. ari_text(self.selected_cut.ari) .. " silhouette " .. real(self.selected_cut.silhouette)}
    for g = 1, self.kappa do append(lines, self:cluster_lines(g)) end
    return lines
end

function Study:centroid_part()
    local centers, lines = self:centroids(self.selected), {"centroid_distances"}
    for g, first in ipairs(centers) do lines[#lines + 1] = g .. " " .. reals(map(centers, function(second) return math.sqrt(distances.squared(first, second)) end)) end
    return lines
end

function Study:profile_part()
    local width = maximum(map(self.names, function(name) return #name end))
    local lines = {"profile_bars"}
    for g, group in ipairs(self.members) do
        lines[#lines + 1] = "cluster " .. g
        for f, name in ipairs(self.names) do
            local zeta = distances.sum(map(group, function(i) return (self.raw[i][f] - self.means[f]) / self.deviations[f] end)) / #group
            local length = math.min(10, math.floor(math.abs(zeta) * 4))
            local left = zeta < 0 and string.rep(" ", 10 - length) .. string.rep("#", length) or string.rep(" ", 10)
            local right = zeta < 0 and string.rep(" ", 10) or string.rep("#", length) .. string.rep(" ", 10 - length)
            lines[#lines + 1] = name .. string.rep(" ", width - #name) .. " " .. left .. "|" .. right .. " " .. real(zeta)
        end
    end
    return lines
end

function Study:contingency_part()
    local lines = {"contingency", "cluster " .. table.concat(self.classes, " ") .. " total"}
    for g, row in ipairs(self.table) do lines[#lines + 1] = g .. " " .. integers(row) .. " " .. math.tointeger(distances.sum(row)) end
    local totals = map(self.classes, function(_, t)
        local total = 0
        for _, row in ipairs(self.table) do total = total + row[t] end
        return total
    end)
    lines[#lines + 1] = "total " .. integers(totals) .. " " .. self.count
    local matches = self:matches(self.selected)
    lines[#lines + 1] = "purity " .. math.tointeger(matches) .. "/" .. self.count .. " " .. real(matches / self.count)
    return lines
end

function Study:misplaced_part()
    local lines, count = {"misplaced"}, 0
    for i, g in ipairs(self.selected) do
        local majority = self.majority[g]
        if self.targets[i] ~= majority then count = count + 1; lines[#lines + 1] = self.idents[i] .. " label " .. self.labels[i] .. " cluster " .. g .. " majority " .. self.classes[majority] end
    end
    lines[#lines + 1] = "count " .. count
    return lines
end

function Study:weakest_part()
    local order, lines = range(self.count), {"weakest"}
    table.sort(order, function(a, b) return self.silhouettes[a] ~= self.silhouettes[b] and self.silhouettes[a] < self.silhouettes[b] or self.silhouettes[a] == self.silhouettes[b] and a < b end)
    for r = 1, self.settings.list_size do local i = order[r]; lines[#lines + 1] = self.idents[i] .. " label " .. self.labels[i] .. " cluster " .. self.selected[i] .. " silhouette " .. real(self.silhouettes[i]) end
    return lines
end

function Study:feature_part()
    local ratios = {}
    for f = 1, #self.names do
        local values = map(self.vectors, function(row) return row[f] end)
        local overall = distances.sum(values) / self.count
        local means = map(self.members, function(group) return distances.sum(map(group, function(i) return values[i] end)) / #group end)
        local between = distances.sum(map(self.members, function(group, g) return #group * (means[g] - overall) * (means[g] - overall) end))
        local within = distances.sum(map(self.selected, function(g, i) return (values[i] - means[g]) * (values[i] - means[g]) end))
        ratios[f] = (between / (self.kappa - 1)) / (within / (self.count - self.kappa))
    end
    local ranking, lines = range(#self.names), {"features"}
    table.sort(ranking, function(a, b) local x, y = rounded(ratios[a]), rounded(ratios[b]); return x ~= y and x > y or x == y and a < b end)
    for rank, f in ipairs(ranking) do lines[#lines + 1] = rank .. " " .. self.names[f] .. " f_ratio " .. real(ratios[f]) end
    return lines
end

function Study:class_counts(tree, node)
    local counts = map(self.classes, function() return 0 end)
    for _, i in ipairs(tree.members[node + 1]) do counts[self.targets[i]] = counts[self.targets[i]] + 1 end
    return table.concat(counts, "/")
end

function Study:top_merges_part()
    local tree, lines = self.results[self.chosen].tree, {"top_merges"}
    for step = self.count - self.settings.inconsistency_count, self.count - 1 do
        local merge = tree.merges[step]
        lines[#lines + 1] = "step " .. step .. " height " .. real(merge.height) .. " a " .. merge.a .. " " .. #tree.members[merge.a + 1] .. " " .. self:class_counts(tree, merge.a) .. " b " .. merge.b .. " " .. #tree.members[merge.b + 1] .. " " .. self:class_counts(tree, merge.b)
    end
    return lines
end

function Study:drop_feature_part()
    local lines = {"drop_feature"}
    for f, name in ipairs(self.names) do
        local reduced = map(self.vectors, function(row)
            local values = {}
            for g, value in ipairs(row) do if g ~= f then values[#values + 1] = value end end
            return values
        end)
        local tree = Tree.new(agglomerative.agglomerate(distances.matrix(reduced, self.settings.distance), self.results[self.chosen].method), self.count)
        local partition = tree:cut_into(self.kappa)
        lines[#lines + 1] = name .. " ari_selected " .. ari_text(self:partition_ari(partition, self.selected)) .. " ari_labels " .. ari_text(self:label_ari(partition))
    end
    return lines
end

function Study:refinement_part()
    local limit, iterations = self.settings.refine_iterations, self.settings.refine_iterations
    local centers, previous = self:centroids(self.selected), self.selected
    for t = 1, limit do
        local assignment = map(self.vectors, function(vector)
            local best, value = 1, distances.squared(vector, centers[1])
            for g = 2, #centers do local candidate = distances.squared(vector, centers[g]); if candidate < value then best, value = g, candidate end end
            return best
        end)
        local same = true
        for i = 1, self.count do if assignment[i] ~= previous[i] then same = false end end
        if same then iterations = t; break end
        for g, group in ipairs(cluster_members(assignment, self.kappa)) do if #group > 0 then centers[g] = centroid(map(group, function(i) return self.vectors[i] end)) end end
        previous = assignment
    end
    local changed = 0
    for i = 1, self.count do if previous[i] ~= self.selected[i] then changed = changed + 1 end end
    local sizes = map(cluster_members(previous, self.kappa), function(group) return #group end)
    return {"refinement max_iterations " .. limit, "iterations " .. iterations .. " changed " .. changed .. " wss " .. real(self:within(self.selected)) .. " -> " .. real(self:within(previous)), "sizes " .. integers(sizes) .. " silhouette " .. real(self:mean_silhouette(previous, self.distances)), "ari_selected " .. ari_text(self:partition_ari(previous, self.selected)) .. " ari_labels " .. ari_text(self:label_ari(previous))}
end

function Study:jaccard(partition, restricted)
    local counts = validation.contingency(restricted, partition, self.kappa, maximum(partition))
    local columns = map(range(#counts[1]), function(h)
        local total = 0
        for _, row in ipairs(counts) do total = total + row[h] end
        return total
    end)
    return map(counts, function(row)
        local size, best = 0, {0, 1}
        for _, common in ipairs(row) do size = size + common end
        if size > 0 then
            for h, common in ipairs(row) do
                local candidate = {common, size + columns[h] - common}
                if ari_greater(candidate, best) then best = candidate end
            end
        end
        return ari_value(best)
    end)
end

function Study:stability_part()
    local settings, n = self.settings, self.count
    local size, state = n * settings.percent // 100, settings.seed
    local aris, jaccards = {}, {}
    local lines = {"stability replicates " .. settings.replicates .. " percent " .. settings.percent .. " seed " .. settings.seed}
    for b = 1, settings.replicates do
        local order = range(n)
        for t = 1, size do
            state = 48271 * state % 2147483647
            local j = t + state % (n - t + 1)
            order[t], order[j] = order[j], order[t]
        end
        local sample = {}
        for i = 1, size do sample[i] = order[i] end
        table.sort(sample)
        local delta = map(sample, function(i) return map(sample, function(j) return self.distances[i][j] end) end)
        local tree = Tree.new(agglomerative.agglomerate(delta, self.results[self.chosen].method), size)
        local partition, restricted = tree:cut_into(self.kappa), map(sample, function(i) return self.selected[i] end)
        local ari, jaccard = self:partition_ari(partition, restricted), self:jaccard(partition, restricted)
        aris[b], jaccards[b] = ari_value(ari), jaccard
        lines[#lines + 1] = "replicate " .. b .. " size " .. size .. " ari " .. ari_text(ari) .. " jaccard " .. reals(jaccard)
    end
    local means = map(range(self.kappa), function(g) return distances.sum(map(jaccards, function(row) return row[g] end)) / settings.replicates end)
    lines[#lines + 1], lines[#lines + 2] = "mean_ari " .. real(distances.sum(aris) / settings.replicates), "mean_jaccard " .. reals(means)
    return lines
end

function Study:distance_map_part()
    local order, method = self.results[self.chosen].tree.order, self.results[self.chosen].method
    local frame = "+" .. string.rep("-", self.count) .. "+"
    local lines, shades = {"distance_map " .. method, frame}, "@%#*+=-:. "
    for _, i in ipairs(order) do
        local row = map(order, function(j) local b = histogram_bin(self.distances[i][j], self.distance_max); return shades:sub(b + 1, b + 1) end)
        lines[#lines + 1] = "|" .. table.concat(row) .. "|"
    end
    lines[#lines + 1] = frame
    return lines
end

function Study:profiles_report()
    return join_parts({self:selection_part(), self:centroid_part(), self:profile_part(), self:contingency_part(), self:misplaced_part(), self:weakest_part(), self:feature_part(), self:top_merges_part(), self:drop_feature_part(), self:refinement_part(), self:stability_part(), self:distance_map_part()})
end

local names, observations = dataset.read_observations("input/data.csv")
local study = Study.new(names, observations, dataset.read_settings("input/params.txt"))
os.execute("mkdir -p output")
dataset.write_lines("output/linkage.csv", study:linkage_table())
dataset.write_lines("output/clusters.csv", study:clusters_table())
dataset.write_lines("output/dendrogram.txt", study:dendrogram_report())
dataset.write_lines("output/trees.txt", study:trees_report())
dataset.write_lines("output/validation.txt", study:validation_report())
dataset.write_lines("output/profiles.txt", study:profiles_report())
