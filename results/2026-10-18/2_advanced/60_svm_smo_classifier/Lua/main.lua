local Dataset = require("dataset")
local E = require("evaluation")
local K = require("kernels")
local S = require("smo")
local M = require("multiclass")
local f, ratio, sign = E.fixed, E.ratio, E.sign
local function append(values, other) for _, value in ipairs(other) do values[#values + 1] = value end end
local function map(values, fn)
    local result = {}
    for i, value in ipairs(values) do result[i] = fn(value, i) end
    return result
end
local function points(examples) return map(examples, function(example) return example.point end) end
local function labels(examples) return map(examples, function(example) return example.label end) end
local function subset(values, indices) return map(indices, function(i) return values[i] end) end
local function support_counts(model)
    local total, bound = 0, 0
    for _, alpha in ipairs(model.alpha) do if alpha > 0 then total = total + 1; if alpha == model.C then bound = bound + 1 end end end
    return total, bound, total - bound
end
local function support_text(model)
    local total, bound, free = support_counts(model)
    return string.format("support_vectors %d bound %d free %d", total, bound, free)
end
local function run_info(model) return string.format("passes %d steps %d converged %s", model.passes, model.steps, model.converged and "yes" or "no") end
local function objectives(model, alpha)
    alpha = alpha or model.alpha
    local scores = {}
    for i, row in ipairs(model.matrix) do
        local score = 0.0
        for j, value in ipairs(alpha) do if value > 0 then score = score + value * model.labels[j] * row[j] end end
        scores[i] = score
    end
    local quadratic, total = 0.0, 0.0
    for i, value in ipairs(alpha) do quadratic, total = quadratic + value * model.labels[i] * scores[i], total + value end
    return quadratic, total - quadratic / 2
end
local function ranking_less(a, b)
    if a.correct ~= b.correct then return a.correct > b.correct end
    if a.C ~= b.C then return a.C < b.C end
    return a.kernel_index < b.kernel_index
end
local function cross_validate(training, settings)
    local all_points, all_labels = points(training), labels(training)
    local partitions, matrices, combinations, best = E.folds(#training, settings.folds), {}, {}, {}
    for kernel_index, kernel in ipairs(settings.kernels) do
        local matrix = kernel:matrix(all_points)
        matrices[kernel_index] = matrix
        for _, coefficient in ipairs(settings.c_grid) do
            local result = { kernel = kernel, kernel_index = kernel_index, C = coefficient, values = {}, folds = {}, correct = 0, support = 0, passes = 0, steps = 0 }
            for _, partition in ipairs(partitions) do
                local train_indices, test_indices = partition[1], partition[2]
                local model = S.train(subset(all_points, train_indices), subset(all_labels, train_indices), kernel, K.submatrix(matrix, train_indices), coefficient, settings)
                local correct = 0
                for _, i in ipairs(test_indices) do
                    local value = model:decision(all_points[i])
                    result.values[i] = value
                    if sign(value) == all_labels[i] then correct = correct + 1 end
                end
                local support = support_counts(model)
                result.folds[#result.folds + 1] = { train = #train_indices, test = #test_indices, correct = correct, support = support, model = model }
                result.correct, result.support, result.passes, result.steps = result.correct + correct, result.support + support, result.passes + model.passes, result.steps + model.steps
            end
            combinations[#combinations + 1] = result
            if not best[kernel_index] or ranking_less(result, best[kernel_index]) then best[kernel_index] = result end
        end
    end
    local ranking = {}
    append(ranking, combinations)
    table.sort(ranking, ranking_less)
    return matrices, combinations, best, ranking[1], ranking
end
local function cross_validation_lines(size, folds, best, selected, ranking)
    local lines = { "cross_validation folds " .. folds .. " examples " .. size }
    for _, result in ipairs(best) do
        lines[#lines + 1] = "best " .. result.kernel.name .. " C " .. f(result.C) .. " correct " .. result.correct .. "/" .. size .. " accuracy " .. ratio(result.correct, size)
    end
    append(lines, { "selected " .. selected.kernel.name .. " C " .. f(selected.C), "ranking" })
    for rank, result in ipairs(ranking) do lines[#lines + 1] = rank .. " " .. result.kernel.name .. " C " .. f(result.C) .. " correct " .. result.correct .. "/" .. size end
    lines[#lines + 1] = "cv_detail " .. selected.kernel.name .. " C " .. f(selected.C)
    for i, result in ipairs(selected.folds) do
        lines[#lines + 1] = string.format("fold %d train %d test %d correct %d support_vectors %d %s", i, result.train, result.test, result.correct, result.support, run_info(result.model))
    end
    return lines
end
local function final_evaluation(model, training, testing, tolerance)
    local n, m = #training, #testing
    local train_values, test_values, test_labels = model:training_decisions(), map(testing, function(example) return model:decision(example.point) end), labels(testing)
    local quadratic, dual = objectives(model)
    local sy, sg, maximum_diagonal, minimum = 0.0, 0.0, -math.huge, math.huge
    for i, row in ipairs(model.matrix) do
        maximum_diagonal = math.max(maximum_diagonal, row[i])
        for j, value in ipairs(row) do sy, sg, minimum = sy + model.labels[i] * model.labels[j] * value, sg + value * value, math.min(minimum, value) end
    end
    local alignment, equality, w1, w2 = sy / (n * math.sqrt(sg)), 0.0, 0.0, 0.0
    local classes = { [1] = { bound = 0, free = 0 }, [-1] = { bound = 0, free = 0 } }
    for i, example in ipairs(training) do
        local alpha = model.alpha[i]
        equality = equality + alpha * example.label
        if model.kernel.kind == "linear" then w1, w2 = w1 + alpha * example.label * example.point[1], w2 + alpha * example.label * example.point[2] end
        if alpha > 0 then
            local class, category = classes[example.label], alpha == model.C and "bound" or "free"
            class[category] = class[category] + 1
        end
    end
    local norm, radius, hinge_total, violations, estimated_errors, largest = math.sqrt(quadratic), maximum_diagonal - minimum, 0.0, 0, 0, 0.0
    for i, alpha in ipairs(model.alpha) do
        local label, value = model.labels[i], train_values[i]
        local hinge = math.max(0.0, 1 - label * value)
        hinge_total = hinge_total + hinge
        local residual, violation = label * value - 1
        if alpha == 0 then violation = math.max(0.0, -residual) elseif alpha == model.C then violation = math.max(0.0, residual) else violation = math.abs(residual) end
        if violation > tolerance then violations = violations + 1 end
        largest = math.max(largest, violation)
        if 2 * alpha * radius + hinge >= 1 then estimated_errors = estimated_errors + 1 end
    end
    local primal, train_correct = quadratic / 2 + model.C * hinge_total, E.correct(model.labels, train_values)
    local tp, fp, tn, fn = E.binary_counts(test_labels, test_values)
    local inside, positive_sum, negative_sum = 0, 0.0, 0.0
    for i, label in ipairs(test_labels) do
        local value = test_values[i]
        if math.abs(value) < 1 then inside = inside + 1 end
        if label == 1 then positive_sum = positive_sum + value else negative_sum = negative_sum + value end
    end
    local choices, clipping, positive, negative = model.choices, model.clipping, classes[1], classes[-1]
    local lines = {
        "model " .. model.kernel.name, "kernel " .. model.kernel:description(), "C " .. f(model.C), "alignment " .. f(alignment, 6),
        string.format("passes %d full %d nonbound %d converged %s", model.passes, model.full_passes, model.nonbound_passes, model.converged and "yes" or "no"),
        string.format("examined %d steps %d", model.examined, model.steps),
        string.format("choice heuristic %d nonbound_loop %d full_loop %d", choices.heuristic, choices.nonbound_loop, choices.full_loop),
        string.format("clipping none %d lower %d upper %d", clipping.none, clipping.lower, clipping.upper), support_text(model), "b " .. f(model.b, 6), "equality " .. f(equality, 6)
    }
    if model.kernel.kind == "linear" then lines[#lines + 1] = "w " .. f(w1, 6) .. " " .. f(w2, 6) end
    append(lines, {
        string.format("sv_by_class positive bound %d free %d negative bound %d free %d", positive.bound, positive.free, negative.bound, negative.free),
        "norm " .. f(norm, 6) .. " margin " .. f(2 / norm, 6), "dual_objective " .. f(dual, 6), "primal_objective " .. f(primal, 6), "duality_gap " .. f(primal - dual, 6),
        "kkt_violations " .. violations .. " max " .. f(largest, 6), "xi_alpha radius " .. f(radius, 6) .. " errors " .. estimated_errors .. "/" .. n .. " accuracy " .. ratio(n - estimated_errors, n),
        "train correct " .. train_correct .. "/" .. n .. " accuracy " .. ratio(train_correct, n),
        string.format("test correct %d/%d accuracy %s tp %d fp %d tn %d fn %d", tp + tn, m, ratio(tp + tn, m), tp, fp, tn, fn),
        "test precision " .. ratio(tp, tp + fp) .. " recall " .. ratio(tp, tp + fn) .. " f1 " .. ratio(2 * tp, 2 * tp + fp + fn) .. " auc " .. f(E.auc(test_labels, test_values)),
        "test inside_margin " .. inside, "test mean_decision positive " .. f(positive_sum / (tp + fn)) .. " negative " .. f(negative_sum / (fp + tn))
    })
    for i, example in ipairs(training) do
        local alpha = model.alpha[i]
        if alpha > 0 then lines[#lines + 1] = "sv " .. example.id .. " y " .. example.label .. " alpha " .. f(alpha, 6) .. " f " .. f(train_values[i]) .. " " .. (alpha == model.C and "bound" or "free") end
    end
    return { model = model, train_values = train_values, test_values = test_values, weights = { w1, w2 }, lines = lines }
end
local function training_log(model)
    local lines, index = { "training_log " .. model.kernel.name }, 1
    while index <= #model.records do
        local record = model.records[index]
        if record.full then
            local _, dual = objectives(model, record.alpha)
            lines[#lines + 1] = "pass " .. index .. " full examined " .. record.examined .. " changed " .. record.changed .. " dual_objective " .. f(dual, 6)
            index = index + 1
        else
            local first, examined, changed = index, 0, 0
            while index <= #model.records and not model.records[index].full do
                examined, changed = examined + model.records[index].examined, changed + model.records[index].changed
                index = index + 1
            end
            lines[#lines + 1] = string.format("passes %d-%d nonbound examined %d changed %d", first, index - 1, examined, changed)
        end
    end
    return lines
end
local function c_path(training, testing, selected, matrix, settings)
    local lines, all_points, all_labels, test_labels = { "c_path " .. selected.kernel.name }, points(training), labels(training), labels(testing)
    for _, coefficient in ipairs(settings.c_grid) do
        local model = S.train(all_points, all_labels, selected.kernel, matrix, coefficient, settings)
        local _, dual = objectives(model)
        local correct = E.correct(all_labels, model:training_decisions())
        local test_correct = E.correct(test_labels, map(testing, function(example) return model:decision(example.point) end))
        lines[#lines + 1] = "C " .. f(coefficient) .. " " .. support_text(model) .. " dual_objective " .. f(dual, 6) .. " train " .. correct .. "/" .. #training .. " test " .. test_correct .. "/" .. #testing .. " " .. run_info(model)
    end
    return lines
end
local function learning_curve(training, testing, selected, matrix, settings)
    local lines, test_labels = { "learning_curve " .. selected.kernel.name .. " C " .. f(selected.C) }, labels(testing)
    for _, percentage in ipairs(settings.learning_curve) do
        local size, indices = #training * percentage // 100, {}
        for i = 1, size do indices[i] = i end
        local examples = subset(training, indices)
        local all_labels = labels(examples)
        local model = S.train(points(examples), all_labels, selected.kernel, K.submatrix(matrix, indices), selected.C, settings)
        local train_correct = E.correct(all_labels, model:training_decisions())
        local test_correct = E.correct(test_labels, map(testing, function(example) return model:decision(example.point) end))
        lines[#lines + 1] = string.format("size %d support_vectors %d train %d/%d test %d/%d %s", size, support_counts(model), train_correct, size, test_correct, #testing, run_info(model))
    end
    return lines
end
local function probability(value, a, b) return 1 / (1 + math.exp(a * value + b)) end
local function nll(values, targets, a, b)
    local total = 0.0
    for i, value in ipairs(values) do
        local p, target = probability(value, a, b), targets[i]
        total = total + (target * math.log(p) + (1 - target) * math.log(1 - p))
    end
    return -total
end
local function calibrate(training, testing, selected, test_values, iterations)
    local positive = 0
    for _, example in ipairs(training) do if example.label == 1 then positive = positive + 1 end end
    local negative = #training - positive
    local targets = map(training, function(example) return example.label == 1 and (positive + 1) / (positive + 2) or 1 / (negative + 2) end)
    local values, a, b = selected.values, 0.0, math.log((negative + 1) / (positive + 1))
    local lines = {
        "calibration " .. selected.kernel.name .. " C " .. f(selected.C) .. " positives " .. positive .. " negatives " .. negative,
        "start A " .. f(a, 6) .. " B " .. f(b, 6) .. " nll " .. f(nll(values, targets, a, b), 6)
    }
    for iteration = 1, iterations do
        local g1, g2, h11, h21, h22 = 0.0, 0.0, 0.0, 0.0, 0.0
        for i, value in ipairs(values) do
            local p, target = probability(value, a, b), targets[i]
            g1, g2 = g1 + value * (target - p), g2 + (target - p)
            h11, h21, h22 = h11 + value * value * p * (1 - p), h21 + value * p * (1 - p), h22 + p * (1 - p)
        end
        local det = h11 * h22 - h21 * h21
        a, b = a - (h22 * g1 - h21 * g2) / det, b - (h11 * g2 - h21 * g1) / det
        lines[#lines + 1] = "iteration " .. iteration .. " A " .. f(a, 6) .. " B " .. f(b, 6) .. " nll " .. f(nll(values, targets, a, b), 6)
    end
    local probabilities = map(test_values, function(value) return probability(value, a, b) end)
    local log_total, brier_total, bins = 0.0, 0.0, {}
    for i = 1, 5 do bins[i] = { count = 0, total = 0.0, positive = 0 } end
    for i, example in ipairs(testing) do
        local p, positive_label = probabilities[i], example.label == 1
        log_total = log_total + math.log(positive_label and p or 1 - p)
        local difference = p - (positive_label and 1 or 0)
        brier_total = brier_total + difference * difference
        local bin = bins[math.min(4, math.floor(p * 5)) + 1]
        bin.count, bin.total = bin.count + 1, bin.total + p
        if positive_label then bin.positive = bin.positive + 1 end
    end
    lines[#lines + 1] = "test log_loss " .. f(-log_total / #testing, 6) .. " brier " .. f(brier_total / #testing, 6)
    local ranges = { "0.0-0.2", "0.2-0.4", "0.4-0.6", "0.6-0.8", "0.8-1.0" }
    for i, bin in ipairs(bins) do
        lines[#lines + 1] = "bin " .. ranges[i] .. " count " .. bin.count .. " mean_probability " .. (bin.count > 0 and f(bin.total / bin.count) or "-") .. " positive_rate " .. ratio(bin.positive, bin.count)
    end
    local closest = {}
    for i = 1, #testing do closest[i] = i end
    table.sort(closest, function(i, j) local a1, b1 = math.abs(test_values[i]), math.abs(test_values[j]); return a1 < b1 or a1 == b1 and i < j end)
    for i = 1, 5 do
        local index = closest[i]
        lines[#lines + 1] = "closest " .. testing[index].id .. " label " .. testing[index].label .. " decision " .. f(test_values[index]) .. " probability " .. f(probabilities[index])
    end
    return a, b, probabilities, lines
end
local function linear_value(weights, point) return weights[1] * point[1] + weights[2] * point[2] + weights[3] end
local function pegasos(training, testing, parameters, comparison)
    local lambda, iterations, seed = table.unpack(parameters)
    local state, w1, w2, w0, sum1, sum2, sum0, updates = seed, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0
    local n, m, train_labels, test_labels = #training, #testing, labels(training), labels(testing)
    local lines = { "pegasos lambda " .. f(lambda) .. " iterations " .. iterations .. " seed " .. seed }
    for t = 1, iterations do
        state = 48271 * state % 2147483647
        local example = training[state % n + 1]
        local eta = 1 / (lambda * t)
        local sigma = 1 - eta * lambda
        if example.label * (w1 * example.point[1] + w2 * example.point[2] + w0) < 1 then
            w1, w2, w0 = sigma * w1 + eta * example.label * example.point[1], sigma * w2 + eta * example.label * example.point[2], sigma * w0 + eta * example.label
            updates = updates + 1
        else w1, w2, w0 = sigma * w1, sigma * w2, sigma * w0 end
        sum1, sum2, sum0 = sum1 + w1, sum2 + w2, sum0 + w0
        if t % (iterations // 10) == 0 then
            local values = map(training, function(item) return w1 * item.point[1] + w2 * item.point[2] + w0 end)
            local hinge = 0.0
            for i, label in ipairs(train_labels) do hinge = hinge + math.max(0.0, 1 - label * values[i]) end
            local objective = lambda / 2 * (w1 * w1 + w2 * w2 + w0 * w0) + hinge / n
            lines[#lines + 1] = "checkpoint " .. t .. " objective " .. f(objective, 6) .. " train " .. E.correct(train_labels, values) .. "/" .. n
        end
    end
    local weights, average = { w1, w2, w0 }, { sum1 / iterations, sum2 / iterations, sum0 / iterations }
    local train_values = map(training, function(example) return linear_value(weights, example.point) end)
    local test_values = map(testing, function(example) return linear_value(weights, example.point) end)
    local average_values = map(testing, function(example) return linear_value(average, example.point) end)
    local train_correct, test_correct, average_correct = E.correct(train_labels, train_values), E.correct(test_labels, test_values), E.correct(test_labels, average_values)
    local v1, v2 = table.unpack(comparison.weights)
    local cosine = (w1 * v1 + w2 * v2) / (math.sqrt(w1 * w1 + w2 * w2) * math.sqrt(v1 * v1 + v2 * v2))
    local agreement = 0
    for i, value in ipairs(test_values) do if sign(value) == sign(comparison.test_values[i]) then agreement = agreement + 1 end end
    append(lines, {
        "updates " .. updates, "w " .. f(w1, 6) .. " " .. f(w2, 6) .. " bias " .. f(w0, 6),
        "train correct " .. train_correct .. "/" .. n .. " accuracy " .. ratio(train_correct, n), "test correct " .. test_correct .. "/" .. m .. " accuracy " .. ratio(test_correct, m),
        "average w " .. f(average[1], 6) .. " " .. f(average[2], 6) .. " bias " .. f(average[3], 6) .. " test correct " .. average_correct .. "/" .. m,
        "compare " .. comparison.model.kernel.name .. " cosine " .. f(cosine, 6) .. " test_agreement " .. agreement .. "/" .. m
    })
    return test_values, lines
end
local function mcnemar(testing, finals, pegasos_values)
    local names, values = {}, {}
    for i, result in ipairs(finals) do names[i], values[i] = result.model.kernel.name, result.test_values end
    names[#names + 1], values[#values + 1] = "pegasos", pegasos_values
    local lines = { "mcnemar" }
    for i = 1, #names do
        for j = i + 1, #names do
            local first, second = 0, 0
            for k, example in ipairs(testing) do
                local a, b = sign(values[i][k]) == example.label, sign(values[j][k]) == example.label
                if a and not b then first = first + 1 elseif b and not a then second = second + 1 end
            end
            local denominator, difference = first + second, math.abs(first - second) - 1
            local chi2 = denominator > 0 and f(difference * difference / denominator) or "-"
            lines[#lines + 1] = string.format("%s %s only_first %d only_second %d chi2 %s", names[i], names[j], first, second, chi2)
        end
    end
    return lines
end
local function multiclass_summary(role, examples, results)
    local rest, pair, agreement, ties = 0, 0, 0, 0
    for i, example in ipairs(examples) do
        local result = results[i]
        if result.ovr == example.label then rest = rest + 1 end
        if result.ovo == example.label then pair = pair + 1 end
        if result.ovr == result.ovo then agreement = agreement + 1 end
        if result.tied then ties = ties + 1 end
    end
    return string.format("%s ovr %d/%d %s ovo %d/%d %s agreement %d/%d vote_ties %d", role, rest, #examples, ratio(rest, #examples), pair, #examples, ratio(pair, #examples), agreement, #examples, ties)
end
local function multiclass_report(training, testing, models)
    local train_results = map(training, function(example) return models:classify(example.point) end)
    local test_results = map(testing, function(example) return models:classify(example.point) end)
    local n, m = #training, #testing
    local lines = { "multiclass kernel " .. models.kernel.name .. " C " .. f(models.C) .. " classes 3 train " .. n .. " test " .. m, "ovr" }
    local function positives(model)
        local count = 0
        for _, label in ipairs(model.labels) do if label == 1 then count = count + 1 end end
        return count
    end
    for i, model in ipairs(models.ovr_models) do
        local correct = 0
        for j, example in ipairs(testing) do if sign(test_results[j].ovr_values[i]) == (example.label == i and 1 or -1) then correct = correct + 1 end end
        lines[#lines + 1] = "model " .. i .. "-rest examples " .. n .. " positives " .. positives(model) .. " " .. support_text(model) .. " b " .. f(model.b, 6) .. " " .. run_info(model) .. " test " .. correct .. "/" .. m
    end
    lines[#lines + 1] = "ovo"
    for i, pair in ipairs(M.pairs) do
        local model, correct, count = models.ovo_models[i], 0, 0
        for j, example in ipairs(testing) do
            if example.label == pair[1] or example.label == pair[2] then
                count = count + 1
                if sign(test_results[j].ovo_values[i]) == (example.label == pair[1] and 1 or -1) then correct = correct + 1 end
            end
        end
        lines[#lines + 1] = "model " .. pair[1] .. "-" .. pair[2] .. " examples " .. #model.points .. " positives " .. positives(model) .. " " .. support_text(model) .. " b " .. f(model.b, 6) .. " " .. run_info(model) .. " test " .. correct .. "/" .. count
    end
    lines[#lines + 1] = "predictions"
    for i, example in ipairs(testing) do
        local result = test_results[i]
        lines[#lines + 1] = example.id .. " class " .. example.label .. " ovr " .. table.concat(map(result.ovr_values, function(value) return f(value) end), " ") .. " pred " .. result.ovr
            .. " ovo " .. table.concat(map(result.ovo_values, function(value) return f(value) end), " ") .. " votes " .. table.concat(result.votes, " ") .. " pred " .. result.ovo
    end
    append(lines, { multiclass_summary("train", training, train_results), multiclass_summary("test", testing, test_results), "confusion ovr" })
    append(lines, E.confusion_lines(E.confusion(labels(testing), map(test_results, function(result) return result.ovr end))))
    lines[#lines + 1] = "confusion ovo"
    append(lines, E.confusion_lines(E.confusion(labels(testing), map(test_results, function(result) return result.ovo end))))
    return lines
end
local function framed(cells, width, height)
    local border = "+" .. string.rep("-", width) .. "+"
    local lines = { border }
    for row = 0, height - 1 do lines[#lines + 1] = "|" .. table.concat(cells, "", row * width + 1, (row + 1) * width) .. "|" end
    lines[#lines + 1] = border
    return lines
end
local function decision_plots(training, multi_training, finals, selected, a, b, multi, settings)
    local width, height = table.unpack(settings.plot_size)
    local xmin, xmax = table.unpack(settings.plot_x)
    local ymin, ymax = table.unpack(settings.plot_y)
    local dx, dy, cell_count = (xmax - xmin) / width, (ymax - ymin) / height, width * height
    local model, binary, probability_cells, multicells, signs, levels = finals[selected.kernel_index].model, {}, {}, {}, {}, {}
    for i = 1, #finals do signs[i] = {} end
    for i = 0, 9 do levels[i + 1] = 0 end
    for row = 0, height - 1 do
        for column = 0, width - 1 do
            local point = { xmin + (column + 0.5) * dx, ymax - (row + 0.5) * dy }
            local values = map(finals, function(result) return result.model:decision(point) end)
            local value, character = values[selected.kernel_index]
            if value >= 1 then character = "+" elseif value > 0 then character = "." elseif value > -1 then character = "-" else character = " " end
            binary[#binary + 1] = character
            local level = math.min(9, math.floor(probability(value, a, b) * 10))
            probability_cells[#probability_cells + 1], levels[level + 1] = tostring(level), levels[level + 1] + 1
            for i, value_at_point in ipairs(values) do signs[i][#signs[i] + 1] = sign(value_at_point) end
            local result = multi:classify(point)
            multicells[#multicells + 1] = result.ovr ~= result.ovo and "?" or ({ " ", ".", ":" })[result.ovr]
        end
    end
    local function cell(point)
        local c, r = math.floor((point[1] - xmin) / dx), math.floor((ymax - point[2]) / dy)
        if c >= 0 and c < width and r >= 0 and r < height then return r * width + c + 1 end
    end
    local assignments, binary_outside, binary_points = {}, 0, 0
    for i, example in ipairs(training) do
        local position = cell(example.point)
        if not position then binary_outside = binary_outside + 1
        elseif not assignments[position] or model.alpha[i] > 0 and model.alpha[assignments[position]] <= 0 then assignments[position] = i end
    end
    for position, i in pairs(assignments) do
        binary_points = binary_points + 1
        local support = model.alpha[i] > 0
        binary[position] = training[i].label == 1 and (support and "X" or "x") or (support and "O" or "o")
    end
    local multi_assignments, multi_outside, multi_points = {}, 0, 0
    for i, example in ipairs(multi_training) do
        local position = cell(example.point)
        if not position then multi_outside = multi_outside + 1 elseif not multi_assignments[position] then multi_assignments[position] = i end
    end
    for position, i in pairs(multi_assignments) do multi_points, multicells[position] = multi_points + 1, tostring(multi_training[i].label) end
    local function count(cells, character)
        local total = 0
        for _, value in ipairs(cells) do if value == character then total = total + 1 end end
        return total
    end
    local lines = {
        "binary " .. model.kernel.name .. " C " .. f(model.C), "x " .. f(xmin) .. " " .. f(xmax) .. " y " .. f(ymin) .. " " .. f(ymax) .. " grid " .. width .. "x" .. height
    }
    append(lines, framed(binary, width, height))
    append(lines, {
        string.format("cells outer_positive %d inner_positive %d inner_negative %d outer_negative %d points %d outside %d", count(binary, "+"), count(binary, "."), count(binary, "-"), count(binary, " "), binary_points, binary_outside),
        "", "probability " .. model.kernel.name .. " A " .. f(a, 6) .. " B " .. f(b, 6)
    })
    append(lines, framed(probability_cells, width, height))
    append(lines, { "levels " .. table.concat(levels, " "), "", "grid_agreement" })
    for i = 1, #finals do
        for j = i + 1, #finals do
            local agreement = 0
            for cell_index = 1, cell_count do if signs[i][cell_index] == signs[j][cell_index] then agreement = agreement + 1 end end
            lines[#lines + 1] = finals[i].model.kernel.name .. " " .. finals[j].model.kernel.name .. " " .. agreement .. "/" .. cell_count .. " positive " .. count(signs[i], 1) .. " " .. count(signs[j], 1)
        end
    end
    append(lines, { "", "multiclass " .. multi.kernel.name .. " C " .. f(multi.C) })
    append(lines, framed(multicells, width, height))
    lines[#lines + 1] = string.format("cells class1 %d class2 %d class3 %d disagree %d points %d outside %d", count(multicells, " "), count(multicells, "."), count(multicells, ":"), count(multicells, "?"), multi_points, multi_outside)
    return lines
end
local function cv_grid(combinations, folds, size)
    local header = { "kernel", "C" }
    for i = 1, folds do header[#header + 1] = "fold" .. i end
    append(header, { "correct", "accuracy", "support_vectors", "passes", "steps" })
    local lines = { table.concat(header, ",") }
    for _, result in ipairs(combinations) do
        local row = { result.kernel.name, f(result.C) }
        for _, fold in ipairs(result.folds) do row[#row + 1] = tostring(fold.correct) end
        append(row, { tostring(result.correct), ratio(result.correct, size), tostring(result.support), tostring(result.passes), tostring(result.steps) })
        lines[#lines + 1] = table.concat(row, ",")
    end
    return lines
end
local function predictions(testing, finals, selected, pegasos_values, probabilities)
    local header = { "id", "label" }
    for _, result in ipairs(finals) do header[#header + 1] = result.model.kernel.name end
    append(header, { "pegasos", "predicted", "probability" })
    local lines, selected_values = { table.concat(header, ",") }, finals[selected.kernel_index].test_values
    for i, example in ipairs(testing) do
        local row = { example.id, tostring(example.label) }
        for _, result in ipairs(finals) do row[#row + 1] = f(result.test_values[i]) end
        append(row, { f(pegasos_values[i]), tostring(sign(selected_values[i])), f(probabilities[i]) })
        lines[#lines + 1] = table.concat(row, ",")
    end
    return lines
end
local training, testing, multi_training, multi_testing, settings = Dataset.read()
local matrices, combinations, best, selected, ranking = cross_validate(training, settings)
local all_points, all_labels, finals = points(training), labels(training), {}
for i, result in ipairs(best) do
    local model = S.train(all_points, all_labels, result.kernel, matrices[i], result.C, settings)
    finals[i] = final_evaluation(model, training, testing, settings.tolerance)
end
local selected_result, selected_matrix = finals[selected.kernel_index], matrices[selected.kernel_index]
local sections = { cross_validation_lines(#training, settings.folds, best, selected, ranking) }
for _, result in ipairs(finals) do sections[#sections + 1] = result.lines end
sections[#sections + 1] = training_log(selected_result.model)
sections[#sections + 1] = c_path(training, testing, selected, selected_matrix, settings)
sections[#sections + 1] = learning_curve(training, testing, selected, selected_matrix, settings)
local a, b, probabilities, calibration_lines = calibrate(training, testing, selected, selected_result.test_values, settings.newton_iterations)
sections[#sections + 1] = calibration_lines
local comparison
for _, result in ipairs(finals) do if result.model.kernel.kind == "linear" then comparison = result; break end end
local pegasos_values, pegasos_lines = pegasos(training, testing, settings.pegasos, comparison)
sections[#sections + 1] = pegasos_lines
sections[#sections + 1] = mcnemar(testing, finals, pegasos_values)
local multi_kernel
for _, kernel in ipairs(settings.kernels) do if kernel.name == settings.multiclass[1] then multi_kernel = kernel; break end end
local multi = M.new(multi_training, multi_kernel, settings.multiclass[2], settings)
local model_lines = {}
for _, section in ipairs(sections) do if #model_lines > 0 then model_lines[#model_lines + 1] = "" end; append(model_lines, section) end
E.write("output/model.txt", model_lines)
E.write("output/cv_grid.csv", cv_grid(combinations, settings.folds, #training))
E.write("output/predictions.csv", predictions(testing, finals, selected, pegasos_values, probabilities))
E.write("output/multiclass.txt", multiclass_report(multi_training, multi_testing, multi))
E.write("output/decision_plot.txt", decision_plots(training, multi_training, finals, selected, a, b, multi, settings))
