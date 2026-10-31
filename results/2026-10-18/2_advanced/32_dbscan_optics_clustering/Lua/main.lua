local dataset = require("dataset")
local grid_index = require("grid_index")
local dbscan = require("dbscan")
local optics = require("optics")
local report = require("report")
local INF, distance = optics.INF, grid_index.distance
local points, params = dataset.read()
local n, m = #points, params.min_pts
local function line(...)
    return table.concat({...}, " ")
end
local function append(target, values)
    for _, value in ipairs(values) do
        target[#target + 1] = value
    end
end
local function indices(count)
    local result = {}
    for i = 1, count do
        result[i] = i
    end
    return result
end
local function filled(count, value)
    local result = {}
    for i = 1, count do
        result[i] = value
    end
    return result
end
local function sorted_keys(values)
    local keys = {}
    for key in pairs(values) do
        keys[#keys + 1] = key
    end
    table.sort(keys)
    return keys
end
local function label_char(label)
    if label < 0 then
        return "."
    end
    local letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
    return label < 52 and letters:sub(label + 1, label + 1) or "#"
end
local function value_text(value)
    return value == INF and "-" or tostring(value)
end
local function root(value)
    return value == INF and "-" or report.root(value)
end
local function optional(value)
    return value == nil and "-" or tostring(value)
end
local function check(value)
    return value and "ok" or "mismatch"
end
local function condition(value)
    return value and "ok" or "fail"
end
local function integer_root(value)
    local low, high = 0, value + 1
    while high - low > 1 do
        local mid = (low + high) // 2
        if mid <= value // mid then
            low = mid
        else
            high = mid
        end
    end
    return low
end
local function suggested(value)
    local radius = integer_root(value)
    if radius * radius < value then
        radius = radius + 1
    end
    return math.max(radius, 1)
end
local neighbor_rows = {}
for i, point in ipairs(points) do
    local values = {}
    for j, other in ipairs(points) do
        if i ~= j then
            values[#values + 1] = distance(point, other)
        end
    end
    table.sort(values)
    neighbor_rows[i] = values
end
local function curve_for(rank)
    local curve = {order = indices(n), values = {}}
    table.sort(curve.order, function(a, b)
        local da, db = neighbor_rows[a][rank], neighbor_rows[b][rank]
        return da > db or da == db and a < b
    end)
    for i, point in ipairs(curve.order) do
        curve.values[i] = neighbor_rows[point][rank]
    end
    local first, last = curve.values[1], curve.values[n]
    curve.knee, curve.cross = 1, -1
    for i, value in ipairs(curve.values) do
        local cross = math.abs((n - 1) * (value - first) - (last - first) * (i - 1))
        if cross > curve.cross then
            curve.knee, curve.cross = i, cross
        end
    end
    curve.eps = suggested(curve.values[curve.knee])
    return curve
end
local curves = {}
for j = 1, 2 * m do
    curves[j] = curve_for(j)
end
local curve, kdist = curves[m - 1], {}
for i = 1, n do
    kdist[i] = neighbor_rows[i][m - 1]
end
local radius_set = {[curve.eps] = true, [params.max_eps] = true}
for _, radius in ipairs(params.eps) do
    radius_set[radius] = true
end
local radii, grids, neighborhoods = sorted_keys(radius_set), {}, {}
for _, radius in ipairs(radii) do
    local index = grid_index.new(points, radius)
    local summary = {radius = radius, cells = #index.ordered_cells, busiest = index:busiest(), candidates = 0, neighbors = {}, occupancy = {}, consistent = true}
    local brute, total, brute_total = grid_index.brute_counts(points, radius), 0, 0
    for i = 1, n do
        local neighbors, candidates = index:neighborhood(i)
        summary.neighbors[i], summary.candidates = neighbors, summary.candidates + candidates
        total, brute_total = total + #neighbors, brute_total + brute[i]
        if #neighbors ~= brute[i] then
            summary.consistent = false
        end
    end
    for _, cell in ipairs(index.ordered_cells) do
        local size = #cell.members
        summary.occupancy[size] = (summary.occupancy[size] or 0) + 1
    end
    summary.pairs, summary.brute_pairs = (total - n) // 2, (brute_total - n) // 2
    grids[#grids + 1], neighborhoods[radius] = summary, summary.neighbors
end
local settings, db_settings, extracted_settings = {}, {}, {}
local function setting(name, kind, radius, labels, core)
    local result = {name = name, kind = kind, radius = radius, labels = labels, core = core, count = 0, noise = 0, core_count = 0, members = {}}
    for i, label in ipairs(labels) do
        if label < 0 then
            result.noise = result.noise + 1
        else
            result.count = math.max(result.count, label + 1)
            result.members[label + 1] = result.members[label + 1] or {}
            local members = result.members[label + 1]
            members[#members + 1] = i
            if core[i] then
                result.core_count = result.core_count + 1
            end
        end
    end
    result.border = n - result.noise - result.core_count
    return result
end
local function add_db(name, radius)
    local labels, core = dbscan.cluster(neighborhoods[radius], m)
    local result = setting(name, "dbscan", radius, labels, core)
    settings[#settings + 1], db_settings[#db_settings + 1] = result, result
    return result
end
for _, radius in ipairs(params.eps) do
    add_db("db" .. radius, radius)
end
local knee = add_db("knee" .. curve.eps, curve.eps)
local core = optics.core_distances(points, neighborhoods[params.max_eps], m)
local ordering, reach, predecessor = optics.order(points, neighborhoods[params.max_eps], core)
local function extract(radius)
    local labels, cores, cluster, limit = filled(n, -1), {}, -1, radius * radius
    for i = 1, n do
        cores[i] = core[i] <= limit
    end
    for _, i in ipairs(ordering) do
        if reach[i] > limit then
            if core[i] <= limit then
                cluster = cluster + 1
                labels[i] = cluster
            end
        else
            labels[i] = cluster
        end
    end
    return labels, cores
end
for _, radius in ipairs(params.extract) do
    local labels, cores = extract(radius)
    local result = setting("op" .. radius, "extract", radius, labels, cores)
    settings[#settings + 1], extracted_settings[#extracted_settings + 1] = result, result
end
local positions = {}
for i, point in ipairs(ordering) do
    positions[i] = reach[point]
end
positions[n + 1] = INF
local alpha, beta = (params.v - params.u) * (params.v - params.u), params.v * params.v
local function xle(a, b)
    if b == INF then
        return true
    end
    if a == INF then
        return false
    end
    return beta * a <= alpha * b
end
local steep_up, steep_down, up, down = {}, {}, {}, {}
for i = 1, n do
    local a, b = positions[i], positions[i + 1]
    steep_up[i] = (a ~= INF or b ~= INF) and xle(a, b)
    steep_down[i] = (a ~= INF or b ~= INF) and xle(b, a)
    up[i], down[i] = a < b, a > b
end
local function region_end(start, steep, reverse)
    local last, flat = start, 0
    for i = start, n do
        if steep[i] then
            last, flat = i, 0
        elseif reverse[i] then
            break
        else
            flat = flat + 1
            if flat > m then
                break
            end
        end
    end
    return last
end
local xi = {areas = {}, clusters = {}, labels = filled(n, -1)}
local down_areas, index, mib = {}, 1, 0
for start = 1, n do
    if start >= index and (steep_up[start] or steep_down[start]) then
        for i = index, start do
            mib = math.max(mib, positions[i])
        end
        local retained = {}
        if mib ~= INF then
            for _, area in ipairs(down_areas) do
                if xle(mib, positions[area.start]) then
                    area.high = math.max(area.high, mib)
                    retained[#retained + 1] = area
                end
            end
        end
        down_areas = retained
        if steep_down[start] then
            local last = region_end(start, steep_down, up)
            xi.areas[#xi.areas + 1] = {"down", start, last}
            down_areas[#down_areas + 1] = {start = start, finish = last, high = 0}
            index, mib = last + 1, positions[last + 1]
        else
            local last = region_end(start, steep_up, down)
            xi.areas[#xi.areas + 1] = {"up", start, last}
            index, mib = last + 1, positions[last + 1]
            local candidates = {}
            for _, area in ipairs(down_areas) do
                local first, finish = area.start, last
                if xle(area.high, positions[finish + 1]) then
                    local top = positions[area.start]
                    if xle(positions[finish + 1], top) then
                        while first < area.finish and positions[first + 1] > positions[finish + 1] do
                            first = first + 1
                        end
                    elseif xle(top, positions[finish + 1]) then
                        while finish > start and positions[finish - 1] > top do
                            finish = finish - 1
                        end
                    end
                    if finish - first + 1 >= params.min_size and first <= area.finish and finish >= start then
                        candidates[#candidates + 1] = {start = first, finish = finish}
                    end
                end
            end
            for i = #candidates, 1, -1 do
                xi.clusters[#xi.clusters + 1] = candidates[i]
            end
        end
    end
end
local next_label = 0
for j, cluster in ipairs(xi.clusters) do
    local clear = true
    for i = cluster.start, cluster.finish do
        if xi.labels[i] ~= -1 then
            clear = false
        end
    end
    if clear then
        cluster.label = next_label
        for i = cluster.start, cluster.finish do
            xi.labels[i] = next_label
        end
        next_label = next_label + 1
    end
    cluster.valley = INF
    for i = cluster.start + 1, cluster.finish do
        cluster.valley = math.min(cluster.valley, positions[i])
    end
    cluster.left, cluster.right = positions[cluster.start], positions[cluster.finish + 1]
    cluster.size = cluster.finish - cluster.start + 1
end
for j, cluster in ipairs(xi.clusters) do
    local parent
    for i, other in ipairs(xi.clusters) do
        if i ~= j and other.start <= cluster.start and other.finish >= cluster.finish and (other.size > cluster.size or other.size == cluster.size and i > j) then
            if not parent or other.size < xi.clusters[parent].size then
                parent = i
            end
        end
    end
    cluster.parent = parent and parent - 1 or nil
end
local xi_labels, xi_core = {}, {}
for i, point in ipairs(ordering) do
    xi_labels[point] = xi.labels[i]
end
for i = 1, n do
    xi_core[i] = core[i] ~= INF
end
local xi_setting = setting("xi", "xi", params.max_eps, xi_labels, xi_core)
settings[#settings + 1] = xi_setting
local names = {}
for i, result in ipairs(settings) do
    names[i] = result.name
end
local labels_output = {"id," .. table.concat(names, ",")}
for i, point in ipairs(points) do
    local values = {point.id}
    for _, result in ipairs(settings) do
        values[#values + 1] = result.labels[i]
    end
    labels_output[#labels_output + 1] = table.concat(values, ",")
end
local optics_output = {"order,id,core_sq,reach_sq,reach,predecessor"}
for i, point in ipairs(ordering) do
    optics_output[#optics_output + 1] = table.concat({i, points[point].id, value_text(core[point]), value_text(reach[point]), root(reach[point]), predecessor[point] and points[predecessor[point]].id or "-"}, ",")
end
local kdist_output = {line("k_distance k", m - 1, "points", n), "rank id kdist_sq kdist"}
for i, point in ipairs(curve.order) do
    kdist_output[#kdist_output + 1] = line(i, points[point].id, curve.values[i], root(curve.values[i]))
end
append(kdist_output, {"", line("knee rank", curve.knee, "id", points[curve.order[curve.knee]].id, "kdist_sq", curve.values[curve.knee], "kdist", root(curve.values[curve.knee]), "cross", curve.cross), line("suggested_eps", curve.eps), "", "knee_table"})
for j, row in ipairs(curves) do
    kdist_output[#kdist_output + 1] = line("k", j, "rank", row.knee, "id", points[row.order[row.knee]].id, "kdist_sq", row.values[row.knee], "eps", row.eps)
end
append(kdist_output, {"", "core_check"})
for _, result in ipairs(db_settings) do
    local kd_count, grid_count = 0, 0
    for i = 1, n do
        if kdist[i] <= result.radius * result.radius then
            kd_count = kd_count + 1
        end
        if result.core[i] then
            grid_count = grid_count + 1
        end
    end
    kdist_output[#kdist_output + 1] = line("eps", result.radius, "core", kd_count, "non_core", n - kd_count, "grid_core", grid_count, check(kd_count == grid_count))
end
local defined, consistent = 0, true
for i = 1, n do
    if core[i] ~= INF then
        defined = defined + 1
        if core[i] ~= kdist[i] then
            consistent = false
        end
    end
end
kdist_output[#kdist_output + 1] = line("optics max_eps", params.max_eps, "core", defined, check(consistent))
local function hull_half(ordered)
    local chain = {}
    for _, i in ipairs(ordered) do
        while #chain >= 2 do
            local o, a, b = points[chain[#chain - 1]], points[chain[#chain]], points[i]
            local turn = (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)
            if turn > 0 then
                break
            end
            chain[#chain] = nil
        end
        chain[#chain + 1] = i
    end
    return chain
end
local function convex_hull(members)
    local ordered = {}
    append(ordered, members)
    table.sort(ordered, function(i, j)
        local a, b = points[i], points[j]
        return a.x < b.x or a.x == b.x and a.y < b.y
    end)
    if #ordered <= 2 then
        return ordered
    end
    local lower, reverse = hull_half(ordered), {}
    for i = #ordered, 1, -1 do
        reverse[#reverse + 1] = ordered[i]
    end
    local upper = hull_half(reverse)
    lower[#lower], upper[#upper] = nil, nil
    append(lower, upper)
    return lower
end
local function cluster_lines(result, label)
    local members = result.members[label + 1]
    local size, core_count, sx, sy = #members, 0, 0, 0
    local xmin, ymin, xmax, ymax = 10001, 10001, 0, 0
    for _, i in ipairs(members) do
        local p = points[i]
        if result.core[i] then
            core_count = core_count + 1
        end
        sx, sy = sx + p.x, sy + p.y
        xmin, xmax, ymin, ymax = math.min(xmin, p.x), math.max(xmax, p.x), math.min(ymin, p.y), math.max(ymax, p.y)
    end
    local medoid, best
    for _, i in ipairs(members) do
        local dx, dy = size * points[i].x - sx, size * points[i].y - sy
        local value = dx * dx + dy * dy
        if not best or value < best then
            medoid, best = i, value
        end
    end
    local hull, area, doubled, diameter = convex_hull(members), (xmax - xmin + 1) * (ymax - ymin + 1), 0, 0
    for j, i in ipairs(hull) do
        local a, b = points[i], points[hull[j % #hull + 1]]
        doubled = doubled + a.x * b.y - b.x * a.y
        for _, other in ipairs(hull) do
            diameter = math.max(diameter, distance(a, points[other]))
        end
    end
    doubled = math.abs(doubled)
    return {
        line("cluster", label, label_char(label), "size", size, "core", core_count, "border", size - core_count, "centroid", report.fraction(sx, size), report.fraction(sy, size), "medoid", points[medoid].id),
        line("  bbox", xmin, ymin, xmax, ymax, "area", area, "density", report.fraction(size, area)),
        line("  hull", #hull, "hull_area", (doubled // 2) .. "." .. (doubled % 2 == 0 and "0" or "5"), "diameter_sq", diameter, "diameter", root(diameter))
    }
end
local parts = {{line("points", n, "min_pts", m), "settings " .. table.concat(names, " ")}}
local grid_lines = {"grid"}
for _, summary in ipairs(grids) do
    local cell, occupancy = summary.busiest, {}
    for _, count in ipairs(sorted_keys(summary.occupancy)) do
        occupancy[#occupancy + 1] = count .. ":" .. summary.occupancy[count]
    end
    append(grid_lines, {line("eps", summary.radius, "cells", summary.cells, "busiest", cell.x, cell.y, #cell.members, "candidates", summary.candidates, "pairs", summary.pairs, "brute_pairs", summary.brute_pairs, check(summary.consistent)), "  occupancy " .. table.concat(occupancy, " ")})
end
parts[#parts + 1] = grid_lines
for _, result in ipairs(settings) do
    local lines = {line("setting", result.name, "eps", result.radius, "clusters", result.count, "noise", result.noise, "core", result.core_count, "border", result.border)}
    for label = 0, result.count - 1 do
        append(lines, cluster_lines(result, label))
    end
    if result.kind == "dbscan" then
        local linked, supported, separated, isolated, ambiguous = true, true, true, 0, {}
        for i, neighbors in ipairs(neighborhoods[result.radius]) do
            local label, core_labels = result.labels[i], {}
            for _, other in ipairs(neighbors) do
                if result.core[other] then
                    core_labels[result.labels[other]] = true
                end
            end
            if result.core[i] then
                for other in pairs(core_labels) do
                    if other ~= label then
                        linked = false
                    end
                end
            elseif label >= 0 then
                if not core_labels[label] then
                    supported = false
                end
                core_labels[label] = nil
                local others = sorted_keys(core_labels)
                if #others > 0 then
                    ambiguous[#ambiguous + 1] = line(" ", points[i].id, "cluster", label, "also", table.concat(others, " "))
                end
            else
                if next(core_labels) then
                    separated = false
                end
                if #neighbors == 1 then
                    isolated = isolated + 1
                end
            end
        end
        append(lines, {line("check", condition(linked), condition(supported), condition(separated)), line("isolated", isolated), line("ambiguous", #ambiguous)})
        append(lines, ambiguous)
    end
    parts[#parts + 1] = lines
end
local hierarchy, ordered_db = {"hierarchy"}, {}
append(ordered_db, db_settings)
local setting_position = {}
for i, result in ipairs(settings) do
    setting_position[result] = i
end
table.sort(ordered_db, function(a, b)
    return a.radius < b.radius or a.radius == b.radius and setting_position[a] < setting_position[b]
end)
for i = 1, #ordered_db - 1 do
    local a, b, sources = ordered_db[i], ordered_db[i + 1], {}
    for label = 1, b.count do
        sources[label] = {}
    end
    for j, members in ipairs(a.members) do
        for _, p in ipairs(members) do
            if a.core[p] then
                local destination = sources[b.labels[p] + 1]
                destination[#destination + 1] = j - 1
                break
            end
        end
    end
    hierarchy[#hierarchy + 1] = a.name .. " -> " .. b.name
    for j, values in ipairs(sources) do
        hierarchy[#hierarchy + 1] = line(" ", j - 1, "<-", #values > 0 and table.concat(values, " ") or "-")
    end
end
parts[#parts + 1] = hierarchy
local comparisons = {"optics_vs_dbscan"}
for _, a in ipairs(extracted_settings) do
    local b
    for _, candidate in ipairs(db_settings) do
        if candidate.radius == a.radius then
            b = candidate
            break
        end
    end
    if b then
        local mapping, reverse, same, border_as_noise = {}, {}, true, 0
        for i = 1, n do
            local x, y = a.labels[i], b.labels[i]
            if a.core[i] then
                if mapping[x] ~= nil and mapping[x] ~= y or reverse[y] ~= nil and reverse[y] ~= x then
                    same = false
                end
                mapping[x], reverse[y] = y, x
            end
            if x == -1 and y >= 0 then
                border_as_noise = border_as_noise + 1
            end
        end
        local moved = "-"
        if same then
            moved = 0
            for i = 1, n do
                if a.labels[i] >= 0 and mapping[a.labels[i]] ~= b.labels[i] then
                    moved = moved + 1
                end
            end
        end
        comparisons[#comparisons + 1] = line(a.name, b.name, "core_partition", same and "same" or "different", "border_as_noise", border_as_noise, "moved", moved)
    end
end
parts[#parts + 1] = comparisons
local components = {}
for _, p in ipairs(ordering) do
    if reach[p] == INF then
        components[#components + 1] = 0
    end
    components[#components] = components[#components] + 1
end
local singleton, largest = 0, 0
for _, size in ipairs(components) do
    if size == 1 then
        singleton = singleton + 1
    end
    largest = math.max(largest, size)
end
parts[#parts + 1] = {line("optics max_eps", params.max_eps, "core", defined, "components", #components, "singletons", singleton, "largest", largest)}
local sweep, counts, stable = {line("sweep max_eps", params.max_eps), "eps clusters noise largest"}, {}, nil
for radius = 1, params.max_eps do
    local labels, cores = extract(radius)
    local result = setting("", "", radius, labels, cores)
    counts[radius], largest = result.count, 0
    for _, members in ipairs(result.members) do
        largest = math.max(largest, #members)
    end
    sweep[#sweep + 1] = line(radius, result.count, result.noise, largest)
end
local run_start = 1
for radius = 1, params.max_eps do
    if radius == params.max_eps or counts[radius + 1] ~= counts[run_start] then
        local length = radius - run_start + 1
        if counts[run_start] >= 2 and (not stable or length > stable.length) then
            stable = {count = counts[run_start], first = run_start, last = radius, length = length}
        end
        run_start = radius + 1
    end
end
sweep[#sweep + 1] = stable and line("stable clusters", stable.count, "eps", stable.first, stable.last, "length", stable.length) or "stable -"
parts[#parts + 1] = sweep
local xi_lines = {line("xi", params.u .. "/" .. params.v, "min_size", params.min_size, "steep_areas", #xi.areas)}
for _, area in ipairs(xi.areas) do
    xi_lines[#xi_lines + 1] = line(table.unpack(area))
end
xi_lines[#xi_lines + 1] = line("xi_clusters", #xi.clusters)
for j, cluster in ipairs(xi.clusters) do
    xi_lines[#xi_lines + 1] = line(j - 1, "start", cluster.start, "end", cluster.finish, "size", cluster.size, "label", optional(cluster.label), "parent", optional(cluster.parent), "walls", root(cluster.left), root(cluster.right), "valley", root(cluster.valley))
end
parts[#parts + 1] = xi_lines
local outliers = {}
for i, label in ipairs(knee.labels) do
    if label < 0 then
        local nearest, best
        for j = 1, n do
            if knee.core[j] then
                local d = distance(points[i], points[j])
                if not best or d < best then
                    nearest, best = j, d
                end
            end
        end
        outliers[#outliers + 1] = {point = i, nearest = nearest, distance = best}
    end
end
table.sort(outliers, function(a, b)
    return a.distance > b.distance or a.distance == b.distance and a.point < b.point
end)
local outlier_lines = {line("outliers", knee.name, "count", #outliers)}
for _, row in ipairs(outliers) do
    outlier_lines[#outlier_lines + 1] = line(points[row.point].id, "nearest_core", points[row.nearest].id, "cluster", knee.labels[row.nearest], "dist_sq", row.distance, "dist", root(row.distance))
end
parts[#parts + 1] = outlier_lines
local gaps = {"gaps " .. knee.name}
for a = 1, knee.count do
    for b = a + 1, knee.count do
        local best, first, second
        for _, i in ipairs(knee.members[a]) do
            for _, j in ipairs(knee.members[b]) do
                local d = distance(points[i], points[j])
                if not best or d < best then
                    best, first, second = d, i, j
                end
            end
        end
        gaps[#gaps + 1] = line(a - 1, b - 1, "dist_sq", best, "dist", root(best), "between", points[first].id, points[second].id)
    end
end
parts[#parts + 1] = gaps
local contingency = {}
for row = 1, knee.count + 1 do
    contingency[row] = filled(xi_setting.count + 1, 0)
end
for i = 1, n do
    local row, column = knee.labels[i] + 2, xi_setting.labels[i] + 2
    contingency[row][column] = contingency[row][column] + 1
end
local columns = {}
for j = -1, xi_setting.count - 1 do
    columns[#columns + 1] = j
end
local contingency_lines = {line("contingency", knee.name, "xi"), "columns " .. table.concat(columns, " ")}
for row = 1, knee.count + 1 do
    contingency_lines[#contingency_lines + 1] = line(row - 2, table.concat(contingency[row], " "))
end
for column = 1, xi_setting.count do
    local best, matched = -1, 1
    for row = 1, knee.count do
        if contingency[row + 1][column + 1] > best then
            best, matched = contingency[row + 1][column + 1], row
        end
    end
    contingency_lines[#contingency_lines + 1] = line("match", column - 1, matched - 1, "shared", best, "jaccard", report.fraction(best, #knee.members[matched] + #xi_setting.members[column] - best))
end
parts[#parts + 1] = contingency_lines
local function pair_count(count)
    return count * (count - 1) // 2
end
local function pair_sum(counts)
    local result = 0
    for _, count in pairs(counts) do
        result = result + pair_count(count)
    end
    return result
end
local ari_lines = {"ari"}
for a = 1, #settings do
    for b = a + 1, #settings do
        local first, second, pairs = {}, {}, {}
        for i = 1, n do
            local x, y = settings[a].labels[i], settings[b].labels[i]
            local key = x .. "," .. y
            first[x], second[y], pairs[key] = (first[x] or 0) + 1, (second[y] or 0) + 1, (pairs[key] or 0) + 1
        end
        local A, B, S, Z = pair_sum(first), pair_sum(second), pair_sum(pairs), pair_count(n)
        local numerator, denominator = 2 * (Z * S - A * B), Z * (A + B) - 2 * A * B
        if denominator == 0 then
            numerator, denominator = 1, 1
        end
        ari_lines[#ari_lines + 1] = line(settings[a].name, settings[b].name, report.ari(numerator, denominator))
    end
end
parts[#parts + 1] = ari_lines
local clusters_output = {}
for i, part in ipairs(parts) do
    if i > 1 then
        clusters_output[#clusters_output + 1] = ""
    end
    append(clusters_output, part)
end
local xmin, xmax, ymin, ymax = 10001, 0, 10001, 0
for _, p in ipairs(points) do
    xmin, xmax, ymin, ymax = math.min(xmin, p.x), math.max(xmax, p.x), math.min(ymin, p.y), math.max(ymax, p.y)
end
local cells = {}
for row = 1, params.height do
    cells[row] = {}
    for column = 1, params.width do
        cells[row][column] = {}
    end
end
for i, p in ipairs(points) do
    local column = (p.x - xmin) * params.width // (xmax - xmin + 1) + 1
    local row = (ymax - p.y) * params.height // (ymax - ymin + 1) + 1
    local members = cells[row][column]
    members[#members + 1] = i
end
local maps_output = {}
for _, result in ipairs(settings) do
    maps_output[#maps_output + 1] = line("map", result.name, "clusters", result.count, "noise", result.noise)
    local rows = {}
    for row = 1, params.height do
        local characters = {}
        for column = 1, params.width do
            local members, labels = cells[row][column], {}
            for _, i in ipairs(members) do
                if result.labels[i] >= 0 then
                    labels[result.labels[i]] = true
                end
            end
            local unique = sorted_keys(labels)
            characters[column] = #members == 0 and " " or #unique == 0 and "." or #unique == 1 and label_char(unique[1]) or "*"
        end
        rows[row] = table.concat(characters)
    end
    append(maps_output, report.framed(rows, params.width))
    local legend = {}
    for j, members in ipairs(result.members) do
        legend[#legend + 1] = label_char(j - 1) .. "=" .. #members
    end
    append(maps_output, {"legend " .. (#legend > 0 and table.concat(legend, " ") or "-"), ""})
end
local kind_rows = {}
for row = 1, params.height do
    local characters = {}
    for column = 1, params.width do
        local value = " "
        for _, i in ipairs(cells[row][column]) do
            if knee.core[i] then
                value = "#"
            elseif value ~= "#" and knee.labels[i] >= 0 then
                value = "+"
            elseif value == " " then
                value = "."
            end
        end
        characters[column] = value
    end
    kind_rows[row] = table.concat(characters)
end
maps_output[#maps_output + 1] = "kinds " .. knee.name
append(maps_output, report.framed(kind_rows, params.width))
maps_output[#maps_output + 1] = ""
local heights, knee_column = {}, 1
for column = 1, params.k_width do
    local first, last = (column - 1) * n // params.k_width + 1, column * n // params.k_width
    heights[column] = integer_root(params.k_height * params.k_height * curve.values[first] // curve.values[1])
    if first <= curve.knee and curve.knee <= last then
        knee_column = column
    end
end
local plot_rows = {}
for row = 1, params.k_height do
    local characters = {}
    for column = 1, params.k_width do
        characters[column] = params.k_height - row + 1 <= heights[column] and "#" or column == knee_column and ":" or " "
    end
    plot_rows[row] = table.concat(characters)
end
maps_output[#maps_output + 1] = line("kdist_plot k", m - 1, "max", root(curve.values[1]), "knee_column", knee_column)
append(maps_output, report.framed(plot_rows, params.k_width))
maps_output[#maps_output + 1] = ""
local top, reach_columns, reach_names = 0, {}, {}
for i = 1, n do
    if reach[i] ~= INF then
        top = math.max(top, reach[i])
    end
end
append(reach_columns, extracted_settings)
reach_columns[#reach_columns + 1] = xi_setting
for i, result in ipairs(reach_columns) do
    reach_names[i] = result.name
end
maps_output[#maps_output + 1] = line("reachability width", params.plot_width, "max_reach", root(top), "columns", table.concat(reach_names, " "))
for j, i in ipairs(ordering) do
    local bar = reach[i] == INF and string.rep("-", params.plot_width) or string.rep("#", integer_root(params.plot_width * params.plot_width * reach[i] // top))
    local characters = {}
    for column, result in ipairs(reach_columns) do
        characters[column] = label_char(result.labels[i])
    end
    maps_output[#maps_output + 1] = string.format("%4d %5d %7s %s |%s", j, points[i].id, root(reach[i]), table.concat(characters), bar)
end
os.execute("mkdir -p output")
report.write("labels.csv", labels_output)
report.write("optics_order.csv", optics_output)
report.write("kdist.txt", kdist_output)
report.write("clusters.txt", clusters_output)
report.write("maps.txt", maps_output)
