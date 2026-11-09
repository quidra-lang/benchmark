local PGM = require("pgm_io")
local Costs = require("costs")
local Aggregation = require("aggregation")
local Refinement = require("refinement")
local Evaluation = require("evaluation")
local width, height, left = PGM.read("input/left.pgm")
local right = select(3, PGM.read("input/right.pgm"))
local truth = select(3, PGM.read("input/ground_truth.pgm"))
local params = PGM.parameters()
local size, minimum, maximum = width * height, params.disparity_min, params.disparity_max
local methods_order = { "sad", "ssd", "census", "sgm", "fusion", "wta_final", "sgm_final" }
local selection_order = { "sad", "ssd", "census", "sgm" }
local sources_order = { "kept", "median", "background", "interpolated", "none" }
local reason_order = { { "textureless", 50 }, { "nonunique", 100 }, { "outside", 150 }, { "mismatch", 200 }, { "occluded", 255 } }
local two, ratio = Refinement.two, Evaluation.ratio
local function append(a, b) for _, value in ipairs(b) do a[#a + 1] = value end end
local function map(values, fn) local result = {}; for i, value in ipairs(values) do result[i] = fn(value, i) end; return result end
local function copy(values) return map(values, function(value) return value end) end
local function zeros(n) local result = {}; for i = 1, n do result[i] = 0 end; return result end
local function sum(values) local result = 0; for _, value in ipairs(values) do result = result + value end; return result end
local function count_valid(image) local result = 0; for _, value in ipairs(image) do if value ~= 0 then result = result + 1 end end; return result end
local function median(values) table.sort(values); return values[(#values + 1) // 2] end
local function keys(values) local result = {}; for key in pairs(values) do result[#result + 1] = key end; table.sort(result); return result end
local function frequencies(values) local result = {}; for _, value in ipairs(values) do result[value] = (result[value] or 0) + 1 end; return result end
local function neighbors(p)
    local x, y, result = (p - 1) % width, (p - 1) // width, {}
    for _, offset in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
        local xx, yy = x + offset[1], y + offset[2]
        if xx >= 0 and xx < width and yy >= 0 and yy < height then result[#result + 1] = yy * width + xx + 1 end
    end
    return result
end
local regions = Evaluation.regions(truth, width, height)
local strengths = Costs.texture(left, width, height, params.texture_window)
local cl, cr = Costs.census(left, width, height), Costs.census(right, width, height)
local volume_cache = {}
local function volume(kind, window)
    local key = kind .. ":" .. window
    if not volume_cache[key] then volume_cache[key] = Costs.volume(left, right, cl, cr, width, height, kind, window, minimum, maximum) end
    return volume_cache[key]
end
local function select_disparities(costs)
    local right_disparities = zeros(size)
    for p = 1, size do
        local x, best_cost = (p - 1) % width, math.maxinteger
        for d = minimum, maximum do
            if x + d < width then
                local value = costs[p + d][d - minimum + 1]
                if value < best_cost then best_cost, right_disparities[p] = value, d end
            end
        end
    end
    local result = { image = zeros(size), reasons = zeros(size), margins = zeros(size), lr = zeros(4), bounds = 0 }
    for p, row in ipairs(costs) do
        local x, best, first, second = (p - 1) % width, minimum, row[1], math.maxinteger
        for d = minimum + 1, maximum do if row[d - minimum + 1] < first then first, best = row[d - minimum + 1], d end end
        for d = minimum, maximum do if math.abs(d - best) >= 2 then second = math.min(second, row[d - minimum + 1]) end end
        if best == minimum or best == maximum then result.bounds = result.bounds + 1 end
        local function consistent(d) return x >= d and math.abs(d - right_disparities[p - d]) <= params.lr_max_diff end
        local reason
        if strengths[p] < params.texture_threshold then reason = 50
        elseif 100 * second <= (100 + params.uniqueness) * first then reason = 100
        elseif x < best then reason = 150
        elseif not consistent(best) then
            reason = 255
            for d = minimum, maximum do if consistent(d) then reason = 200; break end end
        else reason, result.image[p], result.margins[p] = 0, best, second - first end
        result.reasons[p] = reason
        if reason == 0 or reason == 200 or reason == 255 then
            local difference = math.abs(best - right_disparities[p - best])
            local bin = math.min(3, difference) + 1
            result.lr[bin] = result.lr[bin] + 1
        end
    end
    return result
end
local function connected_regions(image, maximum_difference)
    local visited, components = {}, {}
    for start, value in ipairs(image) do
        if value ~= 0 and not visited[start] then
            visited[start] = true
            local stack, component = { start }, {}
            while #stack > 0 do
                local p = table.remove(stack)
                component[#component + 1] = p
                for _, q in ipairs(neighbors(p)) do
                    if image[q] ~= 0 and not visited[q] and math.abs(image[q] - image[p]) <= maximum_difference then visited[q] = true; stack[#stack + 1] = q end
                end
            end
            components[#components + 1] = component
        end
    end
    return components
end
local function ray_values(image, x, y, directions)
    local values = {}
    for _, direction in ipairs(directions) do
        local xx, yy = x + direction[1], y + direction[2]
        while xx >= 0 and xx < width and yy >= 0 and yy < height do
            local value = image[yy * width + xx + 1]
            if value ~= 0 then values[#values + 1] = value; break end
            xx, yy = xx + direction[1], yy + direction[2]
        end
    end
    return values
end
local function postprocess(selection)
    local original, filtered = selection.image, copy(selection.image)
    local removed, removed_pixels = 0, 0
    for _, component in ipairs(connected_regions(original, params.speckle_range)) do
        if #component < params.speckle_size then
            removed, removed_pixels = removed + 1, removed_pixels + #component
            for _, p in ipairs(component) do filtered[p] = 0 end
        end
    end
    local medians, changed = zeros(size), 0
    for p, disparity in ipairs(filtered) do
        if disparity ~= 0 then
            local x, y, values = (p - 1) % width, (p - 1) // width, {}
            for yy = math.max(0, y - 1), math.min(height - 1, y + 1) do
                for xx = math.max(0, x - 1), math.min(width - 1, x + 1) do
                    local value = filtered[yy * width + xx + 1]
                    if value ~= 0 then values[#values + 1] = value end
                end
            end
            medians[p] = median(values)
        end
        if medians[p] ~= disparity then changed = changed + 1 end
    end
    local result = { image = copy(medians), sources = {}, speckles = removed, speckle_pixels = removed_pixels, median_changed = changed, background = 0, interpolated = 0, unfilled = 0 }
    for p, disparity in ipairs(medians) do
        if disparity ~= 0 then result.sources[p] = disparity == original[p] and "kept" or "median"
        else
            local x, y = (p - 1) % width, (p - 1) // width
            local background = selection.reasons[p] == 150 or selection.reasons[p] == 255
            local values = ray_values(medians, x, y, background and { { -1, 0 }, { 1, 0 } } or Aggregation.directions)
            if #values == 0 then result.sources[p], result.unfilled = "none", result.unfilled + 1
            elseif background then result.image[p], result.sources[p], result.background = math.min(table.unpack(values)), "background", result.background + 1
            else result.image[p], result.sources[p], result.interpolated = median(values), "interpolated", result.interpolated + 1 end
        end
    end
    return result
end
local methods, sweeps, progress = {}, {}, {}
for _, kind in ipairs({ "sad", "ssd", "census" }) do
    local best_metrics
    for _, window in ipairs(params[kind .. "_windows"]) do
        local selection = select_disparities(volume(kind, window))
        selection.window = window
        local metrics = Evaluation.evaluate(selection.image, truth, regions.nonocc)
        sweeps[#sweeps + 1] = { kind = kind, window = window, valid = count_valid(selection.image), metrics = metrics }
        if not best_metrics or metrics.bad1 < best_metrics.bad1 or metrics.bad1 == best_metrics.bad1 and metrics.bad2 < best_metrics.bad2 then methods[kind], best_metrics = selection, metrics end
    end
end
local summed_costs = Aggregation.cumulative(volume(params.sgm_cost, params.sgm_window), left, width, height, params.sgm_paths, params.p1, params.p2, params.p2_gamma, function(i, total)
    local selection = select_disparities(total)
    selection.window = params.sgm_window
    methods.sgm = selection
    progress[#progress + 1] = { number = i, valid = count_valid(selection.image), metrics = Evaluation.evaluate(selection.image, truth, regions.nonocc) }
end)
methods.fusion = { image = zeros(size), votes = zeros(5) }
for p = 1, size do
    local values = {}
    for _, name in ipairs(selection_order) do local value = methods[name].image[p]; if value ~= 0 then values[#values + 1] = value end end
    local votes = methods.fusion.votes
    votes[#values + 1] = votes[#values + 1] + 1
    if #values > 0 then
        local middle, agreeing = median(values), 0
        for _, value in ipairs(values) do if math.abs(value - middle) <= 1 then agreeing = agreeing + 1 end end
        if agreeing >= params.fusion_min_votes then methods.fusion.image[p] = middle end
    end
end
methods.wta_final, methods.sgm_final = postprocess(methods[params.wta_cost]), postprocess(methods.sgm)
local true_counts = {}
for _, value in ipairs(truth) do if value ~= 0 then true_counts[value] = (true_counts[value] or 0) + 1 end end
local layers = keys(true_counts)
local objects, small = {}, 0
for _, component in ipairs(connected_regions(methods.sgm_final.image, params.object_range)) do
    if #component < params.object_min_size then small = small + 1
    else
        local values, counts, x0, y0, x1, y1, first = {}, {}, width, height, -1, -1, size + 1
        for _, p in ipairs(component) do
            local x, y = (p - 1) % width, (p - 1) // width
            x0, y0, x1, y1, first = math.min(x0, x), math.min(y0, y), math.max(x1, x), math.max(y1, y), math.min(first, p)
            values[#values + 1] = methods.sgm_final.image[p]
            if truth[p] ~= 0 then counts[truth[p]] = (counts[truth[p]] or 0) + 1 end
        end
        local middle, n, total = median(values), #component, sum(values)
        local layer
        for _, value in ipairs(keys(counts)) do if not layer or counts[value] > counts[layer] then layer = value end end
        local hits, union = layer and counts[layer] or 0, layer and n + true_counts[layer] - counts[layer] or 0
        objects[#objects + 1] = { pixels = n, box = { x0, y0, x1, y1 }, minimum = values[1], maximum = values[#values], median = middle,
            mean = two(total, n), depth = two(params.focal_length * params.baseline * n, total), width = two((x1 - x0 + 1) * params.baseline, middle),
            height = two((y1 - y0 + 1) * params.baseline, middle), truth = layer, hits = hits, union = union, first = first }
    end
end
table.sort(objects, function(a, b)
    if a.median ~= b.median then return a.median > b.median end
    return a.pixels > b.pixels or a.pixels == b.pixels and a.first < b.first
end)
local detected = {}
for _, object in ipairs(objects) do if object.truth and 2 * object.hits > object.union then detected[object.truth] = true end end
local function sample_lines()
    local lines = { "x,y,sad,ssd,census,sgm,disparity,source,subpixel,depth,truth,truth_depth" }
    for _, point in ipairs(params.sample_pixels) do
        local x, y = point[1], point[2]
        local p, row = y * width + x + 1, { x, y }
        for _, name in ipairs(selection_order) do local value = methods[name].image[p]; row[#row + 1] = value ~= 0 and value or "-" end
        local disparity = methods.sgm_final.image[p]
        if disparity ~= 0 then
            local subpixel, depth = Refinement.subpixel(disparity, summed_costs[p], minimum, maximum, params.focal_length, params.baseline)
            append(row, { disparity, methods.sgm_final.sources[p], subpixel, depth })
        else append(row, { "-", "none", "-", "-" }) end
        if truth[p] ~= 0 then append(row, { truth[p], two(params.focal_length * params.baseline, truth[p]) }) else append(row, { "-", "-" }) end
        lines[#lines + 1] = table.concat(row, ",")
    end
    return lines
end
local function object_lines()
    local total = 0
    for _, object in ipairs(objects) do total = total + object.pixels end
    local lines = { string.format("objects %d small %d pixels %d", #objects, small, total) }
    for i, object in ipairs(objects) do
        local actual = object.truth and "truth " .. object.truth .. " iou " .. ratio(object.hits, object.union) or "truth - iou -"
        lines[#lines + 1] = string.format("object %d pixels %d box %s disparity %d %d median %d mean %s depth %s size %s %s %s", i, object.pixels,
            table.concat(object.box, " "), object.minimum, object.maximum, object.median, object.mean, object.depth, object.width, object.height, actual)
    end
    local missed = {}
    for _, layer in ipairs(layers) do if not detected[layer] then missed[#missed + 1] = layer end end
    lines[#lines + 1] = string.format("layers %d detected %d missed %s", #layers, #keys(detected), #missed > 0 and table.concat(missed, " ") or "-")
    return lines
end
local function evaluation_lines()
    local lines, metrics = {}, {}
    local function add(...) lines[#lines + 1] = table.concat({ ... }, " ") end
    add("image", width, height)
    add("disparities", minimum, maximum)
    for _, pair in ipairs({ { "left", left }, { "right", right } }) do add(pair[1], "mean", two(sum(pair[2]), size), "min", math.min(table.unpack(pair[2])), "max", math.max(table.unpack(pair[2]))) end
    local textureless, absolute_sum, bias_sum = 0, 0, 0
    for _, value in ipairs(strengths) do if value < params.texture_threshold then textureless = textureless + 1 end end
    for _, p in ipairs(regions.nonocc) do local difference = right[p - truth[p]] - left[p]; absolute_sum, bias_sum = absolute_sum + math.abs(difference), bias_sum + difference end
    local bias = two(math.abs(bias_sum), #regions.nonocc)
    if bias_sum < 0 and bias ~= "0.00" then bias = "-" .. bias end
    add("texture mean", two(sum(strengths), size), "textureless", textureless)
    add("ground_truth known", #regions.all, "nonocc", #regions.nonocc, "occluded", #regions.occluded, "disc", #regions.disc, "unknown", size - #regions.all)
    add("photometric pixels", #regions.nonocc, "mean_abs", two(absolute_sum, #regions.nonocc), "bias", bias)
    for _, sweep in ipairs(sweeps) do add("sweep", sweep.kind, "window", sweep.window, "valid", sweep.valid, "bad1", ratio(sweep.metrics.bad1, sweep.metrics.pixels), "bad2", ratio(sweep.metrics.bad2, sweep.metrics.pixels)) end
    for _, path in ipairs(progress) do add("paths", path.number, "valid", path.valid, "bad1", ratio(path.metrics.bad1, path.metrics.pixels), "bad2", ratio(path.metrics.bad2, path.metrics.pixels)) end
    for _, name in ipairs(methods_order) do
        local method, values, horizontal, vertical = methods[name], {}, 0, 0
        local image = method.image
        for p, value in ipairs(image) do
            if value ~= 0 then
                values[#values + 1] = value
                local x, y = (p - 1) % width, (p - 1) // width
                if x + 1 < width and image[p + 1] ~= 0 and math.abs(value - image[p + 1]) >= 2 then horizontal = horizontal + 1 end
                if y + 1 < height and image[p + width] ~= 0 and math.abs(value - image[p + width]) >= 2 then vertical = vertical + 1 end
            end
        end
        add("method", name, "valid", #values, "invalid", size - #values)
        if #values == 0 then add("disparity min - max - median - distinct 0")
        else
            local middle = median(values)
            add("disparity min", values[1], "max", values[#values], "median", middle, "distinct", #keys(frequencies(values)))
        end
        add("jumps horizontal", horizontal, "vertical", vertical)
        if method.reasons then
            add("window", method.window, "bounds", method.bounds)
            local reason_counts, parts = frequencies(method.reasons), { "reasons" }
            for _, reason in ipairs(reason_order) do append(parts, { reason[1], reason_counts[reason[2]] or 0 }) end
            lines[#lines + 1] = table.concat(parts, " ")
            add("lr 0", method.lr[1], "1", method.lr[2], "2", method.lr[3], "3+", method.lr[4])
        elseif name == "fusion" then add("votes 0", method.votes[1], "1", method.votes[2], "2", method.votes[3], "3", method.votes[4], "4", method.votes[5])
        else
            add("postprocess speckles", method.speckles, method.speckle_pixels, "median", method.median_changed, "background", method.background, "interpolated", method.interpolated, "unfilled", method.unfilled)
            for _, source in ipairs(sources_order) do
                local region = {}
                for _, p in ipairs(regions.all) do if method.sources[p] == source then region[#region + 1] = p end end
                local score = Evaluation.evaluate(image, truth, region)
                add("source", source, "pixels", score.pixels, "bad1", ratio(score.bad1, score.pixels))
            end
        end
        metrics[name] = {}
        for _, region in ipairs(Evaluation.region_order) do
            local score = Evaluation.evaluate(image, truth, regions[region])
            metrics[name][region] = score
            add("region", region, "pixels", score.pixels, "valid", score.valid, "bad1", ratio(score.bad1, score.pixels), "bad2", ratio(score.bad2, score.pixels), "mae", score.mae, "exact", score.exact)
        end
        local errors = {}
        for _, p in ipairs(regions.nonocc) do
            if image[p] ~= 0 then errors[#errors + 1] = math.abs(Refinement.depth_hundredths(image[p], params.focal_length, params.baseline) - Refinement.depth_hundredths(truth[p], params.focal_length, params.baseline)) end
        end
        if #errors == 0 then add("depth_error pixels 0 mean - max -")
        else add("depth_error pixels", #errors, "mean", two(sum(errors), 100 * #errors), "max", two(math.max(table.unpack(errors)), 100)) end
        local error_counts, invalid = zeros(5), 0
        for _, p in ipairs(regions.all) do
            if image[p] == 0 then invalid = invalid + 1
            else local bin = math.min(math.abs(image[p] - truth[p]), 4) + 1; error_counts[bin] = error_counts[bin] + 1 end
        end
        add("errors 0", error_counts[1], "1", error_counts[2], "2", error_counts[3], "3", error_counts[4], "4+", error_counts[5], "invalid", invalid)
    end
    local order = {}; for i, name in ipairs(methods_order) do order[name] = i end
    for _, region in ipairs(Evaluation.region_order) do
        local ranked = copy(methods_order)
        table.sort(ranked, function(a, b)
            local x, y = metrics[a][region], metrics[b][region]
            if x.bad1 ~= y.bad1 then return x.bad1 < y.bad1 end
            if x.bad2 ~= y.bad2 then return x.bad2 < y.bad2 end
            if (x.valid == 0) ~= (y.valid == 0) then return x.valid > 0 end
            if x.valid > 0 and x.error_sum * y.valid ~= y.error_sum * x.valid then return x.error_sum * y.valid < y.error_sum * x.valid end
            return order[a] < order[b]
        end)
        add("ranking", region, table.concat(ranked, " "))
    end
    for _, name in ipairs(selection_order) do
        local reasons, tp, fp = methods[name].reasons, 0, 0
        for _, p in ipairs(regions.occluded) do if reasons[p] == 150 or reasons[p] == 255 then tp = tp + 1 end end
        for _, p in ipairs(regions.nonocc) do if reasons[p] == 150 or reasons[p] == 255 then fp = fp + 1 end end
        local fn = #regions.occluded - tp
        add("occlusion", name, "tp", tp, "fp", fp, "fn", fn, "precision", ratio(tp, tp + fp), "recall", ratio(tp, tp + fn))
    end
    for _, name in ipairs(selection_order) do
        local method, pixels = methods[name], {}
        for _, p in ipairs(regions.nonocc) do if method.image[p] ~= 0 then pixels[#pixels + 1] = p end end
        table.sort(pixels, function(a, b) return method.margins[a] > method.margins[b] or method.margins[a] == method.margins[b] and a < b end)
        for _, percentage in ipairs({ 25, 50, 75, 100 }) do
            local n, bad = (#pixels * percentage + 99) // 100, 0
            for i = 1, n do local p = pixels[i]; if math.abs(method.image[p] - truth[p]) > 1 then bad = bad + 1 end end
            add("confidence", name, percentage, "pixels", n, "margin", n > 0 and method.margins[pixels[n]] or "-", "bad1", ratio(bad, n))
        end
    end
    for _, layer in ipairs(layers) do
        local region, errors = {}, {}
        for _, p in ipairs(regions.nonocc) do if truth[p] == layer then region[#region + 1] = p end end
        for _, name in ipairs(methods_order) do errors[#errors + 1] = Evaluation.evaluate(methods[name].image, truth, region).bad1 end
        add("layer", layer, "pixels", true_counts[layer], "nonocc", #region, "bad1", table.concat(errors, " "))
    end
    local counts = frequencies(methods.sgm_final.image)
    for d = minimum, maximum do add("histogram", d, counts[d] or 0) end
    return lines
end
local function write(name, lines)
    local output = assert(io.open("output/" .. name, "w"))
    output:write(table.concat(lines, "\n"), "\n")
    output:close()
end
PGM.write("output/disparity_wta.pgm", width, height, map(methods.wta_final.image, function(value) return 8 * value end))
PGM.write("output/disparity_sgm.pgm", width, height, map(methods.sgm_final.image, function(value) return 8 * value end))
PGM.write("output/occlusion.pgm", width, height, methods.sgm.reasons)
PGM.write("output/error_sgm.pgm", width, height, map(methods.sgm_final.image, function(value, p)
    if truth[p] == 0 then return 0 elseif value == 0 then return 255 end
    return 50 * (math.min(math.abs(value - truth[p]), 3) + 1)
end))
write("depth.csv", sample_lines())
write("evaluation.txt", evaluation_lines())
write("objects.txt", object_lines())
