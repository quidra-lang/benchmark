local dataset = require("dataset")
local stumps = require("stumps")
local adaboost = require("adaboost")
local variants = require("variants")
local evaluation = require("evaluation")
local real, ratio = evaluation.real, evaluation.ratio
local Generator = {}
Generator.__index = Generator
local function generator(seed)
    return setmetatable({state = seed}, Generator)
end
function Generator:draw()
    self.state = 48271 * self.state % 2147483647
    return self.state
end
local function append(destination, source)
    for _, value in ipairs(source) do
        destination[#destination + 1] = value
    end
end
local function sum(values)
    local result = 0.0
    for _, value in ipairs(values) do
        result = result + value
    end
    return result
end
local function reals(values)
    local fields = {}
    for _, value in ipairs(values) do
        fields[#fields + 1] = real(value)
    end
    return table.concat(fields, " ")
end
local function labels(rows)
    local result = {}
    for i, row in ipairs(rows) do
        result[i] = row.label
    end
    return result
end
local function argmax(values)
    local result = 1
    for i = 2, #values do
        if values[i] > values[result] then
            result = i
        end
    end
    return result
end
local function sorted_indices(values, descending)
    local result = {}
    for i = 1, #values do
        result[i] = i
    end
    table.sort(result, function(a, b)
        if values[a] ~= values[b] then
            if descending then
                return values[a] > values[b]
            end
            return values[a] < values[b]
        end
        return a < b
    end)
    return result
end
local function magnitude(round)
    local result = 0.0
    for _, value in ipairs(round.stump.values) do
        result = math.max(result, math.abs(value))
    end
    return result
end
local function score_values(model, values, limit)
    local result = 0.0
    for t = 1, math.min(limit or #model.rounds, #model.rounds) do
        result = result + stumps.output(model.rounds[t].stump, values)
    end
    return result
end
local function scores(model, rows, limit)
    local result = {}
    for i, row in ipairs(rows) do
        result[i] = score_values(model, row.values, limit)
    end
    return result
end
local function error_count(rows, values)
    local result = 0
    for i, row in ipairs(rows) do
        result = result + (evaluation.sign(values[i]) ~= row.label and 1 or 0)
    end
    return result
end
local function loss(rows, values, logit)
    local total = 0.0
    for i, row in ipairs(rows) do
        if logit then
            total = total + math.log(1.0 + math.exp(-2.0 * row.label * values[i]))
        else
            total = total + math.exp(-row.label * values[i])
        end
    end
    return total / #rows
end
local function train(variant, rows, params)
    if variant == "discrete" then
        return adaboost.discrete(rows, params.rounds, 1.0)
    end
    return variants[variant](rows, params)
end
local function first_rounds(model, count)
    local result = {}
    for t = 1, math.min(count, #model.rounds) do
        result[t] = model.rounds[t]
    end
    return {rounds = result, stop = model.stop, cuts = model.cuts}
end
local function cross_validation(rows, params)
    local folds, errors = {}, {}
    for t = 1, params.rounds do
        errors[t] = 0
    end
    for fold = 1, params.folds do
        local validation = {}
        for i = 1, #rows do
            if (i - 1) % params.folds == fold - 1 then
                validation[#validation + 1] = i
            end
        end
        local training_count, weights = #rows - #validation, {}
        for i = 1, #rows do
            weights[i] = (i - 1) % params.folds == fold - 1 and 0.0 or 1.0 / training_count
        end
        local model = adaboost.discrete(rows, params.rounds, 1.0, weights)
        local fold_errors = {}
        for t = 1, params.rounds do
            local count = 0
            for _, i in ipairs(validation) do
                count = count + (evaluation.sign(score_values(model, rows[i].values, t)) ~= rows[i].label and 1 or 0)
            end
            fold_errors[t], errors[t] = count, errors[t] + count
        end
        folds[fold] = {model = model, training_count = training_count, validation = validation, errors = fold_errors}
    end
    local selected = 1
    for t = 2, params.rounds do
        if errors[t] < errors[selected] then
            selected = t
        end
    end
    local out_of_fold = {}
    for i, row in ipairs(rows) do
        out_of_fold[i] = score_values(folds[(i - 1) % params.folds + 1].model, row.values, selected)
    end
    return {folds = folds, errors = errors, selected = selected, scores = out_of_fold}
end
local function curve(model, training, testing, logit)
    local result, training_scores, testing_scores, scale = {}, {}, {}, 0.0
    for i = 1, #training do
        training_scores[i] = 0.0
    end
    for i = 1, #testing do
        testing_scores[i] = 0.0
    end
    for _, round in ipairs(model.rounds) do
        scale = scale + magnitude(round)
        local minimum
        for i, row in ipairs(training) do
            training_scores[i] = training_scores[i] + stumps.output(round.stump, row.values)
            local margin = row.label * training_scores[i]
            minimum = minimum == nil and margin or math.min(minimum, margin)
        end
        for i, row in ipairs(testing) do
            testing_scores[i] = testing_scores[i] + stumps.output(round.stump, row.values)
        end
        result[#result + 1] = {training_errors = error_count(training, training_scores), testing_errors = error_count(testing, testing_scores),
            training_loss = loss(training, training_scores, logit), testing_loss = loss(testing, testing_scores, logit), minimum = minimum / scale}
    end
    return result
end
local function curve_minimum(values, key)
    local result = 1
    for i = 2, #values do
        if values[i][key] < values[result][key] then
            result = i
        end
    end
    return values[result][key], result
end
local function metrics_line(kind, variant, rounds, rows, values, logit)
    local tp, fp, tn, fn = 0, 0, 0, 0
    for i, row in ipairs(rows) do
        local predicted = evaluation.sign(values[i])
        if predicted == 1 then
            if row.label == 1 then
                tp = tp + 1
            else
                fp = fp + 1
            end
        elseif row.label == -1 then
            tn = tn + 1
        else
            fn = fn + 1
        end
    end
    local first, second = evaluation.auc(labels(rows), values)
    return kind .. " " .. variant .. " rounds " .. rounds .. " correct " .. tp + tn .. "/" .. #rows ..
        " accuracy " .. ratio(tp + tn, #rows) .. " tp " .. tp .. " fp " .. fp .. " tn " .. tn .. " fn " .. fn ..
        " precision " .. ratio(tp, tp + fp) .. " recall " .. ratio(tp, tp + fn) .. " f1 " .. ratio(2 * tp, 2 * tp + fp + fn) ..
        " auc " .. ratio(first, second) .. " loss " .. real(loss(rows, values, logit))
end
local function importance(model, features, samme)
    local values, counts = {}, {}
    for j = 1, features do
        values[j], counts[j] = 0.0, 0
    end
    for _, round in ipairs(model.rounds) do
        local j = round.stump.feature
        values[j] = values[j] + (samme and round.alpha or magnitude(round))
        counts[j] = counts[j] + 1
    end
    return {values = values, counts = counts, total = sum(values), order = sorted_indices(values, true)}
end
local function importance_lines(item, names)
    local result = {"importance"}
    for rank, j in ipairs(item.order) do
        result[#result + 1] = rank .. " " .. names[j] .. " score " .. real(item.values[j]) ..
            " share " .. real(item.values[j] / item.total) .. " rounds " .. item.counts[j]
    end
    return result
end
local function permutation_importance(model, rows, params, random)
    local base = #rows - error_count(rows, scores(model, rows))
    local drops, minimum, maximum = {}, {}, {}
    for j = 1, #rows[1].values do
        local drop, low, high = 0, nil, nil
        for _ = 1, params.permutation_repeats do
            local order = {}
            for i = 1, #rows do
                order[i] = i
            end
            for i = #rows, 2, -1 do
                local other = random:draw() % i + 1
                order[i], order[other] = order[other], order[i]
            end
            local correct = 0
            for i, row in ipairs(rows) do
                local values = {table.unpack(row.values)}
                values[j] = rows[order[i]].values[j]
                correct = correct + (evaluation.sign(score_values(model, values)) == row.label and 1 or 0)
            end
            drop = drop + base - correct
            low = low == nil and correct or math.min(low, correct)
            high = high == nil and correct or math.max(high, correct)
        end
        drops[j], minimum[j], maximum[j] = drop, low, high
    end
    return {base = base, drops = drops, minimum = minimum, maximum = maximum, order = sorted_indices(drops, true)}
end
local function profile(variant, full, final, data, random)
    local training_scores, testing_scores = scores(final, data.training), scores(final, data.testing)
    local scale = 0.0
    for _, round in ipairs(final.rounds) do
        scale = scale + magnitude(round)
    end
    local training_margins, testing_margins = {}, {}
    for i, row in ipairs(data.training) do
        training_margins[i] = row.label * training_scores[i] / scale
    end
    for i, row in ipairs(data.testing) do
        testing_margins[i] = row.label * testing_scores[i] / scale
    end
    local item = {variant = variant, full = full, final = final, scale = scale, training_scores = training_scores,
        testing_scores = testing_scores, training_margins = training_margins, testing_margins = testing_margins,
        curve = curve(full, data.training, data.testing, variant == "logit"), importance = importance(final, #data.features, false)}
    item.permutation = permutation_importance(final, data.testing, data.params, random)
    return item
end
local function ensemble_report(data, profiles, cv)
    local params, lines = data.params, {}
    for v, item in ipairs(profiles) do
        if v > 1 then
            lines[#lines + 1] = ""
        end
        local variant, model = item.variant, item.full
        local header = "variant " .. variant .. " rounds " .. #model.rounds .. " stop " .. model.stop
        if variant == "real" then
            header = header .. " bins " .. params.bins .. " smoothing " .. real(params.smoothing) .. " convergence " .. real(params.convergence, 6)
        elseif variant == "logit" then
            header = header .. " clip " .. real(params.clip)
        end
        lines[#lines + 1] = header
        if variant == "real" then
            for j, cuts in ipairs(model.cuts) do
                lines[#lines + 1] = "cuts " .. data.features[j] .. " " .. reals(cuts)
            end
        end
        for t, round in ipairs(model.rounds) do
            local stump = round.stump
            local line = "round " .. t .. " feature " .. data.features[stump.feature]
            if variant == "discrete" then
                line = line .. " threshold " .. real(stump.thresholds[1]) .. " polarity " .. round.polarity .. " error " .. real(round.error) ..
                    " alpha " .. real(round.alpha) .. " z " .. real(round.z) .. " bound " .. real(round.bound)
            elseif variant == "real" then
                line = line .. " z " .. real(round.z) .. " bound " .. real(round.bound) .. " values " .. reals(stump.values)
            else
                line = line .. " threshold " .. real(stump.thresholds[1]) .. " left " .. real(stump.values[1]) ..
                    " right " .. real(stump.values[2]) .. " error " .. real(round.error)
                if variant == "logit" then
                    line = line .. " loss " .. real(round.loss)
                end
            end
            lines[#lines + 1] = line
            if variant == "discrete" then
                local maximum, squares = 1, 0.0
                for i, weight in ipairs(round.weights) do
                    if weight > round.weights[maximum] then
                        maximum = i
                    end
                    squares = squares + weight * weight
                end
                lines[#lines + 1] = "weights " .. t .. " max " .. real(round.weights[maximum], 6) ..
                    " id " .. data.training[maximum].id .. " ess " .. real(1.0 / squares)
            end
        end
        if variant == "discrete" then
            lines[#lines + 1] = "cv folds " .. params.folds .. " selected " .. cv.selected .. " errors " .. cv.errors[cv.selected] .. "/" .. #data.training
            for fold, result in ipairs(cv.folds) do
                lines[#lines + 1] = "fold " .. fold .. " train " .. result.training_count .. " validation " .. #result.validation ..
                    " rounds " .. #result.model.rounds .. " stop " .. result.model.stop .. " selected " .. result.errors[cv.selected] ..
                    "/" .. #result.validation .. " final " .. result.errors[params.rounds] .. "/" .. #result.validation
            end
            lines[#lines + 1] = "cv_errors " .. table.concat(cv.errors, " ")
        end
    end
    return lines
end
local function predictions_report(data, profiles)
    local lines = {"id,variant,score,label," .. table.concat(data.features, ",")}
    for i, row in ipairs(data.testing) do
        for _, item in ipairs(profiles) do
            local contributions = {}
            for j = 1, #data.features do
                contributions[j] = 0.0
            end
            for _, round in ipairs(item.final.rounds) do
                local j = round.stump.feature
                contributions[j] = contributions[j] + stumps.output(round.stump, row.values)
            end
            local fields = {row.id, item.variant, real(item.testing_scores[i]), evaluation.sign(item.testing_scores[i])}
            for _, value in ipairs(contributions) do
                fields[#fields + 1] = real(value)
            end
            lines[#lines + 1] = table.concat(fields, ",")
        end
    end
    return lines
end
local function roc_report(data, profiles)
    local lines = {"variant,threshold,tp,fp"}
    for _, item in ipairs(profiles) do
        local seen, thresholds = {}, {}
        for _, value in ipairs(item.testing_scores) do
            if not seen[value] then
                seen[value] = true
                thresholds[#thresholds + 1] = value
            end
        end
        table.sort(thresholds, function(a, b) return a > b end)
        for _, threshold in ipairs(thresholds) do
            local tp, fp = 0, 0
            for i, row in ipairs(data.testing) do
                if item.testing_scores[i] >= threshold then
                    if row.label == 1 then
                        tp = tp + 1
                    else
                        fp = fp + 1
                    end
                end
            end
            lines[#lines + 1] = table.concat({item.variant, real(threshold), tp, fp}, ",")
        end
    end
    return lines
end
local function margins_report(data, profiles)
    local lines, params = {}, data.params
    for v, item in ipairs(profiles) do
        if v > 1 then
            lines[#lines + 1] = ""
        end
        lines[#lines + 1] = "variant " .. item.variant .. " rounds " .. #item.final.rounds .. " scale " .. real(item.scale)
        local training, testing = item.training_margins, item.testing_margins
        lines[#lines + 1] = "train min " .. real(math.min(table.unpack(training))) .. " mean " .. real(sum(training) / #training)
        for _, threshold in ipairs(params.margins) do
            local count = evaluation.count_margin(training, threshold)
            lines[#lines + 1] = "train le " .. real(threshold) .. " " .. count .. "/" .. #training .. " " .. ratio(count, #training)
        end
        local histogram = {}
        for bin = 1, 20 do
            histogram[bin] = 0
        end
        for _, value in ipairs(training) do
            local bin = math.min(19, math.floor((value + 1.0) * 10.0)) + 1
            histogram[bin] = histogram[bin] + 1
        end
        lines[#lines + 1] = "histogram " .. table.concat(histogram, " ")
        local order = sorted_indices(training, false)
        for rank = 1, 5 do
            local i = order[rank]
            lines[#lines + 1] = "hardest " .. data.training[i].id .. " label " .. data.training[i].label .. " margin " .. real(training[i])
        end
        lines[#lines + 1] = "test min " .. real(math.min(table.unpack(testing))) .. " mean " .. real(sum(testing) / #testing)
        for _, threshold in ipairs(params.margins) do
            local count = evaluation.count_margin(testing, threshold)
            lines[#lines + 1] = "test le " .. real(threshold) .. " " .. count .. "/" .. #testing .. " " .. ratio(count, #testing)
        end
        for _, threshold in ipairs(params.margins) do
            local count, correct = 0, 0
            for i, value in ipairs(testing) do
                if math.abs(value) > threshold then
                    count = count + 1
                    correct = correct + (evaluation.sign(item.testing_scores[i]) == data.testing[i].label and 1 or 0)
                end
            end
            lines[#lines + 1] = "test confident " .. real(threshold) .. " " .. count .. "/" .. #testing ..
                " correct " .. correct .. "/" .. count .. " " .. ratio(correct, count)
        end
        append(lines, importance_lines(item.importance, data.features))
        lines[#lines + 1] = "permutation repeats " .. params.permutation_repeats .. " base " .. item.permutation.base .. "/" .. #testing
        for rank, j in ipairs(item.permutation.order) do
            lines[#lines + 1] = rank .. " " .. data.features[j] .. " drop " .. ratio(item.permutation.drops[j], params.permutation_repeats * #testing) ..
                " min " .. item.permutation.minimum[j] .. "/" .. #testing .. " max " .. item.permutation.maximum[j] .. "/" .. #testing
        end
    end
    return lines
end
local function shapes_report(data, profiles)
    local lines = {}
    for v, item in ipairs(profiles) do
        if v > 1 then
            lines[#lines + 1] = ""
        end
        lines[#lines + 1] = "variant " .. item.variant .. " rounds " .. #item.final.rounds
        for j, feature in ipairs(data.features) do
            local rounds, cuts, seen = {}, {}, {}
            for _, round in ipairs(item.final.rounds) do
                if round.stump.feature == j then
                    rounds[#rounds + 1] = round
                    for _, threshold in ipairs(round.stump.thresholds) do
                        if not seen[threshold] then
                            seen[threshold] = true
                            cuts[#cuts + 1] = threshold
                        end
                    end
                end
            end
            table.sort(cuts)
            local values = {}
            for interval = 0, #cuts do
                local total = 0.0
                for _, round in ipairs(rounds) do
                    local bin = 1
                    if interval > 0 then
                        for _, threshold in ipairs(round.stump.thresholds) do
                            if threshold <= cuts[interval] then
                                bin = bin + 1
                            end
                        end
                    end
                    total = total + round.stump.values[bin]
                end
                values[interval + 1] = total
            end
            local range = math.max(table.unpack(values)) - math.min(table.unpack(values))
            lines[#lines + 1] = "feature " .. feature .. " rounds " .. #rounds .. " cuts " .. #cuts .. " range " .. real(range)
            for interval = 0, #cuts do
                local first = interval == 0 and "-inf" or real(cuts[interval])
                local last = interval == #cuts and "inf" or real(cuts[interval + 1])
                lines[#lines + 1] = "interval " .. first .. " " .. last .. " value " .. real(values[interval + 1])
            end
        end
    end
    return lines
end
local function feature_summary(rows, j)
    local minimum, maximum, total, distinct = rows[1].values[j], rows[1].values[j], 0.0, {}
    for _, row in ipairs(rows) do
        local value = row.values[j]
        minimum, maximum = math.min(minimum, value), math.max(maximum, value)
        total, distinct[value] = total + value, true
    end
    local count = 0
    for _ in pairs(distinct) do
        count = count + 1
    end
    return reals({minimum, maximum, total / #rows}) .. " " .. count
end
local function bootstrap_lines(data, profiles)
    local params, random, counts = data.params, generator(data.params.bootstrap_seed), {}
    for v = 1, #profiles do
        counts[v] = {}
    end
    for sample = 1, params.bootstrap_count do
        local selected = {}
        for i = 1, #data.testing do
            selected[i] = random:draw() % #data.testing + 1
        end
        for v, item in ipairs(profiles) do
            local correct = 0
            for _, i in ipairs(selected) do
                correct = correct + (evaluation.sign(item.testing_scores[i]) == data.testing[i].label and 1 or 0)
            end
            counts[v][sample] = correct
        end
    end
    local lines = {"bootstrap samples " .. params.bootstrap_count .. " seed " .. params.bootstrap_seed}
    local tail = params.bootstrap_count // 40
    for v, item in ipairs(profiles) do
        local ordered, total = {table.unpack(counts[v])}, 0
        table.sort(ordered)
        for _, value in ipairs(counts[v]) do
            total = total + value
        end
        lines[#lines + 1] = item.variant .. " mean " .. ratio(total, params.bootstrap_count * #data.testing) ..
            " low " .. ratio(ordered[tail + 1], #data.testing) .. " high " .. ratio(ordered[params.bootstrap_count - tail], #data.testing)
    end
    for a = 1, #profiles - 1 do
        for b = a + 1, #profiles do
            local first, tie, second = 0, 0, 0
            for sample = 1, params.bootstrap_count do
                if counts[a][sample] > counts[b][sample] then
                    first = first + 1
                elseif counts[a][sample] == counts[b][sample] then
                    tie = tie + 1
                else
                    second = second + 1
                end
            end
            lines[#lines + 1] = profiles[a].variant .. " " .. profiles[b].variant .. " first " .. first .. " tie " .. tie .. " second " .. second
        end
    end
    return lines
end
local function calibration_lines(data, profiles)
    local lines, ranges = {}, {"0.0-0.2", "0.2-0.4", "0.4-0.6", "0.6-0.8", "0.8-1.0"}
    for _, item in ipairs(profiles) do
        local counts, totals, positives, brier = {}, {}, {}, 0.0
        for bin = 1, 5 do
            counts[bin], totals[bin], positives[bin] = 0, 0.0, 0
        end
        for i, row in ipairs(data.testing) do
            local p = 1.0 / (1.0 + math.exp(-2.0 * item.testing_scores[i]))
            local target = row.label == 1 and 1.0 or 0.0
            brier = brier + (p - target) * (p - target)
            local bin = math.min(4, math.floor(p * 5.0)) + 1
            counts[bin], totals[bin] = counts[bin] + 1, totals[bin] + p
            positives[bin] = positives[bin] + (row.label == 1 and 1 or 0)
        end
        lines[#lines + 1] = "calibration " .. item.variant .. " brier " .. real(brier / #data.testing)
        for bin = 1, 5 do
            lines[#lines + 1] = "bin " .. ranges[bin] .. " count " .. counts[bin] .. " mean " .. ratio(totals[bin], counts[bin]) .. " positives " .. positives[bin]
        end
    end
    return lines
end
local function summary_report(data, profiles, cv)
    local train_positive, test_positive = 0, 0
    for _, row in ipairs(data.training) do
        train_positive = train_positive + (row.label == 1 and 1 or 0)
    end
    for _, row in ipairs(data.testing) do
        test_positive = test_positive + (row.label == 1 and 1 or 0)
    end
    local lines = {"data train " .. #data.training .. " test " .. #data.testing .. " features " .. #data.features .. " positives " .. train_positive .. " " .. test_positive}
    for j, feature in ipairs(data.features) do
        lines[#lines + 1] = "feature " .. feature .. " train " .. feature_summary(data.training, j) .. " test " .. feature_summary(data.testing, j)
    end
    lines[#lines + 1] = "cv selected " .. cv.selected .. " errors " .. cv.errors[cv.selected] .. "/" .. #data.training .. " rate " .. ratio(cv.errors[cv.selected], #data.training)
    lines[#lines + 1] = metrics_line("oof", "discrete", cv.selected, data.training, cv.scores, false)
    local committee_train, committee_test, total_rounds = {}, {}, 0
    for i = 1, #data.training do
        committee_train[i] = 0.0
    end
    for i = 1, #data.testing do
        committee_test[i] = 0.0
    end
    for _, item in ipairs(profiles) do
        lines[#lines + 1] = metrics_line("train", item.variant, #item.final.rounds, data.training, item.training_scores, item.variant == "logit")
        lines[#lines + 1] = metrics_line("test", item.variant, #item.final.rounds, data.testing, item.testing_scores, item.variant == "logit")
        total_rounds = total_rounds + #item.final.rounds
        for i = 1, #data.training do
            committee_train[i] = committee_train[i] + item.training_scores[i] / item.scale
        end
        for i = 1, #data.testing do
            committee_test[i] = committee_test[i] + item.testing_scores[i] / item.scale
        end
    end
    lines[#lines + 1] = metrics_line("train", "committee", total_rounds, data.training, committee_train, false)
    lines[#lines + 1] = metrics_line("test", "committee", total_rounds, data.testing, committee_test, false)
    for _, item in ipairs(profiles) do
        local train_min, train_at = curve_minimum(item.curve, "training_errors")
        local test_min, test_at = curve_minimum(item.curve, "testing_errors")
        lines[#lines + 1] = "curve " .. item.variant .. " rounds " .. #item.full.rounds .. " train_min " .. train_min .. "/" .. #data.training ..
            " at " .. train_at .. " test_min " .. test_min .. "/" .. #data.testing .. " at " .. test_at
    end
    local all_wrong = {}
    for i, row in ipairs(data.testing) do
        local wrong = true
        for _, item in ipairs(profiles) do
            wrong = wrong and evaluation.sign(item.testing_scores[i]) ~= row.label
        end
        if wrong then
            all_wrong[#all_wrong + 1] = row.id
        end
    end
    lines[#lines + 1] = "all_wrong " .. #all_wrong .. (#all_wrong > 0 and " " .. table.concat(all_wrong, " ") or "")
    lines[#lines + 1] = "agreement"
    for a = 1, #profiles - 1 do
        for b = a + 1, #profiles do
            local agree, first, second = 0, 0, 0
            for i, row in ipairs(data.testing) do
                local pa, pb = evaluation.sign(profiles[a].testing_scores[i]), evaluation.sign(profiles[b].testing_scores[i])
                agree = agree + (pa == pb and 1 or 0)
                first = first + (pa == row.label and pb ~= row.label and 1 or 0)
                second = second + (pb == row.label and pa ~= row.label and 1 or 0)
            end
            local difference = math.abs(first - second) - 1
            lines[#lines + 1] = profiles[a].variant .. " " .. profiles[b].variant .. " agree " .. agree .. "/" .. #data.testing ..
                " only_first " .. first .. " only_second " .. second .. " chi2 " .. ratio(difference * difference, first + second)
        end
    end
    append(lines, bootstrap_lines(data, profiles))
    append(lines, calibration_lines(data, profiles))
    return lines
end
local function samme_scores(model, values, classes, limit)
    local result = {}
    for class = 1, classes do
        result[class] = 0.0
    end
    for t = 1, math.min(limit or #model.rounds, #model.rounds) do
        local round = model.rounds[t]
        local class = stumps.output(round.stump, values)
        result[class] = result[class] + round.alpha
    end
    return result
end
local function multiclass_analysis(data)
    local params = data.params
    local model = adaboost.samme(data.multi_training, params.classes, params.samme_rounds)
    local ovr = {}
    for class = 1, params.classes do
        local rows = {}
        for i, row in ipairs(data.multi_training) do
            rows[i] = {id = row.id, values = row.values, label = row.label == class and 1 or -1}
        end
        ovr[class] = adaboost.discrete(rows, params.samme_rounds, 1.0)
    end
    local train_predictions, test_predictions, train_ovr, test_ovr, class_scores = {}, {}, {}, {}, {}
    for collection, rows in ipairs({data.multi_training, data.multi_testing}) do
        for i, row in ipairs(rows) do
            local values = samme_scores(model, row.values, params.classes)
            local binary = {}
            for class = 1, params.classes do
                binary[class] = score_values(ovr[class], row.values)
            end
            if collection == 1 then
                train_predictions[i], train_ovr[i] = argmax(values), argmax(binary)
            else
                test_predictions[i], test_ovr[i], class_scores[i] = argmax(values), argmax(binary), values
            end
        end
    end
    local progress = {}
    for t = 1, #model.rounds do
        local counts = {}
        for _, rows in ipairs({data.multi_training, data.multi_testing}) do
            local count = 0
            for _, row in ipairs(rows) do
                count = count + (argmax(samme_scores(model, row.values, params.classes, t)) ~= row.label and 1 or 0)
            end
            counts[#counts + 1] = count
        end
        progress[t] = counts
    end
    return {model = model, ovr = ovr, train_predictions = train_predictions, test_predictions = test_predictions,
        train_ovr = train_ovr, test_ovr = test_ovr, class_scores = class_scores, curve = progress}
end
local function class_errors(rows, predicted)
    local result = 0
    for i, row in ipairs(rows) do
        result = result + (row.label ~= predicted[i] and 1 or 0)
    end
    return result
end
local function confusion_lines(rows, predictions, classes)
    local matrix = evaluation.confusion(labels(rows), predictions, classes)
    local lines = {"confusion"}
    for _, row in ipairs(matrix) do
        lines[#lines + 1] = table.concat(row, " ")
    end
    for class = 1, classes do
        local row_total, column_total = 0, 0
        for other = 1, classes do
            row_total, column_total = row_total + matrix[class][other], column_total + matrix[other][class]
        end
        lines[#lines + 1] = "class " .. class .. " precision " .. ratio(matrix[class][class], column_total) .. " recall " .. ratio(matrix[class][class], row_total)
    end
    return lines
end
local function multiclass_evaluation(data, training, testing)
    local train_error, test_error = class_errors(data.multi_training, training), class_errors(data.multi_testing, testing)
    local lines = {"train errors " .. train_error .. "/" .. #data.multi_training .. " rate " .. ratio(train_error, #data.multi_training),
        "test errors " .. test_error .. "/" .. #data.multi_testing .. " rate " .. ratio(test_error, #data.multi_testing)}
    append(lines, confusion_lines(data.multi_testing, testing, data.params.classes))
    return lines
end
local function samme_report(data, multi)
    local params, model = data.params, multi.model
    local lines = {"samme classes " .. params.classes .. " train " .. #data.multi_training .. " test " .. #data.multi_testing .. " rounds " .. #model.rounds .. " stop " .. model.stop}
    for t, round in ipairs(model.rounds) do
        local stump = round.stump
        lines[#lines + 1] = "round " .. t .. " feature " .. data.multi_features[stump.feature] .. " threshold " .. real(stump.thresholds[1]) ..
            " left " .. stump.values[1] .. " right " .. stump.values[2] .. " error " .. real(round.error) .. " alpha " .. real(round.alpha)
    end
    append(lines, multiclass_evaluation(data, multi.train_predictions, multi.test_predictions))
    append(lines, importance_lines(importance(model, #data.multi_features, true), data.multi_features))
    append(lines, {"", "ovr classes " .. params.classes .. " rounds " .. params.samme_rounds})
    for class, binary in ipairs(multi.ovr) do
        local positive, train_error, test_error = 0, 0, 0
        for _, row in ipairs(data.multi_training) do
            local target = row.label == class and 1 or -1
            positive = positive + (row.label == class and 1 or 0)
            train_error = train_error + (evaluation.sign(score_values(binary, row.values)) ~= target and 1 or 0)
        end
        for _, row in ipairs(data.multi_testing) do
            local target = row.label == class and 1 or -1
            test_error = test_error + (evaluation.sign(score_values(binary, row.values)) ~= target and 1 or 0)
        end
        lines[#lines + 1] = "class " .. class .. " rounds " .. #binary.rounds .. " stop " .. binary.stop .. " positives " .. positive ..
            " train_errors " .. train_error .. "/" .. #data.multi_training .. " test_errors " .. test_error .. "/" .. #data.multi_testing
    end
    append(lines, multiclass_evaluation(data, multi.train_ovr, multi.test_ovr))
    local agree = 0
    for i = 1, #data.multi_testing do
        agree = agree + (multi.test_predictions[i] == multi.test_ovr[i] and 1 or 0)
    end
    append(lines, {"agreement " .. agree .. "/" .. #data.multi_testing, "", "predictions"})
    for i, row in ipairs(data.multi_testing) do
        lines[#lines + 1] = row.id .. " class " .. row.label .. " samme " .. multi.test_predictions[i] .. " ovr " .. multi.test_ovr[i] .. " scores " .. reals(multi.class_scores[i])
    end
    return lines
end
local function error_curve_report(data, profiles, multi)
    local lines = {"variant,round,train_error,test_error,train_loss,test_loss,min_margin"}
    for _, item in ipairs(profiles) do
        for t, value in ipairs(item.curve) do
            lines[#lines + 1] = table.concat({item.variant, t, ratio(value.training_errors, #data.training), ratio(value.testing_errors, #data.testing),
                real(value.training_loss), real(value.testing_loss), real(value.minimum)}, ",")
        end
    end
    for t, value in ipairs(multi.curve) do
        lines[#lines + 1] = table.concat({"samme", t, ratio(value[1], #data.multi_training), ratio(value[2], #data.multi_testing), "-", "-", "-"}, ",")
    end
    return lines
end
local function restrict_features(rows, features)
    local result = {}
    for i, row in ipairs(rows) do
        local values = {}
        for _, j in ipairs(features) do
            values[#values + 1] = row.values[j]
        end
        result[i] = {id = row.id, values = values, label = row.label}
    end
    return result
end
local function experiment_fields(model, training, testing)
    return "rounds " .. #model.rounds .. " stop " .. model.stop .. " train_errors " .. error_count(training, scores(model, training)) ..
        "/" .. #training .. " test_errors " .. error_count(testing, scores(model, testing)) .. "/" .. #testing
end
local function experiments_report(data, profiles, cv)
    local params, lines = data.params, {}
    for _, fraction in ipairs(params.sizes) do
        local count, rows = #data.training * fraction // 100, {}
        for i = 1, count do
            rows[i] = data.training[i]
        end
        lines[#lines + 1] = "size " .. fraction .. " rows " .. count
        for _, variant in ipairs(params.variants) do
            local model = train(variant, rows, params)
            lines[#lines + 1] = variant .. " " .. experiment_fields(model, rows, data.testing)
        end
    end
    for _, shrinkage in ipairs(params.shrinkage) do
        local model = adaboost.discrete(data.training, params.rounds, shrinkage)
        local minimum, at = curve_minimum(curve(model, data.training, data.testing, false), "testing_errors")
        lines[#lines + 1] = "shrinkage " .. real(shrinkage) .. " " .. experiment_fields(model, data.training, data.testing) ..
            " test_min " .. minimum .. "/" .. #data.testing .. " at " .. at
    end
    local discrete
    for _, item in ipairs(profiles) do
        if item.variant == "discrete" then
            discrete = item
            break
        end
    end
    for count = 1, #data.features do
        local features = {}
        for rank = 1, count do
            features[rank] = discrete.importance.order[rank]
        end
        table.sort(features)
        local names = {}
        for _, j in ipairs(features) do
            names[#names + 1] = data.features[j]
        end
        local training, testing = restrict_features(data.training, features), restrict_features(data.testing, features)
        local model = adaboost.discrete(training, cv.selected, 1.0)
        lines[#lines + 1] = "top " .. count .. " features " .. table.concat(names, " ") .. " rounds " .. #model.rounds ..
            " train_errors " .. error_count(training, scores(model, training)) .. "/" .. #training ..
            " test_errors " .. error_count(testing, scores(model, testing)) .. "/" .. #testing
    end
    for _, fraction in ipairs(params.noise) do
        local count = #data.training * fraction // 100
        local random, order, flipped = generator(params.noise_seed), {}, {}
        for i = 1, #data.training do
            order[i] = i
        end
        for i = 1, count do
            local other = random:draw() % (#data.training - i + 1) + i
            order[i], order[other] = order[other], order[i]
        end
        for i = 1, count do
            flipped[order[i]] = true
        end
        local training = {}
        for i, row in ipairs(data.training) do
            training[i] = {id = row.id, values = row.values, label = flipped[i] and -row.label or row.label}
        end
        lines[#lines + 1] = "noise " .. fraction .. " flipped " .. count
        for _, variant in ipairs(params.variants) do
            local model = train(variant, training, params)
            local minimum, at = curve_minimum(curve(model, training, data.testing, variant == "logit"), "testing_errors")
            local weight = 0.0
            for i = 1, #training do
                if flipped[i] then
                    weight = weight + model.rounds[#model.rounds].weights[i]
                end
            end
            lines[#lines + 1] = variant .. " " .. experiment_fields(model, training, data.testing) ..
                " test_min " .. minimum .. "/" .. #data.testing .. " at " .. at .. " flipped_weight " .. real(weight)
        end
    end
    return lines
end
local data = dataset.read()
local cv = cross_validation(data.training, data.params)
local random = generator(data.params.permutation_seed)
local profiles = {}
for _, variant in ipairs(data.params.variants) do
    local full = train(variant, data.training, data.params)
    local final = variant == "discrete" and first_rounds(full, cv.selected) or full
    profiles[#profiles + 1] = profile(variant, full, final, data, random)
end
local multi = multiclass_analysis(data)
evaluation.save("ensemble.txt", ensemble_report(data, profiles, cv))
evaluation.save("error_curve.csv", error_curve_report(data, profiles, multi))
evaluation.save("predictions.csv", predictions_report(data, profiles))
evaluation.save("roc.csv", roc_report(data, profiles))
evaluation.save("margins.txt", margins_report(data, profiles))
evaluation.save("shapes.txt", shapes_report(data, profiles))
evaluation.save("samme.txt", samme_report(data, multi))
evaluation.save("summary.txt", summary_report(data, profiles, cv))
evaluation.save("experiments.txt", experiments_report(data, profiles, cv))
