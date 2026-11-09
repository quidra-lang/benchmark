local D = require("dataset")
local N = require("network")
local O = require("optimizers")
local E = require("evaluation")
local real, ratio = E.real, E.ratio
local function append(a, b) for _, value in ipairs(b) do a[#a + 1] = value end end
local function copy(value) local result = {}; for key, item in pairs(value) do result[key] = item end; return result end
local function map(values, fn) local result = {}; for i, value in ipairs(values) do result[i] = fn(value, i) end; return result end
local function formatted(values, places) return table.concat(map(values, function(value) return real(value, places) end), " ") end
local function sequence(count) local result = {}; for i = 1, count do result[i] = i end; return result end
local function slice(values, first, last) local result = {}; for i = first, last do result[#result + 1] = values[i] end; return result end
local function integer_zeros(count) local result = {}; for i = 1, count do result[i] = 0 end; return result end
local function norm(values)
    local total = 0.0
    for _, value in ipairs(values) do total = total + value * value end
    return math.sqrt(total)
end
local function correct(outcome) return outcome.predicted == outcome.label end
local function gradient_checks(data, catalog, training)
    local settings, lines = data.settings, {}
    for _, architecture in ipairs(data.networks) do
        if #lines > 0 then lines[#lines + 1] = "" end
        local network, order = catalog[architecture.name], sequence(#training)
        D.generator(settings.seed):shuffle(order)
        local images = {}
        for i = 1, math.min(settings.batch_size, #training) do images[i] = training[order[i]] end
        local layout, theta = network.layout, N.copy(network.initial)
        local analytic = N.average_gradient(layout, theta, images)
        local checked, passed, count = {}, true, 0
        for p = 1, layout.parameters, settings.gradient_stride do
            local original, h = theta[p], 0.00001
            theta[p] = original + h
            local higher = N.evaluate(layout, theta, images).loss
            theta[p] = original - h
            local lower = N.evaluate(layout, theta, images).loss
            theta[p] = original
            local derivative = (higher - lower) / (2 * h)
            local error_value = math.abs(analytic[p] - derivative) / math.max(1, math.abs(analytic[p]) + math.abs(derivative))
            if error_value >= 0.000001 then passed = false end
            checked[p], count = true, count + 1
        end
        append(lines, { "network " .. architecture.name, "parameters " .. layout.parameters, "batch " .. table.concat(map(images, function(image) return image.id end), " ") })
        for i, layer in ipairs(layout.layers) do
            local weights, biases = 0, 0
            for p = layer.weight_start, layer.weight_finish do if checked[p] then weights = weights + 1 end end
            for p = layer.bias_start, layer.bias_finish do if checked[p] then biases = biases + 1 end end
            lines[#lines + 1] = string.format("layer %d weights %d biases %d", i, weights, biases)
        end
        append(lines, { "checked " .. count, "result " .. (passed and "PASS" or "FAIL") })
    end
    return lines
end
local function train_run(definition, network, training, validation, settings)
    local run, theta, layout = copy(definition), N.copy(network.initial), network.layout
    run.network_data, run.epochs, run.correctness, run.updates, run.stop = network, {}, {}, 0, "max_epochs"
    local state, generator, order, wait = O.initialize(#theta), D.generator(settings.seed), sequence(#training), 0
    for epoch = 1, settings.max_epochs do
        local rate = O.rate(run, epoch, settings.lr_step, settings.lr_gamma)
        generator:shuffle(order)
        local norms, batches = 0.0, 0
        for start = 1, #order, settings.batch_size do
            local images = {}
            for i = start, math.min(#order, start + settings.batch_size - 1) do images[#images + 1] = training[order[i]] end
            local grad = N.average_gradient(layout, theta, images)
            for p, is_weight in ipairs(layout.is_weight) do if is_weight then grad[p] = grad[p] + run.decay * theta[p] end end
            norms, batches = norms + norm(grad), batches + 1
            O.update(theta, grad, state, run, rate)
            run.updates = run.updates + 1
        end
        local train_eval, val_eval = N.evaluate(layout, theta, training), N.evaluate(layout, theta, validation)
        run.correctness[#run.correctness + 1] = map(train_eval.outcomes, correct)
        local improved = not run.best_epoch or val_eval.loss < run.best_val_loss
        if improved then run.best_epoch, run.best_val_loss, run.best_val_correct, run.best_theta, wait = epoch, val_eval.loss, val_eval.correct, N.copy(theta), 0
        else wait = wait + 1 end
        run.epochs[#run.epochs + 1] = { epoch = epoch, lr = rate, grad_norm = norms / batches, train_loss = train_eval.loss, train_correct = train_eval.correct,
            val_loss = val_eval.loss, val_correct = val_eval.correct, improved = improved }
        if wait >= settings.patience then run.stop = "early"; break end
    end
    return run
end
local function prepare_evaluation(run, training, test, settings)
    local network, theta = run.network_data, run.best_theta
    local architecture, layout = network.architecture, network.layout
    run.test = N.evaluate(layout, theta, test)
    local outcomes, classes = run.test.outcomes, architecture.classes
    run.confusion, run.top2 = E.confusion(outcomes, classes), 0
    local correct_sum, wrong_sum, correct_count, wrong_count = 0.0, 0.0, 0, 0
    run.misclassified = {}
    for _, outcome in ipairs(outcomes) do
        local first, second = E.best_two(outcome.scores)
        if outcome.label == first or outcome.label == second then run.top2 = run.top2 + 1 end
        if correct(outcome) then correct_sum, correct_count = correct_sum + outcome.confidence, correct_count + 1
        else wrong_sum, wrong_count = wrong_sum + outcome.confidence, wrong_count + 1; run.misclassified[#run.misclassified + 1] = outcome end
    end
    run.confidence_correct, run.confidence_wrong = correct_count > 0 and correct_sum / correct_count or nil, wrong_count > 0 and wrong_sum / wrong_count or nil
    local events, rows, never = 0, 0, 0
    for i = 1, #training do
        local count, learned = 0, false
        for epoch, statuses in ipairs(run.correctness) do
            if statuses[i] then learned = true end
            if epoch > 1 and run.correctness[epoch - 1][i] and not statuses[i] then count = count + 1 end
        end
        events = events + count
        if count > 0 then rows = rows + 1 end
        if not learned then never = never + 1 end
    end
    run.forgetting, run.weight_norms, run.weight_changes = { events = events, rows = rows, never = never }, {}, {}
    for i, layer in ipairs(layout.layers) do
        local weights, changes = {}, {}
        for p = layer.weight_start, layer.weight_finish do weights[#weights + 1], changes[#changes + 1] = theta[p], theta[p] - network.initial[p] end
        run.weight_norms[i], run.weight_changes[i] = norm(weights), norm(changes)
    end
    run.calibration, run.ece = {}, 0.0
    for i = 1, settings.calibration_bins do run.calibration[i] = { count = 0, correct = 0, sum = 0.0 } end
    for _, outcome in ipairs(outcomes) do
        local bucket = run.calibration[math.min(settings.calibration_bins - 1, math.floor(outcome.confidence * settings.calibration_bins)) + 1]
        bucket.count, bucket.sum = bucket.count + 1, bucket.sum + outcome.confidence
        if correct(outcome) then bucket.correct = bucket.correct + 1 end
    end
    for _, bucket in ipairs(run.calibration) do
        if bucket.count > 0 then run.ece = run.ece + bucket.count / #test * math.abs(bucket.correct / bucket.count - bucket.sum / bucket.count) end
    end
    run.hidden_summary = {}
    for i = 1, #layout.layers - 1 do
        local layer, means, zero_counts, counts = layout.layers[i], {}, integer_zeros(layout.layers[i].outputs), {}
        for class = 1, classes do means[class], counts[class] = N.zeros(layer.outputs), 0 end
        for _, outcome in ipairs(outcomes) do
            local class = outcome.label + 1
            counts[class] = counts[class] + 1
            for j, value in ipairs(outcome.hidden[i]) do
                means[class][j] = means[class][j] + value
                if value == 0 then zero_counts[j] = zero_counts[j] + 1 end
            end
        end
        for class = 1, classes do
            if counts[class] > 0 then for j = 1, layer.outputs do means[class][j] = means[class][j] / counts[class] end else means[class] = false end
        end
        local preferred = {}
        for j = 1, layer.outputs do
            local chosen
            for class = 1, classes do if means[class] and (not chosen or means[class][j] > means[chosen][j]) then chosen = class end end
            preferred[j] = chosen - 1
        end
        run.hidden_summary[i] = { means = means, preferred = preferred, zero_counts = zero_counts }
    end
    local ordered_weights = {}
    for p, weight in ipairs(layout.is_weight) do if weight then ordered_weights[#ordered_weights + 1] = p end end
    table.sort(ordered_weights, function(a, b) local x, y = math.abs(theta[a]), math.abs(theta[b]); return x < y or x == y and a < b end)
    run.pruning = {}
    for _, percent in ipairs(settings.prune) do
        local count, pruned = percent * #ordered_weights // 100, N.copy(theta)
        for i = 1, count do pruned[ordered_weights[i]] = 0.0 end
        local result = N.evaluate(layout, pruned, test)
        run.pruning[#run.pruning + 1] = { percent = percent, removed = count, correct = result.correct, loss = result.loss }
    end
    run.noise_results = {}
    for _, percent in ipairs(settings.noise) do
        local generator, altered, flipped = D.generator(settings.seed), {}, 0
        for i, image in ipairs(test) do
            local changed = copy(image)
            changed.vector = N.copy(image.vector)
            for p, value in ipairs(changed.vector) do if generator:draw() % 100 < percent then changed.vector[p], flipped = 1.0 - value, flipped + 1 end end
            altered[i] = changed
        end
        run.noise_results[#run.noise_results + 1] = { percent = percent, flipped = flipped, correct = N.evaluate(layout, theta, altered).correct }
    end
end
local function data_summary(training, validation, test, architecture)
    local width, height, classes = architecture.width, architecture.height, architecture.classes
    local size, maps, class_names = width * height, {}, {}
    local lines = { "data", string.format("train %d validation %d test %d pixels %d", #training, #validation, #test, width * height) }
    for class = 0, classes - 1 do
        local train_count, val_count, test_count, ink, counts = 0, 0, 0, 0, integer_zeros(size)
        for _, image in ipairs(training) do
            if image.label == class then
                train_count = train_count + 1
                for p = 1, size do if image.pixels:byte(p) == 49 then counts[p], ink = counts[p] + 1, ink + 1 end end
            end
        end
        for _, image in ipairs(validation) do if image.label == class then val_count = val_count + 1 end end
        for _, image in ipairs(test) do if image.label == class then test_count = test_count + 1 end end
        lines[#lines + 1] = string.format("class %d train %d validation %d test %d ink %s", class, train_count, val_count, test_count, ratio(ink, train_count))
        local levels = {}
        for p = 1, size do levels[p] = train_count > 0 and math.min(9, math.tointeger(10 * counts[p]) // train_count) or 0 end
        maps[class + 1], class_names[class + 1] = levels, tostring(class)
    end
    lines[#lines + 1] = "mean_images " .. table.concat(class_names, " ")
    append(lines, E.level_maps(maps, width, height))
    return lines
end
local function run_report(run, validation, test, settings)
    local network, outcomes, test_count = run.network_data, run.test.outcomes, #test
    local forgetting = run.forgetting
    local lines = {
        "run " .. run.name .. " network " .. run.network .. " optimizer " .. run.optimizer,
        string.format("epochs %d best_epoch %d stop %s updates %d", #run.epochs, run.best_epoch, run.stop, run.updates),
        "best_val_loss " .. real(run.best_val_loss, 6) .. " best_val_acc " .. ratio(run.best_val_correct, #validation) .. " correct " .. run.best_val_correct .. "/" .. #validation,
        "test_loss " .. real(run.test.loss, 6) .. " test_acc " .. ratio(run.test.correct, test_count) .. " correct " .. run.test.correct .. "/" .. test_count,
        "top2_acc " .. ratio(run.top2, test_count) .. " correct " .. run.top2 .. "/" .. test_count,
        "confidence correct " .. (run.confidence_correct and real(run.confidence_correct, 4) or "-") .. " wrong " .. (run.confidence_wrong and real(run.confidence_wrong, 4) or "-"),
        string.format("forgetting events %d rows %d never_learned %d", forgetting.events, forgetting.rows, forgetting.never),
        "weight_norms " .. formatted(run.weight_norms, 4), "weight_changes " .. formatted(run.weight_changes, 4), "curve"
    }
    local maximum = 0.0
    for _, epoch in ipairs(run.epochs) do maximum = math.max(maximum, epoch.train_loss, epoch.val_loss) end
    for _, epoch in ipairs(run.epochs) do
        local cells = {}; for i = 1, 40 do cells[i] = " " end
        local ct, cv = math.floor(39 * epoch.train_loss / maximum + 0.5) + 1, math.floor(39 * epoch.val_loss / maximum + 0.5) + 1
        cells[ct] = "t"
        cells[cv] = ct == cv and "*" or "v"
        lines[#lines + 1] = string.format("%2d |%s|%s", epoch.epoch, table.concat(cells), epoch.epoch == run.best_epoch and " best" or "")
    end
    lines[#lines + 1] = "confusion"
    for i, row in ipairs(run.confusion) do lines[#lines + 1] = (i - 1) .. ": " .. table.concat(row, " ") end
    for class = 0, network.architecture.classes - 1 do
        local support, predicted, precision, recall, f1 = E.class_measures(run.confusion, class)
        lines[#lines + 1] = string.format("class %d support %d predicted %d precision %s recall %s f1 %s", class, support, predicted, precision, recall, f1)
    end
    lines[#lines + 1] = "calibration"
    for i, bin in ipairs(run.calibration) do
        lines[#lines + 1] = "bin " .. i .. " " .. real((i - 1) / settings.calibration_bins, 2) .. " " .. real(i / settings.calibration_bins, 2) .. " count " .. bin.count
            .. " accuracy " .. ratio(bin.correct, bin.count) .. " confidence " .. (bin.count > 0 and real(bin.sum / bin.count, 4) or "-")
    end
    lines[#lines + 1] = "ece " .. real(run.ece, 4)
    for i, summary in ipairs(run.hidden_summary) do
        local layer = network.layout.layers[i]
        lines[#lines + 1] = "hidden " .. i .. " " .. layer.activation .. " units " .. layer.outputs
        for class, values in ipairs(summary.means) do lines[#lines + 1] = "class " .. (class - 1) .. " mean " .. (values and formatted(values, 4) or "-") end
        lines[#lines + 1] = "preferred " .. table.concat(summary.preferred, " ")
        if layer.activation == "RELU" then lines[#lines + 1] = "zero_counts " .. table.concat(summary.zero_counts, " ") end
    end
    lines[#lines + 1] = "pruning"
    for _, item in ipairs(run.pruning) do
        lines[#lines + 1] = string.format("prune %d removed %d correct %d test_acc %s test_loss %s", item.percent, item.removed, item.correct, ratio(item.correct, test_count), real(item.loss, 6))
    end
    lines[#lines + 1] = "noise"
    for _, item in ipairs(run.noise_results) do lines[#lines + 1] = string.format("noise %d correct %d test_acc %s", item.percent, item.correct, ratio(item.correct, test_count)) end
    local ids = map(run.misclassified, function(item) return item.id end)
    lines[#lines + 1] = "misclassified " .. #ids .. (#ids > 0 and " " .. table.concat(ids, " ") or "")
    return lines
end
local function comparison_report(runs, training, all_train, test, settings)
    local rank = N.copy(runs)
    table.sort(rank, function(a, b)
        if a.test.correct ~= b.test.correct then return a.test.correct > b.test.correct end
        if a.best_val_loss ~= b.best_val_loss then return a.best_val_loss < b.best_val_loss end
        return a.order < b.order
    end)
    local top, classes, count = rank[1], runs[1].network_data.architecture.classes, #test
    local majority, soft_predictions, soft_runs = {}, {}, {}
    for _, run in ipairs(runs) do local layers = run.network_data.layout.layers; if layers[#layers].activation == "SOFTMAX" then soft_runs[#soft_runs + 1] = run end end
    for i = 1, count do
        local votes = {}; for class = 1, classes do votes[class] = 0 end
        for _, run in ipairs(runs) do local class = run.test.outcomes[i].predicted + 1; votes[class] = votes[class] + 1 end
        local maximum = math.max(table.unpack(votes))
        for _, run in ipairs(rank) do local class = run.test.outcomes[i].predicted; if votes[class + 1] == maximum then majority[i] = class; break end end
        if #soft_runs > 0 then
            local scores = {}
            for class = 1, classes do
                local sum = 0.0
                for _, run in ipairs(soft_runs) do sum = sum + run.test.outcomes[i].scores[class] end
                scores[class] = sum / #soft_runs
            end
            soft_predictions[i] = E.best_two(scores)
        end
    end
    local lines = { "comparison" }
    for i, run in ipairs(rank) do
        lines[#lines + 1] = string.format("rank %d %s correct %d test_acc %s best_val_loss %s test_loss %s best_epoch %d epochs %d updates %d", i, run.name, run.test.correct,
            ratio(run.test.correct, count), real(run.best_val_loss, 6), real(run.test.loss, 6), run.best_epoch, #run.epochs, run.updates)
    end
    lines[#lines + 1] = "agreement"
    for _, a in ipairs(runs) do
        local agreements = {}
        for _, b in ipairs(runs) do
            local equal = 0
            for i = 1, count do if a.test.outcomes[i].predicted == b.test.outcomes[i].predicted then equal = equal + 1 end end
            agreements[#agreements + 1] = equal
        end
        lines[#lines + 1] = a.name .. " " .. table.concat(agreements, " ")
    end
    lines[#lines + 1] = "mcnemar " .. top.name
    for j = 2, #rank do
        local run, b, c = rank[j], 0, 0
        for i = 1, count do
            local first, second = correct(top.test.outcomes[i]), correct(run.test.outcomes[i])
            if first and not second then b = b + 1 elseif second and not first then c = c + 1 end
        end
        local difference, denominator = math.max(math.abs(b - c) - 1, 0), b + c
        local numerator = difference * difference
        lines[#lines + 1] = string.format("vs %s b %d c %d chi2 %s significant %s", run.name, b, c, denominator > 0 and ratio(numerator, denominator) or "0.0000", numerator * 1000 > 3841 * denominator and "yes" or "no")
    end
    local ensemble_correct, fixed, broken, soft_correct = 0, 0, 0, 0
    for i, image in ipairs(test) do
        local chosen, reference = majority[i] == image.label, correct(top.test.outcomes[i])
        if chosen then ensemble_correct = ensemble_correct + 1 end
        if chosen and not reference then fixed = fixed + 1 elseif reference and not chosen then broken = broken + 1 end
        if soft_predictions[i] == image.label then soft_correct = soft_correct + 1 end
    end
    lines[#lines + 1] = string.format("ensemble correct %d/%d test_acc %s fixed %d broken %d", ensemble_correct, count, ratio(ensemble_correct, count), fixed, broken)
    lines[#lines + 1] = #soft_runs > 0 and string.format("soft_ensemble runs %d correct %d/%d test_acc %s", #soft_runs, soft_correct, count, ratio(soft_correct, count)) or "soft_ensemble none"
    for i, percent in ipairs(settings.noise) do lines[#lines + 1] = "noise " .. percent .. " flipped " .. runs[1].noise_results[i].flipped end
    local confused = {}
    for y = 1, classes do
        for p = 1, classes do
            if y ~= p then
                local total = 0
                for _, run in ipairs(runs) do total = total + run.confusion[y][p] end
                if total > 0 then confused[#confused + 1] = { y = y - 1, p = p - 1, count = total } end
            end
        end
    end
    table.sort(confused, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        return a.y < b.y or a.y == b.y and a.p < b.p
    end)
    lines[#lines + 1] = "confused_pairs"
    for i = 1, math.min(5, #confused) do local pair = confused[i]; lines[#lines + 1] = string.format("%d as %d count %d", pair.y, pair.p, pair.count) end
    local network = top.network_data
    local architecture, layout = network.architecture, network.layout
    local size, maps, class_names = architecture.width * architecture.height, {}, {}
    for class = 0, classes - 1 do
        local values, chosen = N.zeros(size), 0
        for _, image in ipairs(test) do
            if image.label == class then
                chosen = chosen + 1
                local _, _, inputs = N.gradient(layout, top.best_theta, image, true)
                for p, value in ipairs(inputs) do values[p] = values[p] + math.abs(value) end
            end
        end
        if chosen > 0 then for p = 1, size do values[p] = values[p] / chosen end end
        local maximum = math.max(table.unpack(values))
        local levels = {}
        for p, value in ipairs(values) do levels[p] = maximum > 0 and math.min(9, math.floor(10 * value / maximum)) or 0 end
        maps[class + 1], class_names[class + 1] = levels, tostring(class)
    end
    append(lines, { "", "saliency " .. top.name, "classes " .. table.concat(class_names, " ") })
    append(lines, E.level_maps(maps, architecture.width, architecture.height))
    append(lines, { "", "hardest_training_examples " .. top.name })
    local train_outcomes = N.evaluate(layout, top.best_theta, training).outcomes
    local hardest = sequence(#training)
    table.sort(hardest, function(a, b) return train_outcomes[a].loss > train_outcomes[b].loss or train_outcomes[a].loss == train_outcomes[b].loss and a < b end)
    for i = 1, math.min(5, #hardest) do
        local p = hardest[i]
        lines[#lines + 1] = string.format("%s label %d predicted %d loss %s", training[p].id, training[p].label, train_outcomes[p].predicted, real(train_outcomes[p].loss, 6))
    end
    append(lines, { "", "misclassified_examples " .. top.name })
    for i, image in ipairs(test) do
        local outcome = top.test.outcomes[i]
        if not correct(outcome) then
            local nearest, distance
            for _, candidate in ipairs(all_train) do
                local d = 0
                for p = 1, #image.pixels do if image.pixels:byte(p) ~= candidate.pixels:byte(p) then d = d + 1 end end
                if not distance or d < distance then nearest, distance = candidate, d end
            end
            local predictions = map(runs, function(run) return run.test.outcomes[i].predicted end)
            lines[#lines + 1] = string.format("%s label %d predicted %d confidence %s true_score %s runs %s ensemble %d", image.id, image.label, outcome.predicted, real(outcome.confidence, 4), real(outcome.scores[image.label + 1], 4), table.concat(predictions, " "), majority[i])
            lines[#lines + 1] = string.format("nearest %s label %d distance %d", nearest.id, nearest.label, distance)
            append(lines, E.image(image.pixels, architecture.width))
        end
    end
    return lines
end
local function write(filename, lines)
    local output = assert(io.open("output/" .. filename, "w"))
    output:write(table.concat(lines, "\n"), "\n")
    output:close()
end
local data = D.read()
local split = #data.train - #data.train // 5
local training, validation, settings = slice(data.train, 1, split), slice(data.train, split + 1, #data.train), data.settings
local catalog = {}
for _, architecture in ipairs(data.networks) do catalog[architecture.name] = { architecture = architecture, layout = N.layout(architecture), initial = data.weights[architecture.name] } end
local checks = gradient_checks(data, catalog, training)
local runs = {}
for i, definition in ipairs(settings.runs) do
    local run = train_run(definition, catalog[definition.network], training, validation, settings)
    run.order = i
    prepare_evaluation(run, training, data.test, settings)
    runs[i] = run
end
local log_lines = { "run,epoch,lr,grad_norm,train_loss,train_acc,val_loss,val_acc,improved" }
local weight_lines, prediction_lines = {}, { "run,id,label,predicted,confidence" }
for i, run in ipairs(runs) do
    for _, epoch in ipairs(run.epochs) do
        log_lines[#log_lines + 1] = table.concat({ run.name, epoch.epoch, real(epoch.lr, 6), real(epoch.grad_norm, 4), real(epoch.train_loss, 6), ratio(epoch.train_correct, #training),
            real(epoch.val_loss, 6), ratio(epoch.val_correct, #validation), epoch.improved and "1" or "0" }, ",")
    end
    if i > 1 then weight_lines[#weight_lines + 1] = "" end
    weight_lines[#weight_lines + 1] = "RUN " .. run.name .. " NETWORK " .. run.network .. " EPOCH " .. run.best_epoch
    for number, layer in ipairs(run.network_data.layout.layers) do
        weight_lines[#weight_lines + 1] = string.format("LAYER %d %d %d", number, layer.outputs, layer.inputs)
        local position = layer.weight_start
        for _ = 1, layer.outputs do weight_lines[#weight_lines + 1] = "W " .. formatted(slice(run.best_theta, position, position + layer.inputs - 1), 4); position = position + layer.inputs end
        weight_lines[#weight_lines + 1] = "B " .. formatted(slice(run.best_theta, layer.bias_start, layer.bias_finish), 4)
    end
    for _, outcome in ipairs(run.test.outcomes) do prediction_lines[#prediction_lines + 1] = table.concat({ run.name, outcome.id, outcome.label, outcome.predicted, real(outcome.confidence, 4) }, ",") end
end
local evaluation_lines = data_summary(training, validation, data.test, data.networks[1])
evaluation_lines[#evaluation_lines + 1] = ""
for _, run in ipairs(runs) do append(evaluation_lines, run_report(run, validation, data.test, settings)); evaluation_lines[#evaluation_lines + 1] = "" end
append(evaluation_lines, comparison_report(runs, training, data.train, data.test, settings))
write("gradient_check.txt", checks)
write("training_log.csv", log_lines)
write("final_weights.txt", weight_lines)
write("predictions.csv", prediction_lines)
write("evaluation.txt", evaluation_lines)
