local directory = arg[0]:match("^(.*[/\\])") or "./"
package.path = directory .. "?.lua;" .. package.path
local tx = require("transactions")
local f = require("features")
local km = require("kmeans")
local v = require("validation")
local profiles = require("profiles")
local r = require("report")

local function map(values, transform)
    local result = {}
    for i, value in ipairs(values) do result[i] = transform(value, i) end
    return result
end

local function copy(values) return map(values, function(value) return value end) end
local function integers(values) return table.concat(values, " ") end
local function yes_no(flag) return flag and "yes" or "no" end
local function sum_int(values)
    local total = 0
    for _, value in ipairs(values) do total = total + value end
    return total
end

local function blocks(sections)
    local lines = {}
    for i, section in ipairs(sections) do
        if i > 1 then lines[#lines + 1] = "" end
        for _, line in ipairs(section) do lines[#lines + 1] = line end
    end
    return lines
end

local function append(lines, extra) for _, line in ipairs(extra) do lines[#lines + 1] = line end end

local Generator = {}
Generator.__index = Generator
function Generator:draw() self.state = 48271 * self.state % 2147483647; return self.state end

local function initial(points, k, method, restart, generator)
    local chosen = {}
    if method == "forgy" then
        local used = {}
        while #chosen < k do
            local index = generator:draw() % #points + 1
            if not used[index] then chosen[#chosen + 1], used[index] = index, true end
        end
        return chosen
    end
    if method == "maximin" then
        local center, order = km.mean(points), {}
        local distances = map(points, function(point) return km.distance(point, center) end)
        for i = 1, #points do order[i] = i end
        table.sort(order, function(a, b) return distances[a] < distances[b] or distances[a] == distances[b] and a < b end)
        chosen[1] = order[restart]
    else chosen[1] = generator:draw() % #points + 1 end
    while #chosen < k do
        local gaps = map(points, function(point)
            local best = km.distance(point, points[chosen[1]])
            for j = 2, #chosen do best = math.min(best, km.distance(point, points[chosen[j]])) end
            return best
        end)
        local selected = 1
        if method == "maximin" then
            for i = 2, #gaps do if gaps[i] > gaps[selected] then selected = i end end
        else
            local threshold = (generator:draw() / 2147483647) * f.sum(gaps)
            local cumulative = 0.0
            selected = nil
            for i, gap in ipairs(gaps) do cumulative = cumulative + gap; if cumulative > threshold then selected = i; break end end
            if not selected then for i, gap in ipairs(gaps) do if gap > 0 then selected = i end end end
        end
        chosen[#chosen + 1] = selected
    end
    return chosen
end

local function refine(points, original, k, limit)
    local labels = copy(original)
    local groups, centers = km.groups(labels, k), km.centers(points, labels, k)
    local sizes = map(groups, function(group) return #group end)
    local passes, transfers = 0, 0
    while passes < limit do
        local changes = 0
        for i, point in ipairs(points) do
            local own = labels[i]
            if sizes[own] > 1 then
                local removal = (sizes[own] / (sizes[own] - 1)) * km.distance(point, centers[own])
                local target, cost
                for j = 1, k do if j ~= own then
                    local insertion = (sizes[j] / (sizes[j] + 1)) * km.distance(point, centers[j])
                    if not target or insertion < cost then target, cost = j, insertion end
                end end
                if cost < removal then
                    labels[i] = target
                    sizes[own], sizes[target] = sizes[own] - 1, sizes[target] + 1
                    centers[own], centers[target] = km.center(points, labels, own), km.center(points, labels, target)
                    changes, transfers = changes + 1, transfers + 1
                end
            end
        end
        passes = passes + 1
        if changes == 0 then break end
    end
    return {labels = labels, passes = passes, transfers = transfers, sse = km.sse(points, labels, km.centers(points, labels, k))}
end

local function run(points, k, method, restart, limit, generator)
    local seeds = initial(points, k, method, restart, generator)
    local result = km.lloyd(points, map(seeds, function(index) return points[index] end), limit)
    return {method = method, restart = restart, seeds = seeds, result = result, refined = refine(points, result.labels, k, limit)}
end

local function organize(points, labels, k)
    local groups = km.groups(labels, k)
    table.sort(groups, function(a, b) return #a > #b or #a == #b and a[1] < b[1] end)
    local ordered = {}
    for label, members in ipairs(groups) do for _, i in ipairs(members) do ordered[i] = label end end
    local centers = km.centers(points, ordered, k)
    return {k = k, labels = ordered, members = groups, centers = centers, sse = km.sse(points, ordered, centers)}
end

local function gini(spends)
    local ordered = copy(spends)
    table.sort(ordered)
    local total, weighted = 0, 0
    for i, spend in ipairs(ordered) do total, weighted = total + spend, weighted + i * spend end
    return (2 * weighted - (#ordered + 1) * total) / (#ordered * total)
end

local function category_totals(customers)
    local totals = {}
    for _, customer in ipairs(customers) do
        for category, spend in pairs(customer.category_spend) do totals[category] = (totals[category] or 0) + spend end
    end
    return totals
end

local function sorted_keys(values)
    local keys = {}; for key in pairs(values) do keys[#keys + 1] = key end
    table.sort(keys)
    return keys
end

local Analysis = {}
Analysis.__index = Analysis

function Analysis.new()
    local self = setmetatable({}, Analysis)
    self.p = tx.params("input/params.txt")
    self.data, self.rules = tx.read("input/transactions.csv"), profiles.read("input/segment_rules.txt")
    self.orders = tx.orders(self.data.rows, 1, self.p.REFERENCE_DAY)
    self.order_groups = tx.by_customer(self.orders)
    self.customers = f.customers(self.orders, self.p.REFERENCE_DAY)
    self.n = #self.customers
    self.numbers = {}; for i, customer in ipairs(self.customers) do self.numbers[customer.id] = i end
    self.scaling = f.scaling(self.customers)
    self.points = map(self.customers, function(customer) return f.standardize(customer.transformed, self.scaling) end)
    self.generator = setmetatable({state = self.p.SEED}, Generator)
    self.solutions = {}
    self:fit()
    self:details()
    self.jaccards = self:subsamples()
    return self
end

function Analysis:ids(indices) return table.concat(map(indices, function(i) return self.customers[i].id end), " ") end

function Analysis:fit()
    local p, table_ = self.p, v.distances(self.points)
    for k = p.K_RANGE[1], p.K_RANGE[2] do
        local runs, bests, best = {}, {}, nil
        for _, method in ipairs(p.METHODS) do
            local method_best
            for restart = 1, p.RESTARTS do
                local result = run(self.points, k, method, restart, p.MAX_ITERATIONS, self.generator)
                runs[#runs + 1] = result
                if not method_best or r.key(result.refined.sse) < r.key(method_best.refined.sse) then method_best = result end
            end
            bests[#bests + 1] = method_best
            if not best or r.key(method_best.refined.sse) < r.key(best.refined.sse) then best = method_best end
        end
        local solution = organize(self.points, best.refined.labels, k)
        solution.runs, solution.bests, solution.best = runs, bests, best
        solution.indices = v.indices(self.points, solution, table_)
        solution.names, solution.rules = {}, {}
        local used = {}
        for j, center in ipairs(solution.centers) do
            local rule = profiles.rule_number(center, self.rules)
            used[rule] = (used[rule] or 0) + 1
            solution.rules[j] = rule
            solution.names[j] = self.rules[rule].name .. (used[rule] == 1 and "" or "_" .. used[rule])
        end
        self.solutions[k] = solution
    end
    for k = p.K_RANGE[1], p.K_RANGE[2] do
        local solution = self.solutions[k]
        solution.indices.elbow = v.elbow(k, p.K_RANGE[1], p.K_RANGE[2], solution.sse, self.solutions[p.K_RANGE[1]].sse, self.solutions[p.K_RANGE[2]].sse)
        if k < p.K_RANGE[2] then solution.hartigan = v.hartigan(solution.sse, self.solutions[k + 1].sse, self.n, k) end
    end
    self.vote_names = {"elbow", "silhouette", "calinski_harabasz", "davies_bouldin", "hartigan"}
    self.votes, self.vote_counts = {}, {}
    for _, criterion in ipairs(self.vote_names) do
        local chosen
        if criterion == "hartigan" then
            chosen = p.K_RANGE[2]
            for k = p.K_RANGE[1], p.K_RANGE[2] - 1 do if self.solutions[k].hartigan <= 10 then chosen = k; break end end
        else
            local first = p.K_RANGE[1] + (criterion == "elbow" and 1 or 0)
            local last = p.K_RANGE[2] - (criterion == "elbow" and 1 or 0)
            chosen = first
            for k = first + 1, last do
                local value, current = r.key(self.solutions[k].indices[criterion]), r.key(self.solutions[chosen].indices[criterion])
                if criterion == "davies_bouldin" and value < current or criterion ~= "davies_bouldin" and value > current then chosen = k end
            end
        end
        self.votes[#self.votes + 1] = chosen
        self.vote_counts[chosen] = (self.vote_counts[chosen] or 0) + 1
    end
    self.k = p.K_RANGE[1]
    for k = self.k + 1, p.K_RANGE[2] do
        local count, previous = self.vote_counts[k] or 0, self.vote_counts[self.k] or 0
        if count > previous or count == previous and r.key(self.solutions[k].indices.silhouette) > r.key(self.solutions[self.k].indices.silhouette) then self.k = k end
    end
    self.final = self.solutions[self.k]
end

function Analysis:details()
    local solution = self.final
    self.distances, self.others, self.scores, self.codes = {}, {}, {}, {}
    for i, customer in ipairs(self.customers) do
        local own, other, best = solution.labels[i], nil, nil
        self.distances[i] = math.sqrt(km.distance(self.points[i], solution.centers[own]))
        for j, center in ipairs(solution.centers) do if j ~= own then
            local distance = km.distance(self.points[i], center)
            if not other or distance < best then other, best = j, distance end
        end end
        self.others[i] = {other, math.sqrt(best)}
        local ranks = {0, 0, 0}
        for _, candidate in ipairs(self.customers) do
            if candidate.raw[1] > customer.raw[1] then ranks[1] = ranks[1] + 1 end
            if candidate.raw[2] < customer.raw[2] then ranks[2] = ranks[2] + 1 end
            if candidate.spend < customer.spend then ranks[3] = ranks[3] + 1 end
        end
        self.scores[i] = map(ranks, function(rank) return 1 + 5 * rank // self.n end)
        self.codes[i] = table.concat(self.scores[i])
    end
    self.total_spend = sum_int(map(self.customers, function(customer) return customer.spend end))
    self.categories = category_totals(self.customers)
    self.category_names = sorted_keys(self.categories)
    self.segment_spends, self.segment_categories, self.rankings, self.segment_sse = {}, {}, {}, {}
    for j, members in ipairs(solution.members) do
        local customers = map(members, function(i) return self.customers[i] end)
        self.segment_spends[j] = sum_int(map(customers, function(customer) return customer.spend end))
        local totals = category_totals(customers)
        self.segment_categories[j] = totals
        local ranking = {}; for category, amount in pairs(totals) do if amount > 0 then ranking[#ranking + 1] = category end end
        table.sort(ranking, function(a, b) return totals[a] > totals[b] or totals[a] == totals[b] and a < b end)
        self.rankings[j] = ranking
        self.segment_sse[j] = f.sum(map(members, function(i) return km.distance(self.points[i], solution.centers[j]) end))
    end
end

function Analysis:subsamples()
    local size, values = self.n * self.p.SUBSAMPLE_PERCENT // 100, {}
    for j = 1, self.k do values[j] = {} end
    for b = 1, self.p.SUBSAMPLES do
        local order = {}; for i = 1, self.n do order[i] = i end
        for i = 1, size do
            local j = i + self.generator:draw() % (self.n - i + 1)
            order[i], order[j] = order[j], order[i]
        end
        local sample = {}; for i = 1, size do sample[i] = order[i] end; table.sort(sample)
        local result = km.lloyd(map(sample, function(i) return self.points[i] end), self.final.centers, self.p.MAX_ITERATIONS)
        for segment = 1, self.k do
            local best = 0.0
            for j = 1, self.k do
                local both, either = 0, 0
                for i, number in ipairs(sample) do
                    local member, assigned = self.final.labels[number] == segment, result.labels[i] == j
                    if member and assigned then both = both + 1 end
                    if member or assigned then either = either + 1 end
                end
                if either > 0 then best = math.max(best, both / either) end
            end
            values[segment][b] = best
        end
    end
    return values
end

function Analysis:features_lines()
    local lines = {"customer,recency,frequency,monetary,basket,categories,tenure,z_recency,z_frequency,z_monetary,z_basket,z_categories,z_tenure"}
    for i, customer in ipairs(self.customers) do
        local raw = customer.raw
        local fields = {customer.id, raw[1], raw[2], r.amount(customer.spend), r.real(raw[4]), raw[5], raw[6]}
        append(fields, map(self.points[i], r.real))
        lines[#lines + 1] = table.concat(fields, ",")
    end
    return lines
end

function Analysis:runs_lines()
    local sections = {}
    for k = self.p.K_RANGE[1], self.p.K_RANGE[2] do
        local solution, lines = self.solutions[k], {"k " .. k}
        for _, result in ipairs(solution.runs) do
            local ll, refined = result.result, result.refined
            lines[#lines + 1] = "run " .. result.method .. " " .. result.restart .. " seeds " .. self:ids(result.seeds) .. " iterations " .. ll.iterations .. " converged " .. yes_no(ll.converged) .. " reseeds " .. ll.reseeds .. " sse " .. r.real(ll.sse) .. " passes " .. refined.passes .. " transfers " .. refined.transfers .. " refined " .. r.real(refined.sse)
        end
        for _, result in ipairs(solution.bests) do lines[#lines + 1] = "best " .. result.method .. " restart " .. result.restart .. " sse " .. r.real(result.refined.sse) end
        local chosen = solution.best
        lines[#lines + 1] = "chosen " .. chosen.method .. " restart " .. chosen.restart .. " sse " .. r.real(chosen.refined.sse)
        lines[#lines + 1] = "sizes " .. integers(map(solution.members, function(members) return #members end))
        sections[#sections + 1] = lines
    end
    return blocks(sections)
end

function Analysis:selection_lines()
    local indices, names, stability = {"indices"}, {"segments"}, {"stability"}
    for k = self.p.K_RANGE[1], self.p.K_RANGE[2] do
        local solution = self.solutions[k]
        local ix = solution.indices
        indices[#indices + 1] = "k=" .. k .. " sse " .. r.real(solution.sse) .. " elbow " .. r.real(ix.elbow) .. " silhouette " .. r.real(ix.silhouette) .. " calinski_harabasz " .. r.real(ix.calinski_harabasz) .. " davies_bouldin " .. r.real(ix.davies_bouldin) .. " hartigan " .. (solution.hartigan and r.real(solution.hartigan) or "-")
        names[#names + 1] = "k=" .. k .. " " .. table.concat(map(solution.members, function(members, j) return solution.names[j] .. ":" .. #members end), " ")
        local parts = {"k=" .. k}
        for i, first in ipairs(solution.bests) do for j = i + 1, #solution.bests do
            local second = solution.bests[j]
            parts[#parts + 1] = first.method .. ":" .. second.method .. " " .. r.real(v.ari(first.refined.labels, second.refined.labels))
        end end
        parts[#parts + 1] = "final"
        for _, result in ipairs(solution.bests) do parts[#parts + 1] = result.method .. " " .. r.real(v.ari(result.refined.labels, solution.labels)) end
        parts[#parts + 1] = "next " .. (k == self.p.K_RANGE[2] and "-" or r.real(v.ari(solution.labels, self.solutions[k + 1].labels)))
        stability[#stability + 1] = table.concat(parts, " ")
    end
    local votes = {"votes"}
    for i, name in ipairs(self.vote_names) do votes[#votes + 1] = name .. " k=" .. self.votes[i] end
    votes[#votes + 1] = "chosen k=" .. self.k .. " votes " .. self.vote_counts[self.k]
    return blocks({indices, votes, names, stability})
end

function Analysis:segments_lines()
    local lines = {"customer,segment,name,distance,other,other_distance,silhouette,recommend"}
    for i, customer in ipairs(self.customers) do
        local label, recommend = self.final.labels[i], "-"
        for _, category in ipairs(self.rankings[label]) do if (customer.category_spend[category] or 0) <= 0 then recommend = category; break end end
        lines[#lines + 1] = table.concat({customer.id, label, self.final.names[label], r.real(self.distances[i]), self.others[i][1], r.real(self.others[i][2]), r.real(self.final.indices.silhouettes[i]), recommend}, ",")
    end
    return lines
end

function Analysis:related(members, k)
    if k < self.p.K_RANGE[1] or k > self.p.K_RANGE[2] then return "k=" .. k .. " -" end
    local counts = {}; for j = 1, k do counts[j] = 0 end
    for _, i in ipairs(members) do local label = self.solutions[k].labels[i]; counts[label] = counts[label] + 1 end
    local best = 1; for j = 2, k do if counts[j] > counts[best] then best = j end end
    return "k=" .. k .. " segment " .. best .. " shared " .. counts[best]
end

function Analysis:profile_lines(segment)
    local members, center = self.final.members[segment], self.final.centers[segment]
    local customers = map(members, function(i) return self.customers[i] end)
    local size, spend = #members, self.segment_spends[segment]
    local lines = {"segment " .. segment .. " " .. self.final.names[segment] .. " rule " .. self.final.rules[segment] .. " size " .. size .. " share " .. r.real(size / self.n) .. " revenue " .. r.amount(spend) .. " revenue_share " .. r.real(spend / self.total_spend)}
    lines[#lines + 1] = "  center " .. r.reals(center)
    lines[#lines + 1] = "  value " .. table.concat(map(profiles.original(center, self.scaling), function(value, i) return f.names[i] .. " " .. r.real(value) end), " ")
    local order = {1, 2, 3, 4, 5, 6}
    table.sort(order, function(a, b) return math.abs(center[a]) > math.abs(center[b]) or math.abs(center[a]) == math.abs(center[b]) and a < b end)
    lines[#lines + 1] = "  traits " .. (center[order[1]] > 0 and "high_" or "low_") .. f.names[order[1]] .. " " .. (center[order[2]] > 0 and "high_" or "low_") .. f.names[order[2]]
    local medians = {}
    for feature = 1, 6 do
        local values = map(customers, function(customer) return feature == 3 and customer.spend or customer.raw[feature] end)
        table.sort(values); medians[feature] = values[(size - 1) // 2 + 1]
    end
    lines[#lines + 1] = "  median recency " .. medians[1] .. " frequency " .. medians[2] .. " monetary " .. r.amount(medians[3]) .. " basket " .. r.real(medians[4]) .. " categories " .. medians[5] .. " tenure " .. medians[6]
    lines[#lines + 1] = "  related " .. self:related(members, self.k - 1) .. " " .. self:related(members, self.k + 1)
    local top = copy(members)
    table.sort(top, function(a, b) return self.customers[a].spend > self.customers[b].spend or self.customers[a].spend == self.customers[b].spend and a < b end)
    local parts = {"  top_customers"}
    for j = 1, math.min(#top, self.p.TOP_CUSTOMERS) do local customer = self.customers[top[j]]; parts[#parts + 1] = customer.id .. " " .. r.amount(customer.spend) end
    lines[#lines + 1] = table.concat(parts, " ")
    local gaps, overdue, bins, gross, returned, cancelled = {}, 0, {}, 0, 0, 0
    for j = 1, #self.p.ORDER_BINS + 1 do bins[j] = 0 end
    for _, customer in ipairs(customers) do
        local raw = customer.raw
        if raw[2] >= 2 then
            gaps[#gaps + 1] = (raw[6] - raw[1]) / (raw[2] - 1)
            if raw[1] * (raw[2] - 1) > self.p.OVERDUE_FACTOR * (raw[6] - raw[1]) then overdue = overdue + 1 end
        end
        for _, purchase in ipairs(customer.orders) do
            local bin = 1; for _, bound in ipairs(self.p.ORDER_BINS) do if purchase.net >= bound * 100 then bin = bin + 1 end end
            bins[bin] = bins[bin] + 1
        end
        for _, purchase in ipairs(self.order_groups[customer.id]) do
            if purchase.net <= 0 then cancelled = cancelled + 1 end
            for _, row in ipairs(purchase.rows) do if row.amount > 0 then gross = gross + row.amount else returned = returned - row.amount end end
        end
    end
    lines[#lines + 1] = "  cadence customers " .. #gaps .. " mean_gap " .. (#gaps > 0 and r.real(f.mean(gaps)) or "-") .. " overdue " .. overdue
    lines[#lines + 1] = "  order_sizes " .. integers(bins)
    lines[#lines + 1] = "  sse " .. r.real(self.segment_sse[segment]) .. " share " .. r.real(self.segment_sse[segment] / self.final.sse)
    lines[#lines + 1] = "  gini " .. r.real(gini(map(customers, function(customer) return customer.spend end)))
    lines[#lines + 1] = "  returns rate " .. r.real(returned / gross) .. " returned " .. r.amount(returned) .. " cancelled " .. cancelled
    local silhouettes = map(members, function(i) return self.final.indices.silhouettes[i] end)
    local negative = 0; for _, value in ipairs(silhouettes) do if value < 0 then negative = negative + 1 end end
    lines[#lines + 1] = "  silhouette " .. r.real(f.mean(silhouettes)) .. " negative " .. negative
    local scores, counts = {0, 0, 0}, {}
    for _, i in ipairs(members) do
        for j = 1, 3 do scores[j] = scores[j] + self.scores[i][j] end
        counts[self.codes[i]] = (counts[self.codes[i]] or 0) + 1
    end
    local codes = sorted_keys(counts)
    table.sort(codes, function(a, b) return counts[a] > counts[b] or counts[a] == counts[b] and a < b end)
    lines[#lines + 1] = "  rfm r " .. r.real(scores[1] / size) .. " f " .. r.real(scores[2] / size) .. " m " .. r.real(scores[3] / size) .. " mode " .. codes[1] .. " " .. counts[codes[1]]
    parts = {"  categories"}
    for j = 1, math.min(#self.rankings[segment], self.p.TOP_CATEGORIES) do
        local category = self.rankings[segment][j]
        local share = self.segment_categories[segment][category] / spend
        parts[#parts + 1] = category .. " " .. r.real(share) .. " " .. r.real(share / (self.categories[category] / self.total_spend))
    end
    lines[#lines + 1] = table.concat(parts, " ")
    local outliers = {}
    if size >= 2 then
        local distances = map(members, function(i) return self.distances[i] end)
        local limit = f.mean(distances) + self.p.OUTLIER_SD * f.sd(distances)
        for _, i in ipairs(members) do if self.distances[i] > limit then outliers[#outliers + 1] = self.customers[i].id end end
    end
    lines[#lines + 1] = "  outliers " .. #outliers .. (#outliers > 0 and " " .. table.concat(outliers, " ") or "")
    return lines
end

function Analysis:profiles_lines()
    local sections = {{"segments k=" .. self.k .. " customers " .. self.n .. " revenue " .. r.amount(self.total_spend) .. " gini " .. r.real(gini(map(self.customers, function(customer) return customer.spend end)))}}
    for j = 1, self.k do sections[#sections + 1] = self:profile_lines(j) end
    local numbers = {}; for j = 1, self.k do numbers[j] = j end
    local mix = {"category_mix " .. integers(numbers)}
    for _, category in ipairs(self.category_names) do mix[#mix + 1] = category .. " " .. r.reals(map(self.segment_spends, function(spend, j) return (self.segment_categories[j][category] or 0) / spend end)) end
    local recency = {"rfm_recency " .. integers(numbers)}
    for score = 5, 1, -1 do
        local counts = {}; for j = 1, self.k do counts[j] = 0 end
        for i, scores in ipairs(self.scores) do if scores[1] == score then local label = self.final.labels[i]; counts[label] = counts[label] + 1 end end
        recency[#recency + 1] = "r=" .. score .. " " .. integers(counts)
    end
    recency[#recency + 1] = "ari rfm_codes " .. r.real(v.ari(self.codes, self.final.labels))
    local centers = {"center_distances"}
    for j, center in ipairs(self.final.centers) do centers[#centers + 1] = j .. " " .. r.reals(map(self.final.centers, function(other) return math.sqrt(km.distance(center, other)) end)) end
    sections[#sections + 1], sections[#sections + 2], sections[#sections + 3] = mix, recency, centers
    return blocks(sections)
end

function Analysis:robustness_lines()
    local subsamples = {"subsamples " .. self.p.SUBSAMPLES .. " size " .. self.n * self.p.SUBSAMPLE_PERCENT // 100}
    for j, values in ipairs(self.jaccards) do
        subsamples[#subsamples + 1] = "segment " .. j .. " " .. self.final.names[j] .. " mean_jaccard " .. r.real(f.mean(values)) .. " min_jaccard " .. r.real(math.min(table.unpack(values)))
    end
    local ablation = {"ablation"}
    for feature, name in ipairs(f.names) do
        local points = map(self.points, function(point)
            local reduced = {}; for j, value in ipairs(point) do if j ~= feature then reduced[#reduced + 1] = value end end; return reduced
        end)
        local result = run(points, self.k, "maximin", 1, self.p.MAX_ITERATIONS, self.generator)
        ablation[#ablation + 1] = "without " .. name .. " seeds " .. self:ids(result.seeds) .. " iterations " .. result.result.iterations .. " converged " .. yes_no(result.result.converged) .. " transfers " .. result.refined.transfers .. " sse " .. r.real(result.refined.sse) .. " ari " .. r.real(v.ari(result.refined.labels, self.final.labels))
    end
    local members = self.final.members[1]
    local points = map(members, function(i) return self.points[i] end)
    local result = run(points, 2, "maximin", 1, self.p.MAX_ITERATIONS, self.generator)
    local parts = organize(points, result.refined.labels, 2)
    local drilldown = {"drilldown segment 1 " .. self.final.names[1] .. " size " .. #members .. " seeds " .. self:ids(map(result.seeds, function(i) return members[i] end)) .. " iterations " .. result.result.iterations .. " converged " .. yes_no(result.result.converged) .. " transfers " .. result.refined.transfers,
        "sse before " .. r.real(self.segment_sse[1]) .. " after " .. r.real(result.refined.sse) .. " gain " .. r.real(self.segment_sse[1] - result.refined.sse)}
    for j, group in ipairs(parts.members) do drilldown[#drilldown + 1] = "part " .. j .. " size " .. #group .. " center " .. r.reals(parts.centers[j]) end
    return blocks({subsamples, ablation, drilldown})
end

function Analysis:tracking_lines()
    local p, periods = self.p, {"periods " .. self.p.PERIODS .. " days " .. self.p.PERIOD_DAYS}
    for q = 1, p.PERIODS do
        local first, last = p.REFERENCE_DAY - q * p.PERIOD_DAYS + 1, p.REFERENCE_DAY - (q - 1) * p.PERIOD_DAYS
        local revenue, active, acquired = {}, {}, {}
        for j = 1, self.k do revenue[j], active[j], acquired[j] = 0, 0, 0 end
        for i, customer in ipairs(self.customers) do
            local label, used = self.final.labels[i], false
            for _, order in ipairs(customer.orders) do if first <= order.day and order.day <= last then revenue[label] = revenue[label] + order.net; used = true end end
            if used then active[label] = active[label] + 1 end
            local initial_day = p.REFERENCE_DAY - customer.raw[6]
            if first <= initial_day and initial_day <= last then acquired[label] = acquired[label] + 1 end
        end
        periods[#periods + 1] = "period " .. q .. " days " .. first .. " " .. last .. " revenue " .. table.concat(map(revenue, r.amount), " ") .. " active " .. integers(active) .. " acquired " .. integers(acquired)
    end
    local snapshot = f.customers(tx.orders(self.data.rows, 1, p.SNAPSHOT_DAY), p.SNAPSHOT_DAY)
    local previous = {}
    for _, customer in ipairs(snapshot) do
        local point = f.standardize(customer.transformed, self.scaling)
        local labels = km.assign({point}, self.final.centers)
        previous[customer.id] = labels[1]
    end
    local table_, moved, stayed, fresh, lost = {}, {}, 0, 0, 0
    for j = 1, self.k + 1 do table_[j] = {}; for k = 1, self.k do table_[j][k] = 0 end end
    for i, customer in ipairs(self.customers) do
        local current, old = self.final.labels[i], previous[customer.id] or self.k + 1
        table_[old][current] = table_[old][current] + 1
        if old == self.k + 1 then fresh = fresh + 1
        elseif old == current then stayed = stayed + 1
        else moved[#moved + 1] = customer.id .. " " .. old .. " " .. current end
    end
    for id in pairs(previous) do if not self.numbers[id] then lost = lost + 1 end end
    local numbers = {}; for j = 1, self.k do numbers[j] = j end
    local migration = {"migration day " .. p.SNAPSHOT_DAY .. " customers " .. #snapshot, "from\\to " .. integers(numbers)}
    for j, row in ipairs(table_) do migration[#migration + 1] = (j == self.k + 1 and "none" or j) .. " " .. integers(row) end
    migration[#migration + 1] = "moved_customers"; append(migration, moved)
    migration[#migration + 1] = "stayed " .. stayed .. " moved " .. #moved .. " new " .. fresh .. " lost " .. lost
    local purchases = {}
    for _, order in ipairs(tx.orders(self.data.rows, p.REFERENCE_DAY + 1, p.REFERENCE_DAY + p.OUTCOME_DAYS)) do
        if order.net > 0 then purchases[order.customer] = (purchases[order.customer] or 0) + order.net end
    end
    local outcome = {"outcome days " .. p.REFERENCE_DAY + 1 .. " " .. p.REFERENCE_DAY + p.OUTCOME_DAYS}
    for j, members in ipairs(self.final.members) do
        local buyers, spend = 0, 0
        for _, i in ipairs(members) do local value = purchases[self.customers[i].id]; if value then buyers, spend = buyers + 1, spend + value end end
        outcome[#outcome + 1] = "segment " .. j .. " " .. self.final.names[j] .. " size " .. #members .. " buyers " .. buyers .. " rate " .. r.real(buyers / #members) .. " revenue " .. r.amount(spend) .. " per_customer " .. r.real((spend / 100) / #members)
    end
    local outsiders, spend = 0, 0
    for id, value in pairs(purchases) do if not self.numbers[id] then outsiders, spend = outsiders + 1, spend + value end end
    outcome[#outcome + 1] = "unsegmented buyers " .. outsiders .. " revenue " .. r.amount(spend)
    return blocks({periods, migration, outcome})
end

function Analysis:summary_lines()
    local used, returns, later, valid = 0, 0, 0, 0
    for _, row in ipairs(self.data.rows) do if row.day <= self.p.REFERENCE_DAY then used = used + 1; if row.amount < 0 then returns = returns + 1 end else later = later + 1 end end
    for _, order in ipairs(self.orders) do if order.net > 0 then valid = valid + 1 end end
    local excluded = {}; for _, id in ipairs(sorted_keys(self.data.customers)) do if not self.numbers[id] then excluded[#excluded + 1] = id end end
    local data = {"rows " .. self.data.count .. " duplicates " .. self.data.duplicates .. " zero " .. self.data.zero .. " used " .. used .. " returns " .. returns .. " later " .. later,
        "orders " .. #self.orders .. " valid " .. valid .. " cancelled " .. #self.orders - valid,
        "customers " .. #sorted_keys(self.data.customers) .. " clustered " .. self.n .. " excluded " .. #excluded,
        "excluded_ids " .. (#excluded > 0 and table.concat(excluded, " ") or "-")}
    local categories = {}
    for _, category in ipairs(self.category_names) do
        local buyers = 0; for _, customer in ipairs(self.customers) do if (customer.category_spend[category] or 0) > 0 then buyers = buyers + 1 end end
        categories[#categories + 1] = "category " .. category .. " revenue " .. r.amount(self.categories[category]) .. " share " .. r.real(self.categories[category] / self.total_spend) .. " customers " .. buyers
    end
    local features, correlations = {}, {"correlation " .. table.concat(f.names, " ")}
    for j, name in ipairs(f.names) do
        local scale = self.scaling[j]
        features[#features + 1] = "feature " .. name .. " transform " .. (f.root(j) and "sqrt" or "none") .. " raw_mean " .. r.real(scale.raw_mean) .. " raw_sd " .. r.real(scale.raw_sd) .. " mean " .. r.real(scale.mean) .. " sd " .. r.real(scale.sd)
        local values = {}; for e = 1, 6 do values[e] = f.correlation(self.points, j, e) end
        correlations[#correlations + 1] = name .. " " .. r.reals(values)
    end
    return blocks({data, categories, features, correlations})
end

local analysis = Analysis.new()
os.execute("mkdir -p output")
r.write("features.csv", analysis:features_lines())
r.write("runs.txt", analysis:runs_lines())
r.write("selection.txt", analysis:selection_lines())
r.write("segments.csv", analysis:segments_lines())
r.write("profiles.txt", analysis:profiles_lines())
r.write("robustness.txt", analysis:robustness_lines())
r.write("tracking.txt", analysis:tracking_lines())
r.write("summary.txt", analysis:summary_lines())
