local dataset = require("dataset")
local gaussian = require("gaussian")
local em = require("em")
local kmeans = require("kmeans")
local report = require("report")
local dec, values, ints = report.dec, report.values, report.integers
local points, initial, settings = dataset.read()
local n = #points
local function xy(point) return {point.x, point.y} end
local function maximum(row)
    local best = 1
    for k = 2, #row do if row[k] > row[best] then best = k end end
    return best, row[best]
end
local function parameter_count(k, kind)
    if kind == "FULL" then return 6 * k - 1
    elseif kind == "TIED" then return 3 * k + 2
    elseif kind == "DIAG" then return 5 * k - 1
    else return 4 * k - 1 end
end
local function entropy(row)
    local total = 0.0
    for _, r in ipairs(row) do if r > 0 then total = total + r * math.log(r) end end
    return -total
end
local function summarize(fitted, count, kind, type_index, sample_size)
    local p = parameter_count(count, kind)
    fitted.k, fitted.kind, fitted.type_index, fitted.p = count, kind, type_index, p
    fitted.bic = -2 * fitted.loglik + p * math.log(sample_size)
    fitted.aic = -2 * fitted.loglik + 2 * p
    fitted.assignment, fitted.sizes, fitted.entropy = {}, {}, 0.0
    for k = 1, count do fitted.sizes[k] = 0 end
    for i, row in ipairs(fitted.records) do
        local chosen = maximum(row.r)
        fitted.assignment[i] = chosen
        fitted.sizes[chosen] = fitted.sizes[chosen] + 1
        fitted.entropy = fitted.entropy + entropy(row.r)
    end
    fitted.icl = fitted.bic + 2 * fitted.entropy
    fitted.settled_at = #fitted.trace - 1
    for t = #fitted.trace, 1, -1 do
        if math.abs(fitted.trace[t] - fitted.loglik) > settings.SETTLE_TOLERANCE[1] then break end
        fitted.settled_at = t - 1
    end
    fitted.largest_t, fitted.largest_value, fitted.violations = 1, -math.huge, {}
    for t = 2, #fitted.trace do
        local increase = fitted.trace[t] - fitted.trace[t - 1]
        if increase > fitted.largest_value then fitted.largest_t, fitted.largest_value = t - 1, increase end
        if fitted.trace[t] < fitted.trace[t - 1] - 0.000001 * math.abs(fitted.trace[t - 1]) then
            fitted.violations[#fitted.violations + 1] = t - 1
        end
    end
    return fitted
end
local function fit(sample, start, count, kind, type_index)
    return summarize(em.run(sample, start, kind, settings.ITERATIONS[1], settings.REGULARIZATION[1]),
        count, kind, type_index, #sample)
end
local function ranking(models, criterion)
    local ordered = {table.unpack(models)}
    table.sort(ordered, function(a, b)
        local first, second = report.scaled(a[criterion]), report.scaled(b[criterion])
        if first ~= second then return first < second end
        if a.p ~= b.p then return a.p < b.p end
        if a.k ~= b.k then return a.k < b.k end
        return a.type_index < b.type_index
    end)
    return ordered
end
local function filter(models, key, value)
    local result = {}
    for _, model in ipairs(models) do if model[key] == value then result[#result + 1] = model end end
    return result
end
local function contingency(left, right, rows, columns)
    local result = {}
    for a = 1, rows do
        result[a] = {}
        for b = 1, columns do result[a][b] = 0 end
    end
    for i, a in ipairs(left) do result[a][right[i]] = result[a][right[i]] + 1 end
    return result
end
local function choose2(value) return value * (value - 1) // 2 end
local function gcd(a, b)
    while b ~= 0 do a, b = b, a % b end
    return a
end
local function ari(left, right, rows, columns)
    local matrix = contingency(left, right, rows, columns)
    local shared, a, b = 0, 0, 0
    for _, row in ipairs(matrix) do
        local total = 0
        for _, count in ipairs(row) do shared, total = shared + choose2(count), total + count end
        a = a + choose2(total)
    end
    for column = 1, columns do
        local total = 0
        for row = 1, rows do total = total + matrix[row][column] end
        b = b + choose2(total)
    end
    local z = choose2(#left)
    local numerator, denominator = 2 * (z * shared - a * b), z * (a + b) - 2 * a * b
    if denominator == 0 then numerator, denominator = 1, 1
    else
        if denominator < 0 then numerator, denominator = -numerator, -denominator end
        local divisor = gcd(math.abs(numerator), denominator)
        numerator, denominator = numerator // divisor, denominator // divisor
    end
    return numerator .. "/" .. denominator .. " " .. dec(numerator / denominator)
end
local function partition_metrics(labels, count)
    local sizes, centers, occupied = {}, {}, {}
    local center = {0.0, 0.0}
    for _, point in ipairs(points) do center[1], center[2] = center[1] + point.x, center[2] + point.y end
    center[1], center[2] = center[1] / n, center[2] / n
    for k = 1, count do
        local sx, sy, size = 0.0, 0.0, 0
        for i, point in ipairs(points) do
            if labels[i] == k then sx, sy, size = sx + point.x, sy + point.y, size + 1 end
        end
        sizes[k] = size
        if size > 0 then centers[k], occupied[#occupied + 1] = {sx / size, sy / size}, k end
    end
    local result = {cluster = {}}
    if #occupied < 2 then return result end
    local silhouette, cluster_sums = 0.0, {}
    for k = 1, count do cluster_sums[k] = 0.0 end
    for i, point in ipairs(points) do
        local own, nearest = labels[i], math.huge
        local own_sum = 0.0
        for _, k in ipairs(occupied) do
            local total = 0.0
            for j, other in ipairs(points) do
                if labels[j] == k and i ~= j then total = total + kmeans.distance(xy(point), xy(other)) end
            end
            if k == own then own_sum = total else nearest = math.min(nearest, total / sizes[k]) end
        end
        local s = 0.0
        if sizes[own] > 1 then
            local a = own_sum / (sizes[own] - 1)
            s = (nearest - a) / math.max(a, nearest)
        end
        silhouette = silhouette + s
        cluster_sums[own] = cluster_sums[own] + s
    end
    result.silhouette = silhouette / n
    local between, within, scatter = 0.0, 0.0, {}
    for _, k in ipairs(occupied) do
        result.cluster[k] = cluster_sums[k] / sizes[k]
        between = between + sizes[k] * kmeans.distance2(centers[k], center)
        local total = 0.0
        for i, point in ipairs(points) do
            if labels[i] == k then total = total + kmeans.distance(xy(point), centers[k]) end
        end
        scatter[k] = total / sizes[k]
    end
    for i, point in ipairs(points) do within = within + kmeans.distance2(xy(point), centers[labels[i]]) end
    result.ch = (between / (#occupied - 1)) / (within / (n - #occupied))
    local total = 0.0
    for _, k in ipairs(occupied) do
        local worst = -math.huge
        for _, other in ipairs(occupied) do
            if other ~= k then worst = math.max(worst, (scatter[k] + scatter[other]) / kmeans.distance(centers[k], centers[other])) end
        end
        total = total + worst
    end
    result.db = total / #occupied
    return result
end
local models, means = {}, {}
for _, count in ipairs(settings.K) do
    means[count] = kmeans.run(points, initial[count].means, settings.KMEANS_MAX_ITERATIONS[1])
    for type_index, kind in ipairs(settings.TYPES) do
        models[#models + 1] = fit(points, initial[count], count, kind, type_index)
    end
end
local rankings, ranks = {}, {}
for _, criterion in ipairs({"bic", "aic", "icl"}) do
    rankings[criterion], ranks[criterion] = ranking(models, criterion), {}
    for i, model in ipairs(rankings[criterion]) do ranks[criterion][model] = i end
end
local selected = rankings.bic[1]
local selected_means = means[selected.k]
local model_blocks, trace, assignments = {}, {"K,type,iteration,loglik"}, {"id,component,max_responsibility,log_density,kmeans_cluster"}
for _, model in ipairs(models) do
    local block = {"model K=" .. model.k .. " type=" .. model.kind, "parameters " .. model.p,
        "loglik " .. dec(model.loglik), "bic " .. dec(model.bic), "aic " .. dec(model.aic),
        "icl " .. dec(model.icl), "mean_entropy " .. dec(model.entropy / n), "settled_at " .. model.settled_at,
        "largest_increase iteration " .. model.largest_t .. " value " .. dec(model.largest_value),
        "violations " .. #model.violations, "sizes " .. ints(model.sizes)}
    for k = 1, model.k do
        local geometry = gaussian.eigen(model.model.covariances[k])
        block[#block + 1] = "component " .. k .. " weight " .. dec(model.model.weights[k])
            .. " mean " .. values(model.model.means[k]) .. " cov " .. values(model.model.covariances[k])
            .. " axes " .. values(geometry.axes) .. " angle " .. dec(geometry.angle)
    end
    model_blocks[#model_blocks + 1] = block
    for i, loglik in ipairs(model.trace) do trace[#trace + 1] = model.k .. "," .. model.kind .. "," .. (i - 1) .. "," .. dec(loglik) end
end
for i, point in ipairs(points) do
    local _, max = maximum(selected.records[i].r)
    assignments[#assignments + 1] = point.id .. "," .. selected.assignment[i] .. "," .. dec(max) .. ","
        .. dec(selected.records[i].lp) .. "," .. selected_means.assignment[i]
end
local blocks = {}
local block = {"ranking by bic", "rank K type parameters loglik bic delta_bic aic aic_rank icl icl_rank"}
for i, model in ipairs(rankings.bic) do
    block[#block + 1] = i .. " " .. model.k .. " " .. model.kind .. " " .. model.p .. " " .. dec(model.loglik)
        .. " " .. dec(model.bic) .. " " .. dec((report.scaled(model.bic) - report.scaled(selected.bic)) / 10000)
        .. " " .. dec(model.aic) .. " " .. ranks.aic[model] .. " " .. dec(model.icl) .. " " .. ranks.icl[model]
end
for _, item in ipairs({{"selected", "bic"}, {"best_aic", "aic"}, {"best_icl", "icl"}}) do
    local best = rankings[item[2]][1]
    block[#block + 1] = item[1] .. " K=" .. best.k .. " type=" .. best.kind
end
blocks[#blocks + 1] = block
block = {"best K per type"}
for _, kind in ipairs(settings.TYPES) do
    local subset = filter(models, "kind", kind)
    block[#block + 1] = kind .. " bic " .. ranking(subset, "bic")[1].k .. " aic " .. ranking(subset, "aic")[1].k
        .. " icl " .. ranking(subset, "icl")[1].k
end
blocks[#blocks + 1] = block
local previous
for _, count in ipairs(settings.K) do
    local best = ranking(filter(models, "k", count), "bic")[1]
    local km = means[count]
    local gm_stats, km_stats = partition_metrics(best.assignment, count), partition_metrics(km.assignment, count)
    block = {"K=" .. count .. " type=" .. best.kind .. " bic " .. dec(best.bic),
        "  kmeans iterations " .. km.iterations .. " inertia " .. dec(km.inertia),
        "  ari " .. ari(best.assignment, km.assignment, count, count),
        "  silhouette gmm " .. report.optional(gm_stats.silhouette) .. " kmeans " .. report.optional(km_stats.silhouette),
        "  calinski_harabasz gmm " .. report.optional(gm_stats.ch) .. " kmeans " .. report.optional(km_stats.ch),
        "  davies_bouldin gmm " .. report.optional(gm_stats.db) .. " kmeans " .. report.optional(km_stats.db)}
    if previous then
        local matrix = contingency(previous.assignment, best.assignment, previous.k, count)
        local parents, shared = {}, {}
        for k = 1, count do
            local chosen, largest = "-", 0
            for a = 1, previous.k do
                if matrix[a][k] > largest then chosen, largest = a, matrix[a][k] end
            end
            parents[k], shared[k] = chosen, largest
        end
        block[#block + 1] = "  parents K=" .. previous.k .. " " .. ints(parents) .. " shared " .. ints(shared)
    end
    previous = best
    blocks[#blocks + 1] = block
end
block = {"violations"}
for _, model in ipairs(models) do
    for _, t in ipairs(model.violations) do
        block[#block + 1] = "K=" .. model.k .. " type=" .. model.kind .. " iteration " .. t
            .. " previous " .. dec(model.trace[t]) .. " current " .. dec(model.trace[t + 1])
    end
end
if #block == 1 then block[2] = "none" end
blocks[#blocks + 1] = block
local stats = partition_metrics(selected.assignment, selected.k)
block = {"selected components"}
for k = 1, selected.k do
    local mixture = selected.model
    local cov, mean = mixture.covariances[k], mixture.means[k]
    local geometry = gaussian.eigen(cov)
    local observed, expected = {}, {}
    for i = 1, #settings.GOF_EDGES + 1 do observed[i] = 0 end
    local soft, inside_one, inside_two = 0.0, 0, 0
    for i, point in ipairs(points) do
        soft = soft + selected.records[i].r[k]
        if selected.assignment[i] == k then
            local q = gaussian.mahalanobis(xy(point), mean, cov)
            if q <= 1 then inside_one = inside_one + 1 end
            if q <= 4 then inside_two = inside_two + 1 end
            local rho, bucket = math.sqrt(q), 1
            while bucket <= #settings.GOF_EDGES and rho >= settings.GOF_EDGES[bucket] do bucket = bucket + 1 end
            observed[bucket] = observed[bucket] + 1
        end
    end
    local left, chi = 0.0, 0.0
    for i = 1, #observed do
        local end_probability = 0.0
        if i <= #settings.GOF_EDGES then
            local right = settings.GOF_EDGES[i]
            end_probability = math.exp(-right * right / 2)
        end
        expected[i] = selected.sizes[k] * (math.exp(-left * left / 2) - end_probability)
        chi = chi + (observed[i] - expected[i]) * (observed[i] - expected[i]) / expected[i]
        left = settings.GOF_EDGES[i]
    end
    block[#block + 1] = "component " .. k .. " weight " .. dec(mixture.weights[k]) .. " size " .. selected.sizes[k]
        .. " soft_size " .. dec(soft) .. " mean " .. values(mean)
    block[#block + 1] = "  cov " .. values(cov) .. " corr " .. dec(geometry.correlation)
    block[#block + 1] = "  eigen " .. dec(geometry.leading) .. " " .. dec(geometry.trailing) .. " direction "
        .. values(geometry.direction) .. " angle " .. dec(geometry.angle)
    block[#block + 1] = "  axes_1sigma " .. values(geometry.axes) .. " axes_2sigma " .. values({2 * geometry.axes[1], 2 * geometry.axes[2]})
    block[#block + 1] = "  inside_1sigma " .. inside_one .. " inside_2sigma " .. inside_two .. " area_1sigma " .. dec(geometry.area)
    block[#block + 1] = "  silhouette " .. report.optional(stats.cluster[k])
    block[#block + 1] = "  gof observed " .. ints(observed) .. " expected " .. values(expected) .. " chi2 " .. dec(chi)
end
blocks[#blocks + 1] = block
block = {"overlap"}
for a = 1, selected.k - 1 do
    for b = a + 1, selected.k do
        local d, coefficient = gaussian.bhattacharyya(selected.model.means[a], selected.model.covariances[a], selected.model.means[b], selected.model.covariances[b])
        local shared = 0.0
        for _, row in ipairs(selected.records) do shared = shared + row.r[a] * row.r[b] end
        block[#block + 1] = a .. "-" .. b .. " bhattacharyya " .. dec(d) .. " coefficient " .. dec(coefficient) .. " shared " .. dec(shared)
    end
end
if #block == 1 then block[2] = "none" end
blocks[#blocks + 1] = block
local function cluster_statistics(clusters)
    local total, sizes = 0.0, {}
    for j = 1, #clusters do sizes[j] = 0 end
    for _, record in ipairs(selected.records) do
        local probability = {}
        for j, cluster in ipairs(clusters) do
            local sum = 0.0
            for _, k in ipairs(cluster) do sum = sum + record.r[k] end
            probability[j] = sum
        end
        total = total + entropy(probability)
        local winner = maximum(probability)
        sizes[winner] = sizes[winner] + 1
    end
    return total, sizes
end
local clusters = {}
for k = 1, selected.k do clusters[k] = {k} end
local start_entropy = cluster_statistics(clusters)
block = {"merging", "start entropy " .. dec(start_entropy)}
local step = 0
while #clusters > 1 do
    local best, first, second, best_entropy, best_sizes
    for a = 1, #clusters - 1 do
        for b = a + 1, #clusters do
            local proposed = {}
            for j, cluster in ipairs(clusters) do
                if j ~= b then
                    local item = {table.unpack(cluster)}
                    if j == a then
                        for _, k in ipairs(clusters[b]) do item[#item + 1] = k end
                        table.sort(item)
                    end
                    proposed[#proposed + 1] = item
                end
            end
            local total, sizes = cluster_statistics(proposed)
            if not best or report.scaled(total) < report.scaled(best_entropy) then
                best, first, second, best_entropy, best_sizes = proposed, a, b, total, sizes
            end
        end
    end
    step = step + 1
    block[#block + 1] = "step " .. step .. " merge " .. table.concat(clusters[first], "+") .. " "
        .. table.concat(clusters[second], "+") .. " entropy " .. dec(best_entropy) .. " sizes " .. ints(best_sizes)
    clusters = best
end
blocks[#blocks + 1] = block
local matrix = contingency(selected.assignment, selected_means.assignment, selected.k, selected.k)
local best_permutation, agreement, used, permutation = {}, -1, {}, {}
local function match_next()
    if #permutation == selected.k then
        local total = 0
        for j, component in ipairs(permutation) do total = total + matrix[component][j] end
        if total > agreement then best_permutation, agreement = {table.unpack(permutation)}, total end
        return
    end
    for k = 1, selected.k do
        if not used[k] then
            used[k], permutation[#permutation + 1] = true, k
            match_next()
            used[k], permutation[#permutation] = nil, nil
        end
    end
end
match_next()
block = {"kmeans K=" .. selected.k, "iterations " .. selected_means.iterations, "inertia " .. dec(selected_means.inertia), "sizes " .. ints(selected_means.sizes)}
for k, center in ipairs(selected_means.centers) do block[#block + 1] = "center " .. k .. " " .. values(center) end
block[#block + 1] = "contingency"
for _, row in ipairs(matrix) do block[#block + 1] = ints(row) end
block[#block + 1] = "ari " .. ari(selected.assignment, selected_means.assignment, selected.k, selected.k)
block[#block + 1] = "matching " .. ints(best_permutation)
block[#block + 1] = "agreement " .. agreement .. "/" .. n .. " " .. dec(agreement / n)
local disagreements = 0
for i, point in ipairs(points) do
    local cluster = selected_means.assignment[i]
    if best_permutation[cluster] ~= selected.assignment[i] then
        disagreements = disagreements + 1
        local _, max = maximum(selected.records[i].r)
        block[#block + 1] = "disagree " .. point.id .. " gmm " .. selected.assignment[i] .. " kmeans " .. cluster .. " max " .. dec(max)
    end
end
block[#block + 1] = "disagreements " .. disagreements
blocks[#blocks + 1] = block
local start = {weights = {}, means = selected_means.centers, covariances = {}}
for k, center in ipairs(start.means) do
    local a, b, c = 0.0, 0.0, 0.0
    local size = selected_means.sizes[k]
    for i, point in ipairs(points) do
        if selected_means.assignment[i] == k then
            local dx, dy = point.x - center[1], point.y - center[2]
            a, b, c = a + dx * dx, b + dx * dy, c + dy * dy
        end
    end
    start.weights[k] = size / n
    start.covariances[k] = {a / size + settings.REGULARIZATION[1], b / size, c / size + settings.REGULARIZATION[1]}
end
local refit = fit(points, start, selected.k, selected.kind, selected.type_index)
blocks[#blocks + 1] = {"refit_from_kmeans K=" .. selected.k .. " type=" .. selected.kind,
    "loglik " .. dec(refit.loglik) .. " bic " .. dec(refit.bic) .. " settled_at " .. refit.settled_at,
    "sizes " .. ints(refit.sizes), "ari_vs_selected " .. ari(selected.assignment, refit.assignment, selected.k, selected.k)}
block = {"cross_validation K=" .. selected.k .. " type=" .. selected.kind .. " folds " .. settings.CV_FOLDS[1]}
local mean_test = 0.0
for fold = 1, settings.CV_FOLDS[1] do
    local training, testing = {}, {}
    for i, point in ipairs(points) do
        local target = (i - 1) % settings.CV_FOLDS[1] == fold - 1 and testing or training
        target[#target + 1] = point
    end
    local trained = em.run(training, initial[selected.k], selected.kind, settings.ITERATIONS[1], settings.REGULARIZATION[1])
    local _, test_total = em.expectation(testing, trained.model)
    local test_loglik = test_total / #testing
    mean_test = mean_test + test_loglik
    block[#block + 1] = "fold " .. fold .. " train " .. #training .. " test " .. #testing .. " train_loglik "
        .. dec(trained.loglik / #training) .. " test_loglik " .. dec(test_loglik)
end
block[#block + 1] = "mean_test_loglik " .. dec(mean_test / settings.CV_FOLDS[1])
blocks[#blocks + 1] = block
local uncertain, outliers = {}, {}
for i, row in ipairs(selected.records) do
    local _, max = maximum(row.r)
    if max < settings.UNCERTAIN_THRESHOLD[1] then uncertain[#uncertain + 1] = i end
    if row.lp < settings.LOW_DENSITY_THRESHOLD[1] then outliers[#outliers + 1] = i end
end
local function order_points(indices, score)
    table.sort(indices, function(a, b)
        local first, second = report.scaled(score(a)), report.scaled(score(b))
        return first < second or first == second and a < b
    end)
end
order_points(uncertain, function(i) local _, max = maximum(selected.records[i].r); return max end)
order_points(outliers, function(i) return selected.records[i].lp end)
block = {"uncertain threshold " .. dec(settings.UNCERTAIN_THRESHOLD[1])}
for _, i in ipairs(uncertain) do
    local row = selected.records[i]
    local _, max = maximum(row.r)
    block[#block + 1] = points[i].id .. " component " .. selected.assignment[i] .. " max " .. dec(max) .. " responsibilities " .. values(row.r)
end
block[#block + 1] = "count " .. #uncertain
blocks[#blocks + 1] = block
block = {"outliers threshold " .. dec(settings.LOW_DENSITY_THRESHOLD[1])}
for _, i in ipairs(outliers) do
    local k = selected.assignment[i]
    local q = gaussian.mahalanobis(xy(points[i]), selected.model.means[k], selected.model.covariances[k])
    block[#block + 1] = points[i].id .. " component " .. k .. " log_density " .. dec(selected.records[i].lp) .. " q " .. dec(q)
end
block[#block + 1] = "count " .. #outliers
blocks[#blocks + 1] = block
local xmin, xmax = table.unpack(settings.MAP_X)
local ymin, ymax = table.unpack(settings.MAP_Y)
local width, height = table.unpack(settings.MAP_SIZE)
local dx, dy = (xmax - xmin) / width, (ymax - ymin) / height
local coordinates, measures, density, regions, uncertainty, point_map = {}, {}, {}, {}, {}, {}
local fmax, mass = 0.0, 0.0
for row = 1, height do
    coordinates[row], measures[row] = {}, {}
    for column = 1, width do
        local point = {xmin + (column - 0.5) * dx, ymax - (row - 0.5) * dy}
        coordinates[row][column] = point
        local scores, f, max_score = {}, 0.0, -math.huge
        for k = 1, selected.k do
            scores[k] = gaussian.log_density(point, selected.model.weights[k], selected.model.means[k], selected.model.covariances[k])
            f = f + math.exp(scores[k])
            max_score = math.max(max_score, scores[k])
        end
        local r, normalizer = {}, 0.0
        for k, score in ipairs(scores) do r[k] = math.exp(score - max_score); normalizer = normalizer + r[k] end
        for k = 1, selected.k do r[k] = r[k] / normalizer end
        local winner = maximum(scores)
        measures[row][column] = {f = f, r = r, winner = winner}
        fmax, mass = math.max(fmax, f), mass + f
    end
end
local function cell(point)
    local column, row = math.floor((point[1] - xmin) / dx) + 1, math.floor((ymax - point[2]) / dy) + 1
    if column >= 1 and column <= width and row >= 1 and row <= height then return row, column end
end
local level_counts = {}
for level = 1, 10 do level_counts[level] = 0 end
for row = 1, height do
    density[row], regions[row], uncertainty[row], point_map[row] = {}, {}, {}, {}
    for column = 1, width do
        local measure = measures[row][column]
        local level = math.min(9, math.floor(10 * measure.f / fmax))
        level_counts[level + 1] = level_counts[level + 1] + 1
        density[row][column] = report.levels:sub(level + 1, level + 1)
        regions[row][column] = tostring(measure.winner)
        local uncertainty_level = 0
        if selected.k >= 2 then uncertainty_level = math.max(0, math.min(9, math.floor(10 * entropy(measure.r) / math.log(selected.k)))) end
        uncertainty[row][column] = report.levels:sub(uncertainty_level + 1, uncertainty_level + 1)
        local contour = false
        for k = 1, selected.k do
            local mean, cov = selected.model.means[k], selected.model.covariances[k]
            if gaussian.mahalanobis(coordinates[row][column], mean, cov) <= 4 then
                for _, offset in ipairs({{-1, 0}, {1, 0}, {0, -1}, {0, 1}}) do
                    local r, c = row + offset[1], column + offset[2]
                    if r >= 1 and r <= height and c >= 1 and c <= width
                        and gaussian.mahalanobis(coordinates[r][c], mean, cov) > 4 then contour = true; break end
                end
            end
            if contour then break end
        end
        point_map[row][column] = contour and "." or " "
    end
end
for k, mean in ipairs(selected.model.means) do
    local row, column = cell(mean)
    if row then density[row][column] = tostring(k) end
end
local bins, outside = {}, 0
for i, point in ipairs(points) do
    local row, column = cell(xy(point))
    if row then
        local index = (row - 1) * width + column
        local component = selected.assignment[i]
        if not bins[index] then bins[index] = component
        elseif bins[index] ~= component then bins[index] = 0 end
    else outside = outside + 1 end
end
for row = 1, height do
    for column = 1, width do
        local bin = bins[(row - 1) * width + column]
        if bin then point_map[row][column] = bin == 0 and "*" or tostring(bin) end
    end
end
local map_lines = {"density K=" .. selected.k .. " type=" .. selected.kind,
    "x " .. dec(xmin) .. " " .. dec(xmax) .. " y " .. dec(ymin) .. " " .. dec(ymax) .. " grid " .. width .. "x" .. height,
    "max_density " .. dec(fmax, 6) .. " mass_in_map " .. dec(mass * dx * dy)}
local function append(rows)
    for _, line in ipairs(rows) do map_lines[#map_lines + 1] = line end
end
append(report.framed(density))
for level = 0, 9 do
    map_lines[#map_lines + 1] = "level " .. level .. " \"" .. report.levels:sub(level + 1, level + 1)
        .. "\" from " .. dec(level * fmax / 10, 6) .. " cells " .. level_counts[level + 1]
end
append({"", "regions"})
append(report.framed(regions))
append({"", "uncertainty"})
append(report.framed(uncertainty))
append({"", "points"})
append(report.framed(point_map))
map_lines[#map_lines + 1] = "outside " .. outside
report.blocks("models.txt", model_blocks)
report.write("loglik_trace.csv", trace)
report.write("assignments.csv", assignments)
report.blocks("selection.txt", blocks)
report.write("density_map.txt", map_lines)
