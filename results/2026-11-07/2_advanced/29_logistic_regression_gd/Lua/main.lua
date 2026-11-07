local dataset, logistic, optimizers, softmax, metrics = require("dataset"), require("logistic"), require("optimizers"), require("softmax"), require("metrics")
local fixed, ratio, fraction = metrics.fixed, metrics.ratio, metrics.fraction
local function map(values, operation)
    local result = {}
    for i, value in ipairs(values) do
        result[i] = operation(value, i)
    end
    return result
end
local function sum(values)
    local total = 0.0
    for _, value in ipairs(values) do
        total = total + value
    end
    return total
end
local function count_sum(values)
    local total = 0
    for _, value in ipairs(values) do
        total = total + value
    end
    return total
end
local function copy(values)
    return {table.unpack(values)}
end
local function slice(values, first, last)
    return {table.unpack(values, first, last or #values)}
end
local function append(destination, source)
    for _, value in ipairs(source) do
        destination[#destination + 1] = value
    end
end
local function length(values)
    return math.sqrt(sum(map(values, function(value)
        return value * value
    end)))
end
local function reals(values, places)
    return table.concat(map(values, function(value)
        return fixed(value, places)
    end), " ")
end
local function predict(probabilities, threshold)
    return map(probabilities, function(value)
        return value >= threshold and 1 or 0
    end)
end
local function count_equal(first, second)
    local count = 0
    for i, value in ipairs(first) do
        if value == second[i] then
            count = count + 1
        end
    end
    return count
end
local function ordering(values, descending)
    local order = {}
    for i = 1, #values do
        order[i] = i
    end
    table.sort(order, function(a, b)
        if values[a] == values[b] then
            return a < b
        end
        return descending and values[a] > values[b] or not descending and values[a] < values[b]
    end)
    return order
end
local function probabilities(weights, vectors)
    return map(vectors, function(vector)
        return logistic.probability(logistic.score(weights, vector))
    end)
end
local function last_weights(checkpoints)
    return checkpoints[#checkpoints].weights
end
local function auc_text(scores, targets)
    return fraction(metrics.auc(scores, targets))
end
local function inverse(matrix)
    local lower, result = optimizers.cholesky(matrix), {}
    for j = 1, #matrix do
        result[j] = {}
    end
    for k = 1, #matrix do
        local unit = map(matrix, function()
            return 0.0
        end)
        unit[k] = 1.0
        local column = optimizers.solve(lower, unit)
        for j = 1, #matrix do
            result[j][k] = column[j]
        end
    end
    return result
end
local names, train = dataset.read_examples("input/train.csv")
local _, test = dataset.read_examples("input/test.csv")
local settings = dataset.read_settings("input/params.txt")
local n, m, d = #train, #test, #names
local tuples = dataset.expansion_tuples(d, settings.degree)
local feature_names, p = dataset.expanded_names(names, tuples), #tuples
local train_expanded = map(train, function(example)
    return dataset.expanded_values(tuples, example.values)
end)
local test_expanded = map(test, function(example)
    return dataset.expanded_values(tuples, example.values)
end)
local overall = dataset.compute_statistics(train_expanded, p)
local function standardized(values)
    return dataset.standardize(values, overall, p)
end
local function vector(values)
    return standardized(dataset.expanded_values(tuples, values))
end
local train_vectors, test_vectors = map(train_expanded, standardized), map(test_expanded, standardized)
local train_targets = map(train, function(example)
    return example.label == settings.positive and 1 or 0
end)
local test_targets = map(test, function(example)
    return example.label == settings.positive and 1 or 0
end)
local train_labels = map(train, function(example)
    return example.label
end)
local test_labels = map(test, function(example)
    return example.label
end)
local classes = 0
for _, label in ipairs(train_labels) do
    classes = math.max(classes, label + 1)
end
local mean_values = slice(overall.means, 1, d)
local function evaluate(weights, vectors, targets)
    local scores = probabilities(weights, vectors)
    local predictions = predict(scores, settings.threshold)
    local numerator, denominator = metrics.auc(scores, targets)
    return {probabilities = scores, predictions = predictions, loss = logistic.average_loss(weights, vectors, targets), correct = count_equal(predictions, targets), numerator = numerator, denominator = denominator}
end
local function binary_model(name, checkpoints)
    local weights = last_weights(checkpoints)
    local fitting, checking = evaluate(weights, train_vectors, train_targets), evaluate(weights, test_vectors, test_targets)
    return {name = name, checkpoints = checkpoints, weights = weights, train = fitting, test = checking, roc = metrics.roc_points(checking.probabilities, test_targets)}
end
local function influence(weights, vectors, targets, lambda)
    local matrix = inverse(logistic.hessian(weights, vectors, lambda))
    local result = {matrix = matrix, probabilities = {}, leverages = {}, residuals = {}, distances = {}}
    for i, row in ipairs(vectors) do
        local pi = logistic.probability(logistic.score(weights, row))
        local variance, quadratic = pi * (1.0 - pi), 0.0
        for j = 1, #weights do
            for k = 1, #weights do
                quadratic = quadratic + row[j] * matrix[j][k] * row[k]
            end
        end
        local leverage = variance * quadratic / #vectors
        local pearson = (targets[i] - pi) / math.sqrt(variance)
        result.probabilities[i], result.leverages[i], result.residuals[i] = pi, leverage, pearson / math.sqrt(1.0 - leverage)
        result.distances[i] = pearson * pearson * leverage / (#weights * ((1.0 - leverage) * (1.0 - leverage)))
    end
    result.edf = sum(result.leverages)
    result.deviance = 2.0 * #vectors * logistic.average_loss(weights, vectors, targets)
    result.aic, result.bic = result.deviance + 2.0 * result.edf, result.deviance + math.log(#vectors) * result.edf
    return result
end
local function original_units(weights)
    local scaled, shift = {}, 0.0
    for j = 2, #weights do
        scaled[j] = weights[j] / overall.deviations[j - 1]
        shift = shift + scaled[j] * overall.means[j - 1]
    end
    scaled[1] = weights[1] - shift
    return scaled
end
local function cross_validate(lambda, count)
    local losses, scores, fold_losses, errors = {}, {}, {}, 0
    for fold = 0, 4 do
        local fitting, checking, targets = {}, {}, {}
        for i = 1, n do
            if (i - 1) % 5 == fold then
                checking[#checking + 1] = i
            else
                fitting[#fitting + 1], targets[#targets + 1] = train_expanded[i], train_targets[i]
            end
        end
        local statistics = dataset.compute_statistics(fitting, count)
        local vectors = map(fitting, function(values)
            return dataset.standardize(values, statistics, count)
        end)
        local weights = last_weights(optimizers.newton_method(vectors, targets, lambda))
        local total = 0.0
        for _, i in ipairs(checking) do
            local score = logistic.score(weights, dataset.standardize(train_expanded[i], statistics, count))
            losses[i], scores[i] = logistic.loss(score, train_targets[i]), logistic.probability(score)
            total = total + losses[i]
            if (scores[i] >= settings.threshold and 1 or 0) ~= train_targets[i] then
                errors = errors + 1
            end
        end
        fold_losses[#fold_losses + 1] = total / #checking
    end
    return {lambda = lambda, fold_losses = fold_losses, loss = sum(losses) / n, probabilities = scores, errors = errors}
end
local results = map(settings.lambdas, function(lambda)
    return cross_validate(lambda, p)
end)
local best = results[1]
for _, result in ipairs(results) do
    if result.loss <= best.loss then
        best = result
    end
end
local lambda = best.lambda
local mean_fold = sum(best.fold_losses) / 5.0
local se = math.sqrt(sum(map(best.fold_losses, function(value)
    return (value - mean_fold) * (value - mean_fold)
end)) / 4.0) / math.sqrt(5.0)
local one_se = lambda
for _, result in ipairs(results) do
    if result.loss <= best.loss + se then
        one_se = result.lambda
    end
end
local models = {
    binary_model("gd", optimizers.gradient_descent(train_vectors, train_targets, lambda, settings.gd_rate, settings.gd_iterations)),
    binary_model("sgd", optimizers.stochastic_gradient_descent(train_vectors, train_targets, lambda, settings.sgd_rate, settings.batch_size, settings.epochs, settings.sgd_seed)),
    binary_model("newton", optimizers.newton_method(train_vectors, train_targets, lambda))
}
local newton = models[3]
local soft_checkpoints = softmax.train(train_vectors, train_labels, classes, settings.softmax_lambda, settings.softmax_rate, settings.softmax_iterations)
local soft_weights = last_weights(soft_checkpoints)
local soft_probabilities = map(test_vectors, function(row)
    return softmax.probabilities(soft_weights, row)
end)
local soft_predictions = map(soft_probabilities, softmax.predicted_class)
local inf = influence(newton.weights, train_vectors, train_targets, lambda)
local function term_lines(weights)
    local original = original_units(weights)
    local lines = {"term intercept standardized " .. fixed(weights[1], 4) .. " original " .. fixed(original[1], 4)}
    for j, name in ipairs(feature_names) do
        lines[#lines + 1] = "term " .. name .. " standardized " .. fixed(weights[j + 1], 4) .. " original " .. fixed(original[j + 1], 4)
    end
    return lines
end
local weight_parts = {}
local correlation = {}
for j = 1, p do
    correlation[j] = {}
    for k = 1, p do
        local total = 0.0
        for _, row in ipairs(train_vectors) do
            total = total + row[j + 1] * row[k + 1]
        end
        correlation[j][k] = total / (n - 1)
    end
end
local inflation = inverse(correlation)
local feature_lines = {"features " .. d .. " degree " .. settings.degree .. " expanded " .. p, "standardization"}
for j, name in ipairs(feature_names) do
    feature_lines[#feature_lines + 1] = name .. " mean " .. fixed(overall.means[j], 6) .. " sd " .. fixed(overall.deviations[j], 6) .. " vif " .. fixed(inflation[j][j], 4)
end
feature_lines[#feature_lines + 1] = "correlation"
for _, row in ipairs(correlation) do
    feature_lines[#feature_lines + 1] = reals(row, 4)
end
weight_parts[1] = feature_lines
for _, model in ipairs(models) do
    local lines = {"model " .. model.name .. " lambda " .. fixed(lambda, 4)}
    append(lines, term_lines(model.weights))
    lines[#lines + 1] = "norm " .. fixed(length(slice(model.weights, 2)), 4)
    if model.name ~= "newton" then
        lines[#lines + 1] = "distance_to_newton " .. fixed(length(map(model.weights, function(value, j)
            return value - newton.weights[j]
        end)), 6)
    end
    weight_parts[#weight_parts + 1] = lines
end
local coefficient_lines = {"coefficients newton lambda " .. fixed(lambda, 4)}
for j, weight in ipairs(newton.weights) do
    local name = j == 1 and "intercept" or feature_names[j - 1]
    local error = math.sqrt(inf.matrix[j][j] / n)
    coefficient_lines[#coefficient_lines + 1] = name .. " weight " .. fixed(weight, 4) .. " se " .. fixed(error, 4) .. " z " .. fixed(weight / error, 4) .. " lower " .. fixed(weight - 1.96 * error, 4) .. " upper " .. fixed(weight + 1.96 * error, 4) .. " odds_ratio " .. fixed(math.exp(weight), 4)
end
weight_parts[#weight_parts + 1] = coefficient_lines
local soft_weight_lines = {"model softmax lambda " .. fixed(settings.softmax_lambda, 4)}
for k, row in ipairs(soft_weights) do
    soft_weight_lines[#soft_weight_lines + 1] = "class " .. (k - 1)
    append(soft_weight_lines, term_lines(row))
end
weight_parts[#weight_parts + 1] = soft_weight_lines
local loss_lines, prediction_lines, roc_lines = {"optimizer,iteration,loss,gradient_norm,test_loss"}, {"id,model,probability,predicted,actual"}, {"model,threshold,tpr,fpr,precision"}
local positives, negatives = count_sum(test_targets), m - count_sum(test_targets)
for _, model in ipairs(models) do
    for _, checkpoint in ipairs(model.checkpoints) do
        local weights = checkpoint.weights
        loss_lines[#loss_lines + 1] = table.concat({model.name, checkpoint.iteration, fixed(logistic.objective(weights, train_vectors, train_targets, lambda), 6), fixed(length(logistic.gradient(weights, train_vectors, train_targets, lambda)), 6), fixed(logistic.average_loss(weights, test_vectors, test_targets), 6)}, ",")
    end
    for i, example in ipairs(test) do
        prediction_lines[#prediction_lines + 1] = table.concat({example.ident, model.name, fixed(model.test.probabilities[i], 6), model.test.predictions[i], test_targets[i]}, ",")
    end
    roc_lines[#roc_lines + 1] = model.name .. ",inf,0.0000,0.0000,-"
    for _, point in ipairs(model.roc) do
        roc_lines[#roc_lines + 1] = table.concat({model.name, fixed(point.threshold, 6), ratio(point.tp, positives), ratio(point.fp, negatives), ratio(point.tp, point.tp + point.fp)}, ",")
    end
end
for _, checkpoint in ipairs(soft_checkpoints) do
    local weights = checkpoint.weights
    local direction, flat = softmax.gradient(weights, train_vectors, train_labels, settings.softmax_lambda), {}
    for _, row in ipairs(direction) do
        append(flat, row)
    end
    loss_lines[#loss_lines + 1] = table.concat({"softmax", checkpoint.iteration, fixed(softmax.objective(weights, train_vectors, train_labels, settings.softmax_lambda), 6), fixed(length(flat), 6), fixed(softmax.average_loss(weights, test_vectors, test_labels), 6)}, ",")
end
for i, example in ipairs(test) do
    local predicted = soft_predictions[i]
    prediction_lines[#prediction_lines + 1] = table.concat({example.ident, "softmax", fixed(soft_probabilities[i][predicted + 1], 6), predicted, example.label}, ",")
end
local function class_counts(labels)
    local counts = {}
    for k = 1, classes do
        counts[k] = 0
    end
    for _, label in ipairs(labels) do
        counts[label + 1] = counts[label + 1] + 1
    end
    return counts
end
local evaluation_parts = {{
    "data train " .. n .. " test " .. m .. " base_features " .. d .. " degree " .. settings.degree .. " features " .. p,
    "binary positive_class " .. settings.positive .. " train " .. count_sum(train_targets) .. "/" .. n .. " test " .. positives .. "/" .. m,
    "classes " .. classes .. " train " .. table.concat(class_counts(train_labels), " ") .. " test " .. table.concat(class_counts(test_labels), " ")
}}
local cv_lines = {"cross_validation folds 5 newton_iterations 10"}
for _, result in ipairs(results) do
    cv_lines[#cv_lines + 1] = "lambda " .. fixed(result.lambda, 4) .. " fold_loss " .. reals(result.fold_losses, 6) .. " cv_loss " .. fixed(result.loss, 6) .. " errors " .. result.errors .. "/" .. n
end
cv_lines[#cv_lines + 1] = "selected lambda " .. fixed(lambda, 4) .. " cv_loss " .. fixed(best.loss, 6) .. " se " .. fixed(se, 6) .. " lambda_1se " .. fixed(one_se, 4)
local validation_matrix = metrics.confusion(predict(best.probabilities, settings.threshold), train_targets)
cv_lines[#cv_lines + 1] = string.format("out_of_fold tp %d fp %d tn %d fn %d accuracy %s auc %s", validation_matrix.tp, validation_matrix.fp, validation_matrix.tn, validation_matrix.fn, ratio(validation_matrix.tp + validation_matrix.tn, n), auc_text(best.probabilities, train_targets))
evaluation_parts[#evaluation_parts + 1] = cv_lines
local path_lines = {"lambda_path"}
for _, value in ipairs(settings.lambdas) do
    local weights = last_weights(optimizers.newton_method(train_vectors, train_targets, value))
    local fitting, checking = evaluate(weights, train_vectors, train_targets), evaluate(weights, test_vectors, test_targets)
    path_lines[#path_lines + 1] = "lambda " .. fixed(value, 4) .. " objective " .. fixed(logistic.objective(weights, train_vectors, train_targets, value), 6) .. " train_loss " .. fixed(fitting.loss, 6) .. " test_loss " .. fixed(checking.loss, 6) .. " train_accuracy " .. ratio(fitting.correct, n) .. " test_accuracy " .. ratio(checking.correct, m) .. " norm " .. fixed(length(slice(weights, 2)), 4)
end
evaluation_parts[#evaluation_parts + 1] = path_lines
local degree_lines = {"degrees lambda " .. fixed(lambda, 4)}
for degree = 1, settings.degree do
    local count = 0
    for _, indices in ipairs(tuples) do
        if #indices <= degree then
            count = count + 1
        end
    end
    local fitting_vectors = map(train_vectors, function(row)
        return slice(row, 1, count + 1)
    end)
    local checking_vectors = map(test_vectors, function(row)
        return slice(row, 1, count + 1)
    end)
    local weights = last_weights(optimizers.newton_method(fitting_vectors, train_targets, lambda))
    local fitting, checking = evaluate(weights, fitting_vectors, train_targets), evaluate(weights, checking_vectors, test_targets)
    local validation, measures = cross_validate(lambda, count), influence(weights, fitting_vectors, train_targets, lambda)
    degree_lines[#degree_lines + 1] = "degree " .. degree .. " features " .. count .. " cv_loss " .. fixed(validation.loss, 6) .. " train_loss " .. fixed(fitting.loss, 6) .. " test_loss " .. fixed(checking.loss, 6) .. " test_accuracy " .. ratio(checking.correct, m) .. " auc " .. fraction(checking.numerator, checking.denominator) .. " edf " .. fixed(measures.edf, 4) .. " aic " .. fixed(measures.aic, 4) .. " bic " .. fixed(measures.bic, 4)
end
evaluation_parts[#evaluation_parts + 1] = degree_lines
local learning_lines = {"learning_curve lambda " .. fixed(lambda, 4)}
for step = 1, 4 do
    local size = step * n // 4
    local rows, targets = slice(train_expanded, 1, size), slice(train_targets, 1, size)
    local statistics = dataset.compute_statistics(rows, p)
    local fitting_vectors = map(rows, function(row)
        return dataset.standardize(row, statistics, p)
    end)
    local checking_vectors = map(test_expanded, function(row)
        return dataset.standardize(row, statistics, p)
    end)
    local weights = last_weights(optimizers.newton_method(fitting_vectors, targets, lambda))
    local fitting, checking = evaluate(weights, fitting_vectors, targets), evaluate(weights, checking_vectors, test_targets)
    learning_lines[#learning_lines + 1] = "size " .. size .. " train_loss " .. fixed(fitting.loss, 6) .. " test_loss " .. fixed(checking.loss, 6) .. " test_accuracy " .. ratio(checking.correct, m) .. " auc " .. fraction(checking.numerator, checking.denominator)
end
evaluation_parts[#evaluation_parts + 1] = learning_lines
local function bin_index(value)
    return math.min(9, math.floor(value * 10.0))
end
local function fill_bins(values, hits)
    local bins = {}
    for i = 1, 10 do
        bins[i] = {count = 0, total = 0.0, hits = 0}
    end
    for i, value in ipairs(values) do
        local bin = bins[bin_index(value) + 1]
        bin.count, bin.total, bin.hits = bin.count + 1, bin.total + value, bin.hits + hits[i]
    end
    return bins
end
local function bins_lines(bins, mean_label, rate_label)
    local lines = {}
    for i, bin in ipairs(bins) do
        local mean = bin.count == 0 and "-" or fixed(bin.total / bin.count, 4)
        lines[i] = string.format("bin %.1f-%.1f count %d %s %s %s %s", (i - 1) / 10.0, i / 10.0, bin.count, mean_label, mean, rate_label, ratio(bin.hits, bin.count))
    end
    return lines
end
local function calibration_error(bins, size)
    local total = 0.0
    for _, bin in ipairs(bins) do
        if bin.count > 0 then
            total = total + math.abs(bin.total - bin.hits)
        end
    end
    return total / size
end
local function cost(point)
    return settings.cost_fp * point.fp + settings.cost_fn * (positives - point.tp)
end
for _, model in ipairs(models) do
    local scores = model.test.probabilities
    local matrix = metrics.confusion(model.test.predictions, test_targets)
    local tp, fp, tn, fn = matrix.tp, matrix.fp, matrix.tn, matrix.fn
    local brier = sum(map(scores, function(value, i)
        return (value - test_targets[i]) * (value - test_targets[i])
    end)) / m
    local youden, best_f1, cheapest = model.roc[1], model.roc[1], model.roc[1]
    local ap, previous = 0.0, 0
    for _, point in ipairs(model.roc) do
        if point.tp * negatives - point.fp * positives > youden.tp * negatives - youden.fp * positives then
            youden = point
        end
        if point.tp * (positives + best_f1.tp + best_f1.fp) > best_f1.tp * (positives + point.tp + point.fp) then
            best_f1 = point
        end
        if cost(point) < cost(cheapest) then
            cheapest = point
        end
        ap, previous = ap + (point.tp - previous) * point.tp / (point.tp + point.fp), point.tp
    end
    local lines = {
        "model " .. model.name .. " lambda " .. fixed(lambda, 4),
        "train correct " .. model.train.correct .. "/" .. n .. " accuracy " .. ratio(model.train.correct, n),
        string.format("test tp %d fp %d tn %d fn %d", tp, fp, tn, fn),
        "test accuracy " .. ratio(tp + tn, m) .. " precision " .. ratio(tp, tp + fp) .. " recall " .. ratio(tp, tp + fn) .. " specificity " .. ratio(tn, tn + fp) .. " f1 " .. ratio(2 * tp, 2 * tp + fp + fn),
        "log_loss " .. fixed(model.test.loss, 6) .. " brier " .. fixed(brier, 6),
        "auc " .. fraction(model.test.numerator, model.test.denominator) .. " average_precision " .. fixed(ap / positives, 4),
        "youden threshold " .. fixed(youden.threshold, 6) .. " tpr " .. ratio(youden.tp, positives) .. " fpr " .. ratio(youden.fp, negatives) .. " j " .. ratio(youden.tp * negatives - youden.fp * positives, positives * negatives),
        "best_f1 threshold " .. fixed(best_f1.threshold, 6) .. " precision " .. ratio(best_f1.tp, best_f1.tp + best_f1.fp) .. " recall " .. ratio(best_f1.tp, positives) .. " f1 " .. ratio(2 * best_f1.tp, positives + best_f1.tp + best_f1.fp),
        "min_cost threshold " .. fixed(cheapest.threshold, 6) .. " cost " .. cost(cheapest) .. " fp " .. cheapest.fp .. " fn " .. (positives - cheapest.tp),
        "calibration"
    }
    local bins, mce, statistic, groups = fill_bins(scores, test_targets), 0.0, 0.0, 0
    append(lines, bins_lines(bins, "mean_probability", "positive_rate"))
    for _, bin in ipairs(bins) do
        if bin.count > 0 then
            groups = groups + 1
            mce = math.max(mce, math.abs(bin.total / bin.count - bin.hits / bin.count))
            statistic = statistic + (bin.hits - bin.total) * (bin.hits - bin.total) / (bin.total * (1.0 - bin.total / bin.count))
        end
    end
    lines[#lines + 1] = "ece " .. fixed(calibration_error(bins, m), 4) .. " mce " .. fixed(mce, 4) .. " hosmer_lemeshow " .. fixed(statistic, 4) .. " groups " .. groups
    lines[#lines + 1] = "gains"
    local order = ordering(scores, true)
    for decile = 1, 10 do
        local size, hits = decile * m // 10, 0
        for position = 1, size do
            hits = hits + test_targets[order[position]]
        end
        lines[#lines + 1] = "decile " .. decile .. " rows " .. size .. " positives " .. hits .. " gain " .. ratio(hits, positives) .. " lift " .. ratio(hits * m, size * positives)
    end
    evaluation_parts[#evaluation_parts + 1] = lines
end
local comparison_lines = {}
for _, pair in ipairs({{1, 2}, {1, 3}, {2, 3}}) do
    local first, second, only_first, only_second = models[pair[1]], models[pair[2]], 0, 0
    for i, target in ipairs(test_targets) do
        if first.test.predictions[i] == target and second.test.predictions[i] ~= target then
            only_first = only_first + 1
        elseif second.test.predictions[i] == target and first.test.predictions[i] ~= target then
            only_second = only_second + 1
        end
    end
    local gap = math.abs(only_first - only_second) - 1
    comparison_lines[#comparison_lines + 1] = string.format("agreement %s %s same %d/%d only_first %d only_second %d mcnemar %s", first.name, second.name, count_equal(first.test.predictions, second.test.predictions), m, only_first, only_second, ratio(gap * gap, only_first + only_second))
end
evaluation_parts[#evaluation_parts + 1] = comparison_lines
local base_rate = count_sum(train_targets) / n
local null_loss = -(base_rate * math.log(base_rate) + (1.0 - base_rate) * math.log(1.0 - base_rate))
local diagnostics = {"diagnostics newton lambda " .. fixed(lambda, 4), "fit null_loss " .. fixed(null_loss, 6) .. " train_loss " .. fixed(newton.train.loss, 6) .. " mcfadden_r2 " .. fixed(1.0 - newton.train.loss / null_loss, 4) .. " deviance " .. fixed(inf.deviance, 4) .. " edf " .. fixed(inf.edf, 4) .. " aic " .. fixed(inf.aic, 4) .. " bic " .. fixed(inf.bic, 4)}
local grouped, hl = {}, 0.0
local train_order = ordering(inf.probabilities, false)
for group = 1, 10 do
    local first, last = (group - 1) * n // 10 + 1, group * n // 10
    local observed, expected = 0, 0.0
    for position = first, last do
        local i = train_order[position]
        observed, expected = observed + train_targets[i], expected + inf.probabilities[i]
    end
    local size = last - first + 1
    hl = hl + (observed - expected) * (observed - expected) / (expected * (1.0 - expected / size))
    grouped[#grouped + 1] = string.format("group %d rows %d observed %d expected %s", group, size, observed, fixed(expected, 4))
end
diagnostics[#diagnostics + 1] = "hosmer_lemeshow_train groups 10 statistic " .. fixed(hl, 4)
append(diagnostics, grouped)
diagnostics[#diagnostics + 1] = "newton_iterations"
for t = 1, 10 do
    local weights = newton.checkpoints[t].weights
    local direction, step = optimizers.newton_direction(weights, train_vectors, train_targets, lambda)
    local decrease = sum(map(direction, function(value, j)
        return value * step[j]
    end)) / 2.0
    diagnostics[#diagnostics + 1] = "iteration " .. t .. " objective " .. fixed(logistic.objective(weights, train_vectors, train_targets, lambda), 6) .. " gradient_norm " .. fixed(length(direction), 6) .. " step_norm " .. fixed(length(step), 6) .. " predicted_decrease " .. fixed(decrease, 6)
end
local original = original_units(newton.weights)
local function slope(values, base)
    local total = 0.0
    for j, indices in ipairs(tuples) do
        local occurrences, removed, product = 0, false, 1.0
        for _, index in ipairs(indices) do
            if index == base then
                occurrences = occurrences + 1
            end
            if index == base and not removed then
                removed = true
            else
                product = product * values[index]
            end
        end
        if occurrences > 0 then
            total = total + original[j + 1] * (occurrences * product)
        end
    end
    return total
end
local centre = logistic.probability(logistic.score(newton.weights, vector(mean_values)))
for base, name in ipairs(names) do
    local total = 0.0
    for i, example in ipairs(train) do
        local pi = inf.probabilities[i]
        total = total + pi * (1.0 - pi) * slope(example.values, base)
    end
    diagnostics[#diagnostics + 1] = "marginal " .. name .. " average " .. fixed(total / n, 4) .. " at_mean " .. fixed(centre * (1.0 - centre) * slope(mean_values, base), 4)
end
for cut = 1, 9 do
    local matrix = metrics.confusion(predict(newton.test.probabilities, cut / 10.0), test_targets)
    diagnostics[#diagnostics + 1] = "cut 0." .. cut .. " positive " .. (matrix.tp + matrix.fp) .. " tp " .. matrix.tp .. " fp " .. matrix.fp .. " precision " .. ratio(matrix.tp, matrix.tp + matrix.fp) .. " recall " .. ratio(matrix.tp, matrix.tp + matrix.fn) .. " accuracy " .. ratio(matrix.tp + matrix.tn, m)
end
local wrong = {}
for i = 1, m do
    if newton.test.predictions[i] ~= test_targets[i] then
        wrong[#wrong + 1] = i
    end
end
table.sort(wrong, function(a, b)
    local first, second = math.abs(newton.test.probabilities[a] - settings.threshold), math.abs(newton.test.probabilities[b] - settings.threshold)
    return first > second or first == second and a < b
end)
for position = 1, math.min(5, #wrong) do
    local i = wrong[position]
    diagnostics[#diagnostics + 1] = "error " .. test[i].ident .. " actual " .. test_targets[i] .. " probability " .. fixed(newton.test.probabilities[i], 6)
end
local bootstrap_rng, samples, bootstrap_values = optimizers.generator(settings.bootstrap_seed), {}, {}
for replicate = 1, settings.bootstrap_count do
    local scores, targets = {}, {}
    for j = 1, m do
        local i = bootstrap_rng:draw() % m + 1
        scores[j], targets[j] = newton.test.probabilities[i], test_targets[i]
    end
    local numerator, denominator = metrics.auc(scores, targets)
    samples[replicate], bootstrap_values[replicate] = {numerator, denominator}, numerator / denominator
end
local bootstrap_mean = sum(bootstrap_values) / settings.bootstrap_count
local bootstrap_sd = math.sqrt(sum(map(bootstrap_values, function(value)
    return (value - bootstrap_mean) * (value - bootstrap_mean)
end)) / (settings.bootstrap_count - 1))
local bootstrap_order = ordering(bootstrap_values, false)
local tail = settings.bootstrap_count // 40
local lower, upper = samples[bootstrap_order[tail + 1]], samples[bootstrap_order[settings.bootstrap_count - tail]]
diagnostics[#diagnostics + 1] = "bootstrap resamples " .. settings.bootstrap_count .. " seed " .. settings.bootstrap_seed .. " auc_mean " .. fixed(bootstrap_mean, 4) .. " auc_sd " .. fixed(bootstrap_sd, 4) .. " lower " .. fraction(lower[1], lower[2]) .. " upper " .. fraction(upper[1], upper[2])
local large = 0
for _, residual in ipairs(inf.residuals) do
    if math.abs(residual) > 2.0 then
        large = large + 1
    end
end
diagnostics[#diagnostics + 1] = "influence effective_parameters " .. fixed(inf.edf, 4) .. " large_residuals " .. large
local cook_order = ordering(inf.distances, true)
for position = 1, math.min(5, n) do
    local i = cook_order[position]
    diagnostics[#diagnostics + 1] = "cook " .. train[i].ident .. " actual " .. train_targets[i] .. " probability " .. fixed(inf.probabilities[i], 4) .. " leverage " .. fixed(inf.leverages[i], 4) .. " residual " .. fixed(inf.residuals[i], 4) .. " distance " .. fixed(inf.distances[i], 4)
end
evaluation_parts[#evaluation_parts + 1] = diagnostics
local soft_correct = count_equal(soft_predictions, test_labels)
local importance = {"importance repeats " .. settings.permutation_count .. " seed " .. settings.permutation_seed, "baseline log_loss " .. fixed(newton.test.loss, 6) .. " auc " .. fraction(newton.test.numerator, newton.test.denominator) .. " softmax_accuracy " .. ratio(soft_correct, m)}
local permutation_rng = optimizers.generator(settings.permutation_seed)
for base, name in ipairs(names) do
    local losses, auc_total, correct_total = {}, 0, 0
    for replicate = 1, settings.permutation_count do
        local order = {}
        for i = 1, m do
            order[i] = i
        end
        optimizers.shuffle(order, permutation_rng)
        local vectors = {}
        for i, example in ipairs(test) do
            local values = copy(example.values)
            values[base] = test[order[i]].values[base]
            vectors[i] = vector(values)
        end
        losses[replicate] = logistic.average_loss(newton.weights, vectors, test_targets)
        local numerator = metrics.auc(probabilities(newton.weights, vectors), test_targets)
        auc_total = auc_total + numerator
        local predictions = map(vectors, function(row)
            return softmax.predicted_class(softmax.probabilities(soft_weights, row))
        end)
        correct_total = correct_total + count_equal(predictions, test_labels)
    end
    importance[#importance + 1] = "feature " .. name .. " log_loss_increase " .. fixed(sum(losses) / settings.permutation_count - newton.test.loss, 6) .. " auc " .. fraction(auc_total, settings.permutation_count * newton.test.denominator) .. " softmax_accuracy " .. ratio(correct_total, settings.permutation_count * m)
end
evaluation_parts[#evaluation_parts + 1] = importance
local minimums, maximums = {}, {}
for base = 1, d do
    minimums[base], maximums[base] = train[1].values[base], train[1].values[base]
    for _, example in ipairs(train) do
        minimums[base], maximums[base] = math.min(minimums[base], example.values[base]), math.max(maximums[base], example.values[base])
    end
end
local profiles = {"profiles"}
for base, name in ipairs(names) do
    for step = 0, 4 do
        local values = copy(mean_values)
        values[base] = minimums[base] + (maximums[base] - minimums[base]) * step / 4.0
        local row = vector(values)
        profiles[#profiles + 1] = "profile " .. name .. " value " .. fixed(values[base], 4) .. " newton " .. fixed(logistic.probability(logistic.score(newton.weights, row)), 4) .. " softmax " .. reals(softmax.probabilities(soft_weights, row), 4)
    end
end
evaluation_parts[#evaluation_parts + 1] = profiles
local multiclass = {"softmax classes " .. classes .. " lambda " .. fixed(settings.softmax_lambda, 4) .. " iterations " .. settings.softmax_iterations, "confusion"}
local confusion, row_totals, column_totals = {}, {}, {}
for k = 1, classes do
    confusion[k], row_totals[k], column_totals[k] = {}, 0, 0
    for j = 1, classes do
        confusion[k][j] = 0
    end
end
for i, label in ipairs(test_labels) do
    local predicted = soft_predictions[i]
    confusion[label + 1][predicted + 1] = confusion[label + 1][predicted + 1] + 1
    row_totals[label + 1], column_totals[predicted + 1] = row_totals[label + 1] + 1, column_totals[predicted + 1] + 1
end
for _, row in ipairs(confusion) do
    multiclass[#multiclass + 1] = table.concat(row, " ")
end
local diagonal, chance = 0, 0
for k = 1, classes do
    local scores = map(soft_probabilities, function(values)
        return values[k]
    end)
    local targets = map(test_labels, function(label)
        return label == k - 1 and 1 or 0
    end)
    local hits = confusion[k][k]
    multiclass[#multiclass + 1] = "class " .. (k - 1) .. " precision " .. ratio(hits, column_totals[k]) .. " recall " .. ratio(hits, row_totals[k]) .. " f1 " .. ratio(2 * hits, column_totals[k] + row_totals[k]) .. " auc " .. auc_text(scores, targets)
    diagonal, chance = diagonal + hits, chance + row_totals[k] * column_totals[k]
end
multiclass[#multiclass + 1] = "accuracy " .. ratio(diagonal, m) .. " kappa " .. ratio(m * diagonal - chance, m * m - chance)
local squares, confidences, hits = {}, {}, {}
for i, values in ipairs(soft_probabilities) do
    local total = 0.0
    for k, value in ipairs(values) do
        local error = value - (test_labels[i] == k - 1 and 1.0 or 0.0)
        total = total + error * error
    end
    squares[i], confidences[i], hits[i] = total, values[soft_predictions[i] + 1], soft_predictions[i] == test_labels[i] and 1 or 0
end
multiclass[#multiclass + 1] = "log_loss " .. fixed(softmax.average_loss(soft_weights, test_vectors, test_labels), 6) .. " brier " .. fixed(sum(squares) / m, 6)
local binary_scores = map(soft_probabilities, function(values)
    return values[settings.positive + 1]
end)
local binary_predictions = predict(binary_scores, settings.threshold)
local binary_loss = sum(map(binary_scores, function(value, i)
    return -math.log(test_targets[i] == 1 and value or 1.0 - value)
end)) / m
multiclass[#multiclass + 1] = "binary_view positive_class " .. settings.positive .. " auc " .. auc_text(binary_scores, test_targets) .. " log_loss " .. fixed(binary_loss, 6) .. " accuracy " .. ratio(count_equal(binary_predictions, test_targets), m) .. " agreement_with_newton " .. count_equal(binary_predictions, newton.test.predictions) .. "/" .. m
local confidence_bins = fill_bins(confidences, hits)
multiclass[#multiclass + 1] = "confidence"
append(multiclass, bins_lines(confidence_bins, "mean_confidence", "accuracy"))
multiclass[#multiclass + 1] = "ece " .. fixed(calibration_error(confidence_bins, m), 4)
evaluation_parts[#evaluation_parts + 1] = multiclass
local ovr, class_probabilities = {"one_vs_rest lambda " .. fixed(settings.softmax_lambda, 4) .. " newton_iterations 10"}, {}
for k = 0, classes - 1 do
    local targets = map(train_labels, function(label)
        return label == k and 1 or 0
    end)
    local checking_targets = map(test_labels, function(label)
        return label == k and 1 or 0
    end)
    local weights = last_weights(optimizers.newton_method(train_vectors, targets, settings.softmax_lambda))
    local checking = evaluate(weights, test_vectors, checking_targets)
    ovr[#ovr + 1] = "class " .. k .. " objective " .. fixed(logistic.objective(weights, train_vectors, targets, settings.softmax_lambda), 6) .. " auc " .. fraction(checking.numerator, checking.denominator)
    class_probabilities[k + 1] = checking.probabilities
end
local ovr_predictions = {}
for i = 1, m do
    ovr_predictions[i] = softmax.predicted_class(map(class_probabilities, function(values)
        return values[i]
    end))
end
ovr[#ovr + 1] = "accuracy " .. ratio(count_equal(ovr_predictions, test_labels), m) .. " agreement_with_softmax " .. count_equal(ovr_predictions, soft_predictions) .. "/" .. m
evaluation_parts[#evaluation_parts + 1] = ovr
local maps, probability_rows, cells = {"map " .. names[1] .. " " .. names[2] .. " width " .. settings.map_width .. " height " .. settings.map_height, "softmax_classes"}, {}, {}
for k = 1, classes do
    cells[k] = 0
end
for r = 0, settings.map_height - 1 do
    local class_row, probability_row = {}, {}
    for c = 0, settings.map_width - 1 do
        local values = copy(mean_values)
        values[1] = minimums[1] + (c + 0.5) * (maximums[1] - minimums[1]) / settings.map_width
        values[2] = maximums[2] - (r + 0.5) * (maximums[2] - minimums[2]) / settings.map_height
        local row = vector(values)
        local predicted = softmax.predicted_class(softmax.probabilities(soft_weights, row))
        cells[predicted + 1] = cells[predicted + 1] + 1
        class_row[#class_row + 1], probability_row[#probability_row + 1] = predicted, bin_index(logistic.probability(logistic.score(newton.weights, row)))
    end
    maps[#maps + 1], probability_rows[#probability_rows + 1] = table.concat(class_row), table.concat(probability_row)
end
maps[#maps + 1], maps[#maps + 2] = "cells " .. table.concat(cells, " "), "newton_probability"
append(maps, probability_rows)
evaluation_parts[#evaluation_parts + 1] = maps
os.execute("mkdir -p output")
local function write_lines(name, lines)
    local handle = assert(io.open("output/" .. name, "wb"))
    handle:write(table.concat(lines, "\n"), "\n")
    handle:close()
end
local function write_parts(name, parts)
    local lines = {}
    for i, part in ipairs(parts) do
        if i > 1 then
            lines[#lines + 1] = ""
        end
        append(lines, part)
    end
    write_lines(name, lines)
end
write_parts("weights.txt", weight_parts)
write_lines("loss_trace.csv", loss_lines)
write_lines("predictions.csv", prediction_lines)
write_parts("evaluation.txt", evaluation_parts)
write_lines("roc.csv", roc_lines)
