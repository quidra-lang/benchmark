local dataset = require("dataset")
local linalg = require("linalg")
local gaussian = require("gaussian_models")
local evaluation = require("evaluation")
local plot = require("plot")
local names = {"NB", "LDA", "QDA"}
local function append(target, values)
    for _, value in ipairs(values) do
        target[#target + 1] = value
    end
end
local function copy(values)
    return {table.unpack(values)}
end
local function sum(values)
    local total = 0.0
    for _, value in ipairs(values) do
        total = total + value
    end
    return total
end
local function integers(values)
    local fields = {}
    for index, value in ipairs(values) do
        fields[index] = tostring(value)
    end
    return table.concat(fields, " ")
end
local function difference(first, second)
    local result = {}
    for index = 1, #first do
        result[index] = first[index] - second[index]
    end
    return result
end
local function predictions(model, rows)
    local result = {}
    for index, row in ipairs(rows) do
        result[index] = model:predict(row.values)
    end
    return result
end
local function correct_count(actual, predicted)
    local result = 0
    for index, value in ipairs(actual) do
        if value == predicted[index] then
            result = result + 1
        end
    end
    return result
end
local function confusion_lines(classes, matrix)
    local lines = {}
    for k, name in ipairs(classes) do
        lines[#lines + 1] = "confusion " .. name .. " " .. integers(matrix[k])
    end
    return lines
end
local function comparisons(title, labels, predicted, actual)
    local lines = {title}
    for a = 1, #labels - 1 do
        for b = a + 1, #labels do
            local b01, b10, chi, significant = evaluation.mcnemar(actual, predicted[a], predicted[b])
            lines[#lines + 1] = labels[a] .. " " .. labels[b] .. " b01 " .. b01 .. " b10 " .. b10 .. " chi2 " .. plot.real(chi) .. " significant " .. (significant and "yes" or "no")
        end
    end
    return lines
end
local data = dataset.read()
local params, features, classes, train, test = data.params, data.features, data.classes, data.train, data.test
local n, m, d, class_count = #train, #test, #features, #classes
local all, train_actual, test_actual, upper, lower, folds, fold_sizes = {}, {}, {}, {}, {}, {}, {}
for index = 1, d do
    all[index] = index
end
for k, name in ipairs(classes) do
    lower[k], upper[k] = name:sub(1, 1), name:sub(1, 1):upper()
end
for f = 1, params.folds do
    fold_sizes[f] = 0
end
for index, row in ipairs(train) do
    train_actual[index], folds[index] = row.class_index, row.id % params.folds
    fold_sizes[folds[index] + 1] = fold_sizes[folds[index] + 1] + 1
end
for index, row in ipairs(test) do
    test_actual[index] = row.class_index
end
local function feature_names(sequence)
    local result = {}
    for index, feature in ipairs(sequence) do
        result[index] = features[feature]
    end
    return table.concat(result, " ")
end
local function fit(name, sequence, rows, prior, epsilon, gamma)
    return gaussian.train(rows or train, sequence or all, class_count, name, prior or params.prior,
        epsilon or params.epsilon, gamma or params.gamma)
end
local cv_cache = {}
local function cross_validate(name, sequence, epsilon, gamma)
    epsilon, gamma = epsilon or params.epsilon, gamma or params.gamma
    local key = name .. ":" .. table.concat(sequence, ",") .. ":" .. string.format("%.17g", epsilon) .. ":" .. string.format("%.17g", gamma)
    if cv_cache[key] then
        return cv_cache[key]
    end
    local result = {predictions = {}, fold_correct = {}, correct = 0}
    for fold = 0, params.folds - 1 do
        local retained = {}
        for index, row in ipairs(train) do
            if folds[index] ~= fold then
                retained[#retained + 1] = row
            end
        end
        local model, correct = fit(name, sequence, retained, nil, epsilon, gamma), 0
        for index, row in ipairs(train) do
            if folds[index] == fold then
                local predicted = model:predict(row.values)
                result.predictions[index] = predicted
                if predicted == row.class_index then
                    correct = correct + 1
                end
            end
        end
        result.fold_correct[fold + 1], result.correct = correct, result.correct + correct
    end
    cv_cache[key] = result
    return result
end
local models, results, main_predictions = {}, {}, {}
for index, name in ipairs(names) do
    models[index], results[index], main_predictions[index] = fit(name), {}, {}
    for row_index, row in ipairs(test) do
        local result = models[index]:infer(row.values, data.costs)
        results[index][row_index], main_predictions[index][row_index] = result, result.predicted
    end
end
local function model_sections()
    local nb, lda, qda = models[1], models[2], models[3]
    local stats, sections = nb.statistics, {}
    local lines = {"features " .. table.concat(features, " "), "classes " .. table.concat(classes, " "), "prior_mode " .. params.prior}
    for k, name in ipairs(classes) do
        lines[#lines + 1] = "class " .. name .. " letter " .. upper[k] .. " count " .. stats.counts[k] .. " prior " .. plot.real(nb.priors[k]) .. " mean " .. plot.reals(stats.means[k])
    end
    sections[#sections + 1] = lines
    lines = {"model NB", "smoothing epsilon " .. plot.real(nb.epsilon) .. " max_variance " .. plot.real(nb.max_variance) .. " added " .. plot.real(nb.added_variance)}
    for k, name in ipairs(classes) do
        local diagonal = {}
        for j = 1, d do
            diagonal[j] = nb.covariances[k][j][j]
        end
        lines[#lines + 1] = "class " .. name .. " variance " .. plot.reals(diagonal) .. " log_det " .. plot.real(nb.log_determinants[k])
    end
    sections[#sections + 1] = lines
    local factor = lda.factors[1]
    lines = {"model LDA", "log_det " .. plot.real(lda.log_determinants[1])}
    for _, row in ipairs(lda.covariances[1]) do
        lines[#lines + 1] = "  " .. plot.reals(row)
    end
    for k, name in ipairs(classes) do
        local coefficients = linalg.backward(factor, linalg.forward(factor, lda.means[k]))
        local intercept = math.log(lda.priors[k]) - linalg.dot(lda.means[k], coefficients) / 2
        lines[#lines + 1] = "class " .. name .. " intercept " .. plot.real(intercept) .. " coef " .. plot.reals(coefficients)
    end
    sections[#sections + 1] = lines
    lines = {"model QDA gamma " .. plot.real(qda.gamma)}
    for k, name in ipairs(classes) do
        local eigenvalues = linalg.jacobi(qda.covariances[k])
        table.sort(eigenvalues, function(a, b) return a > b end)
        local condition = eigenvalues[1] / eigenvalues[#eigenvalues]
        lines[#lines + 1] = "class " .. name .. " log_det " .. plot.real(qda.log_determinants[k]) .. " eigenvalues " .. plot.reals(eigenvalues) .. " condition " .. plot.real(condition)
        for _, row in ipairs(qda.covariances[k]) do
            lines[#lines + 1] = "  " .. plot.reals(row)
        end
    end
    sections[#sections + 1] = lines
    lines = {"separation"}
    for a = 1, class_count - 1 do
        for b = a + 1, class_count do
            local delta = difference(stats.means[a], stats.means[b])
            local mahalanobis = math.sqrt(linalg.quadratic(factor, delta))
            local average = linalg.zeros(d)
            for i = 1, d do
                for j = 1, d do
                    average[i][j] = (qda.covariances[a][i][j] + qda.covariances[b][i][j]) / 2
                end
            end
            local average_factor = linalg.cholesky(average)
            local bhattacharyya = linalg.quadratic(average_factor, delta) / 8
                + (linalg.log_determinant(average_factor) - (qda.log_determinants[a] + qda.log_determinants[b]) / 2) / 2
            lines[#lines + 1] = classes[a] .. " " .. classes[b] .. " mahalanobis " .. plot.real(mahalanobis) .. " bhattacharyya " .. plot.real(bhattacharyya)
        end
    end
    sections[#sections + 1] = lines
    local outliers = {}
    for index, row in ipairs(train) do
        local distance = qda:distances(row.values)[row.class_index]
        if distance > params.theta then
            outliers[#outliers + 1] = {distance = distance, index = index}
        end
    end
    table.sort(outliers, function(a, b) return a.distance > b.distance or (a.distance == b.distance and a.index < b.index) end)
    lines = {"outliers threshold " .. plot.real(params.theta)}
    for _, outlier in ipairs(outliers) do
        local row = train[outlier.index]
        lines[#lines + 1] = row.id .. " " .. row.label .. " q " .. plot.real(outlier.distance)
    end
    lines[#lines + 1] = "count " .. #outliers
    sections[#sections + 1] = lines
    return sections
end
local function prediction_lines()
    local lines = {"id,model,actual,predicted,decision," .. table.concat(classes, ",")}
    for index, row in ipairs(test) do
        for model_index, name in ipairs(names) do
            local result = results[model_index][index]
            local fields = {tostring(row.id), name, row.label, classes[result.predicted], classes[result.decision]}
            for _, value in ipairs(result.posterior) do
                fields[#fields + 1] = plot.real(value)
            end
            lines[#lines + 1] = table.concat(fields, ",")
        end
    end
    return lines
end
local function model_evaluation(index)
    local inferred = results[index]
    local metrics = evaluation.measures(test_actual, main_predictions[index], class_count)
    local lines = {"model " .. names[index]}
    append(lines, confusion_lines(classes, metrics.matrix))
    append(lines, {"accuracy " .. plot.fraction(metrics.accuracy), "balanced_accuracy " .. plot.fraction(metrics.balanced_accuracy), "kappa " .. plot.fraction(metrics.kappa)})
    for k, name in ipairs(classes) do
        lines[#lines + 1] = "class " .. name .. " support " .. metrics.support[k] .. " recall " .. plot.fraction(metrics.recall[k]) .. " precision " .. plot.fraction(metrics.precision[k]) .. " f1 " .. plot.fraction(metrics.f1[k])
    end
    local loss, errors = 0.0, {}
    for row_index, row in ipairs(test) do
        local result = inferred[row_index]
        loss = loss + result.log_posterior[row.class_index]
        if result.predicted ~= row.class_index then
            errors[#errors + 1] = "error " .. row.id .. " actual " .. row.label .. " predicted " .. classes[result.predicted] .. " confidence " .. plot.real(result.confidence)
        end
    end
    append(lines, {"macro_f1 " .. plot.real(metrics.macro_f1), "log_loss " .. plot.real(-loss / m), "errors " .. #errors})
    append(lines, errors)
    local edges, calibration_error = {0.0}, 0.0
    append(edges, params.CALIBRATION_EDGES)
    edges[#edges + 1] = 1.0
    for bin = 1, #edges - 1 do
        local low, high, count, confidence, correct = edges[bin], edges[bin + 1], 0, 0.0, 0
        for row_index, result in ipairs(inferred) do
            if result.confidence >= low and (result.confidence < high or (bin == #edges - 1 and result.confidence == high)) then
                count, confidence = count + 1, confidence + result.confidence
                if result.predicted == test_actual[row_index] then
                    correct = correct + 1
                end
            end
        end
        lines[#lines + 1] = "bin " .. plot.real(low) .. " " .. plot.real(high) .. " count " .. count .. " confidence " .. (count > 0 and plot.real(confidence / count) or "-") .. " accuracy " .. plot.ratio(correct, count)
        calibration_error = calibration_error + math.abs(correct - confidence)
    end
    lines[#lines + 1] = "ece " .. plot.real(calibration_error / m)
    for _, threshold in ipairs(params.REJECT_THRESHOLDS) do
        local count, correct = 0, 0
        for row_index, result in ipairs(inferred) do
            if result.confidence >= threshold then
                count = count + 1
                if result.predicted == test_actual[row_index] then
                    correct = correct + 1
                end
            end
        end
        lines[#lines + 1] = "reject " .. plot.real(threshold) .. " accepted " .. count .. " coverage " .. plot.ratio(count, m) .. " accuracy " .. plot.ratio(correct, count)
    end
    return lines
end
local function bootstrap_lines()
    local count, draw = params.bootstrap_count, evaluation.generator(params.seed)
    local resamples = {{}, {}, {}}
    for round = 1, count do
        local correct = {0, 0, 0}
        for sample = 1, m do
            local index = draw() % m + 1
            for model = 1, 3 do
                if main_predictions[model][index] == test_actual[index] then
                    correct[model] = correct[model] + 1
                end
            end
        end
        for model = 1, 3 do
            resamples[model][round] = correct[model]
        end
    end
    local lines = {"bootstrap resamples " .. count .. " seed " .. params.seed}
    local offset = count // 40
    for model, name in ipairs(names) do
        local ordered = copy(resamples[model])
        table.sort(ordered)
        local total = 0
        for _, value in ipairs(ordered) do
            total = total + value
        end
        lines[#lines + 1] = name .. " mean " .. plot.real(total / count / m) .. " interval " .. plot.ratio(ordered[offset + 1], m) .. " " .. plot.ratio(ordered[count - offset], m)
    end
    for a = 1, 2 do
        for b = a + 1, 3 do
            local wins, ties = 0, 0
            for round = 1, count do
                if resamples[a][round] > resamples[b][round] then
                    wins = wins + 1
                elseif resamples[a][round] == resamples[b][round] then
                    ties = ties + 1
                end
            end
            lines[#lines + 1] = names[a] .. " " .. names[b] .. " wins " .. wins .. " ties " .. ties .. " losses " .. (count - wins - ties)
        end
    end
    return lines
end
local function subset_lines()
    local lines = {"cross_validation folds " .. params.folds, "fold_sizes " .. integers(fold_sizes)}
    local best
    for _, subset in ipairs(params.subsets) do
        lines[#lines + 1] = "subset " .. subset.name .. " features " .. feature_names(subset.features)
        for _, name in ipairs(names) do
            local result = cross_validate(name, subset.features)
            lines[#lines + 1] = "  " .. name .. " fold_correct " .. integers(result.fold_correct) .. " correct " .. result.correct .. " accuracy " .. plot.ratio(result.correct, n)
            if not best or result.correct > best.correct or (result.correct == best.correct and #subset.features < #best.subset.features) then
                best = {subset = subset, name = name, correct = result.correct}
            end
        end
    end
    lines[#lines + 1] = "best subset " .. best.subset.name .. " model " .. best.name .. " correct " .. best.correct .. " accuracy " .. plot.ratio(best.correct, n)
    local model = fit(best.name, best.subset.features)
    local correct = correct_count(test_actual, predictions(model, test))
    lines[#lines + 1] = "refit_test correct " .. correct .. " accuracy " .. plot.ratio(correct, m)
    return lines
end
local function forward_sections()
    local sections = {}
    for _, name in ipairs(names) do
        local lines, selected, chosen, best_step, best_correct = {"forward_selection model " .. name}, {}, {}, 0, -1
        for step = 1, d do
            local added, step_correct
            for feature = 1, d do
                if not chosen[feature] then
                    local sequence = copy(selected)
                    sequence[#sequence + 1] = feature
                    local result = cross_validate(name, sequence)
                    if not added or result.correct > step_correct then
                        added, step_correct = feature, result.correct
                    end
                end
            end
            selected[#selected + 1], chosen[added] = added, true
            lines[#lines + 1] = "step " .. step .. " add " .. features[added] .. " correct " .. step_correct .. " accuracy " .. plot.ratio(step_correct, n)
            if step_correct > best_correct then
                best_step, best_correct = step, step_correct
            end
        end
        local sequence = {}
        for index = 1, best_step do
            sequence[index] = selected[index]
        end
        lines[#lines + 1] = "best_step " .. best_step .. " features " .. feature_names(sequence)
        sections[#sections + 1] = lines
    end
    return sections
end
local function tuning_lines(name, values, title)
    local lines, best_value, best_correct = {title}, nil, -1
    for _, value in ipairs(values) do
        local result = cross_validate(name, all, name == "NB" and value or nil, name == "QDA" and value or nil)
        lines[#lines + 1] = "value " .. plot.real(value) .. " correct " .. result.correct .. " accuracy " .. plot.ratio(result.correct, n)
        if result.correct >= best_correct then
            best_value, best_correct = value, result.correct
        end
    end
    local model = fit(name, nil, nil, nil, name == "NB" and best_value or nil, name == "QDA" and best_value or nil)
    local correct = correct_count(test_actual, predictions(model, test))
    lines[#lines + 1] = "best " .. plot.real(best_value) .. " test correct " .. correct .. " accuracy " .. plot.ratio(correct, m)
    return lines
end
local function evaluation_sections()
    local sections = {{"test rows " .. m}}
    for index = 1, 3 do
        sections[#sections + 1] = model_evaluation(index)
    end
    local ensemble = {}
    for index = 1, m do
        local posterior = {}
        for k = 1, class_count do
            local total = 0.0
            for model = 1, 3 do
                total = total + results[model][index].posterior[k]
            end
            posterior[k] = total / 3
        end
        ensemble[index] = gaussian.argmax(posterior)
    end
    local metrics = evaluation.measures(test_actual, ensemble, class_count)
    sections[#sections + 1] = {"ensemble soft_vote", "accuracy " .. plot.fraction(metrics.accuracy) .. " balanced_accuracy " .. plot.fraction(metrics.balanced_accuracy) .. " kappa " .. plot.fraction(metrics.kappa)}
    sections[#sections + 1] = comparisons("mcnemar test", {"NB", "LDA", "QDA", "ENSEMBLE"}, {main_predictions[1], main_predictions[2], main_predictions[3], ensemble}, test_actual)
    local lines = {"costs"}
    for index, name in ipairs(names) do
        local argmax_total, decision_total, changed, correct = 0.0, 0.0, 0, 0
        for row_index, row in ipairs(test) do
            local result = results[index][row_index]
            argmax_total = argmax_total + data.costs[row.class_index][result.predicted]
            decision_total = decision_total + data.costs[row.class_index][result.decision]
            if result.predicted ~= result.decision then
                changed = changed + 1
            end
            if result.decision == row.class_index then
                correct = correct + 1
            end
        end
        lines[#lines + 1] = name .. " argmax_total " .. plot.real(argmax_total) .. " decision_total " .. plot.real(decision_total) .. " changed " .. changed .. " decision_accuracy " .. plot.ratio(correct, m)
    end
    sections[#sections + 1] = lines
    local novel = {}
    for index, row in ipairs(test) do
        local distances = models[3]:distances(row.values)
        local nearest = gaussian.argmin(distances)
        if distances[nearest] > params.theta then
            novel[#novel + 1] = {distance = distances[nearest], index = index, nearest = nearest}
        end
    end
    table.sort(novel, function(a, b) return a.distance > b.distance or (a.distance == b.distance and a.index < b.index) end)
    lines = {"novelty threshold " .. plot.real(params.theta)}
    for _, value in ipairs(novel) do
        lines[#lines + 1] = test[value.index].id .. " nearest " .. classes[value.nearest] .. " q " .. plot.real(value.distance)
    end
    lines[#lines + 1] = "count " .. #novel
    sections[#sections + 1] = lines
    sections[#sections + 1] = bootstrap_lines()
    local alternative = params.prior == "empirical" and "uniform" or "empirical"
    lines = {"prior_sensitivity alternative " .. alternative}
    for index, name in ipairs(names) do
        local model = fit(name, nil, nil, alternative)
        local predicted = predictions(model, test)
        local measures = evaluation.measures(test_actual, predicted, class_count)
        local changed = 0
        for j = 1, m do
            if predicted[j] ~= main_predictions[index][j] then
                changed = changed + 1
            end
        end
        lines[#lines + 1] = name .. " accuracy " .. plot.fraction(measures.accuracy) .. " balanced_accuracy " .. plot.fraction(measures.balanced_accuracy) .. " changed " .. changed
    end
    sections[#sections + 1] = lines
    lines = {"learning_curve"}
    for _, size in ipairs(params.CURVE) do
        local retained, taken = {}, {}
        for k = 1, class_count do
            taken[k] = 0
        end
        for _, row in ipairs(train) do
            if taken[row.class_index] < size then
                retained[#retained + 1] = row
                taken[row.class_index] = taken[row.class_index] + 1
            end
        end
        local fields = {"size " .. size .. " rows " .. #retained}
        for _, name in ipairs(names) do
            local model = fit(name, nil, retained)
            fields[#fields + 1] = name .. " " .. plot.ratio(correct_count(test_actual, predictions(model, test)), m)
        end
        lines[#lines + 1] = table.concat(fields, " ")
    end
    sections[#sections + 1] = lines
    sections[#sections + 1] = subset_lines()
    local cv_predictions = {}
    for index, name in ipairs(names) do
        cv_predictions[index] = cross_validate(name, all).predictions
    end
    sections[#sections + 1] = comparisons("mcnemar cross_validation", names, cv_predictions, train_actual)
    for index, name in ipairs(names) do
        local measures = evaluation.measures(train_actual, cv_predictions[index], class_count)
        lines = {"cv_confusion model " .. name}
        append(lines, confusion_lines(classes, measures.matrix))
        lines[#lines + 1] = "balanced_accuracy " .. plot.fraction(measures.balanced_accuracy) .. " kappa " .. plot.fraction(measures.kappa)
        sections[#sections + 1] = lines
    end
    lines = {"leave_one_out"}
    for _, name in ipairs(names) do
        local correct = 0
        for excluded, row in ipairs(train) do
            local retained = {}
            for index, candidate in ipairs(train) do
                if index ~= excluded then
                    retained[#retained + 1] = candidate
                end
            end
            local model = fit(name, nil, retained)
            if model:predict(row.values) == row.class_index then
                correct = correct + 1
            end
        end
        lines[#lines + 1] = name .. " correct " .. correct .. " accuracy " .. plot.ratio(correct, n)
    end
    sections[#sections + 1] = lines
    append(sections, forward_sections())
    sections[#sections + 1] = tuning_lines("NB", params.SMOOTHING_GRID, "nb_smoothing_path")
    sections[#sections + 1] = tuning_lines("QDA", params.GAMMA_GRID, "qda_gamma_path")
    return sections
end
local function point_grid(points, actual, limits, size)
    local width, height = size[1], size[2]
    local grid = {}
    for row = 1, height do
        grid[row] = {}
        for column = 1, width do
            grid[row][column] = " "
        end
    end
    for index, point in ipairs(points) do
        local column = plot.cell(point[1], limits[1], limits[2], width) + 1
        local row = height - plot.cell(point[2], limits[3], limits[4], height)
        local letter, previous = lower[actual[index]], grid[row][column]
        grid[row][column] = (previous == " " or previous == letter) and letter or "*"
    end
    return grid
end
local function limits_of(points)
    local xmin, xmax, ymin, ymax = points[1][1], points[1][1], points[1][2], points[1][2]
    for _, point in ipairs(points) do
        xmin, xmax = math.min(xmin, point[1]), math.max(xmax, point[1])
        ymin, ymax = math.min(ymin, point[2]), math.max(ymax, point[2])
    end
    return {xmin, xmax, ymin, ymax}
end
local function boundary_sections()
    local sections, width, height = {}, params.MAP_SIZE[1], params.MAP_SIZE[2]
    for _, pair in ipairs(params.pairs) do
        local fx, fy, points = pair[1], pair[2], {}
        for index, row in ipairs(train) do
            points[index] = {row.values[fx], row.values[fy]}
        end
        local limits = limits_of(points)
        local xmin, xmax, ymin, ymax = table.unpack(limits)
        local dx, dy = (xmax - xmin) / (width - 1), (ymax - ymin) / (height - 1)
        local lines = {"pair " .. features[fx] .. " " .. features[fy],
            "x " .. features[fx] .. " " .. plot.real(xmin) .. " " .. plot.real(xmax) .. " y " .. features[fy] .. " " .. plot.real(ymin) .. " " .. plot.real(ymax) .. " grid " .. width .. "x" .. height}
        local grids = {}
        for model_index, name in ipairs(names) do
            local model = fit(name, pair)
            local correct = correct_count(train_actual, predictions(model, train))
            local cv = cross_validate(name, pair)
            lines[#lines + 1] = "model " .. name .. " train_accuracy " .. plot.ratio(correct, n) .. " cv_accuracy " .. plot.ratio(cv.correct, n)
            local grid, inferred, counts = {}, {}, {}
            for k = 1, class_count do
                counts[k] = 0
            end
            for row = 0, height - 1 do
                grid[row + 1], inferred[row + 1] = {}, {}
                for column = 0, width - 1 do
                    local result = model:infer_vector({xmin + column * dx, ymax - row * dy})
                    inferred[row + 1][column + 1], grid[row + 1][column + 1] = result, upper[result.predicted]
                    counts[result.predicted] = counts[result.predicted] + 1
                end
            end
            grids[model_index] = inferred
            append(lines, plot.frame(grid))
            local fields = {"cells"}
            for k = 1, class_count do
                fields[#fields + 1] = upper[k] .. " " .. counts[k]
            end
            lines[#lines + 1] = table.concat(fields, " ")
        end
        local agreement, uncertainty, disagreements = {}, {}, 0
        local levels = " .:-=+*#%@"
        for row = 1, height do
            agreement[row], uncertainty[row] = {}, {}
            for column = 1, width do
                local distinct, seen = 0, {}
                for model = 1, 3 do
                    local predicted = grids[model][row][column].predicted
                    if not seen[predicted] then
                        seen[predicted], distinct = true, distinct + 1
                    end
                end
                agreement[row][column] = distinct == 1 and "." or tostring(distinct)
                if distinct ~= 1 then
                    disagreements = disagreements + 1
                end
                local u = (1 - grids[3][row][column].confidence) / (1 - 1 / class_count)
                local level = math.min(9, math.floor(10 * u))
                uncertainty[row][column] = levels:sub(level + 1, level + 1)
            end
        end
        lines[#lines + 1] = "agreement"
        append(lines, plot.frame(agreement))
        append(lines, {"disagreement_cells " .. disagreements, "uncertainty QDA"})
        append(lines, plot.frame(uncertainty))
        lines[#lines + 1] = "points"
        append(lines, plot.frame(point_grid(points, train_actual, limits, params.MAP_SIZE)))
        sections[#sections + 1] = lines
    end
    return sections
end
local function projection_sections()
    local stats = models[1].statistics
    local center, within, between = stats.center, linalg.zeros(d), linalg.zeros(d)
    for a = 1, d do
        for b = 1, d do
            local sw, sb = 0.0, 0.0
            for k = 1, class_count do
                sw = sw + stats.scatter[k][a][b]
                sb = sb + stats.counts[k] * (stats.means[k][a] - center[a]) * (stats.means[k][b] - center[b])
            end
            within[a][b], between[a][b] = sw, sb
        end
    end
    local f_values, feature_order = {}, copy(all)
    for j = 1, d do
        f_values[j] = (between[j][j] / (class_count - 1)) / (within[j][j] / (n - class_count))
    end
    table.sort(feature_order, function(a, b) return f_values[a] > f_values[b] or (f_values[a] == f_values[b] and a < b) end)
    local univariate = {"univariate"}
    for rank, j in ipairs(feature_order) do
        univariate[#univariate + 1] = "rank " .. rank .. " " .. features[j] .. " f " .. plot.real(f_values[j]) .. " between " .. plot.real(between[j][j]) .. " within " .. plot.real(within[j][j])
    end
    local factor, transformed, whitened = linalg.cholesky(within), linalg.zeros(d), linalg.zeros(d)
    for j = 1, d do
        local column = {}
        for a = 1, d do
            column[a] = between[a][j]
        end
        column = linalg.forward(factor, column)
        for a = 1, d do
            transformed[a][j] = column[a]
        end
    end
    for i = 1, d do
        local column = linalg.forward(factor, transformed[i])
        for a = 1, d do
            whitened[a][i] = column[a]
        end
    end
    local symmetric = linalg.zeros(d)
    for a = 1, d do
        for b = 1, d do
            symmetric[a][b] = (whitened[a][b] + whitened[b][a]) / 2
        end
    end
    local eigenvalues, eigenvectors, sweeps = linalg.jacobi(symmetric)
    local eigen_order, total = copy(all), sum(eigenvalues)
    table.sort(eigen_order, function(a, b) return eigenvalues[a] > eigenvalues[b] or (eigenvalues[a] == eigenvalues[b] and a < b) end)
    local directions = {}
    for dimension = 1, 2 do
        local vector = {}
        for j = 1, d do
            vector[j] = eigenvectors[j][eigen_order[dimension]]
        end
        vector = linalg.backward(factor, vector)
        local norm, magnitudes = math.sqrt(linalg.dot(vector, vector)), {}
        for j = 1, d do
            vector[j] = vector[j] / norm
            magnitudes[j] = math.abs(vector[j])
        end
        if vector[gaussian.argmax(magnitudes)] < 0 then
            for j = 1, d do
                vector[j] = -vector[j]
            end
        end
        directions[dimension] = vector
    end
    local function project(values)
        local result = {}
        for dimension, direction in ipairs(directions) do
            local value = 0.0
            for j = 1, d do
                value = value + direction[j] * (values[j] - center[j])
            end
            result[dimension] = value
        end
        return result
    end
    local train_points, test_points, centroids = {}, {}, {}
    for index, row in ipairs(train) do
        train_points[index] = project(row.values)
    end
    for index, row in ipairs(test) do
        test_points[index] = project(row.values)
    end
    for k, mean in ipairs(stats.means) do
        centroids[k] = project(mean)
    end
    local ordered_values, ratios = {}, {}
    for index, j in ipairs(eigen_order) do
        ordered_values[index], ratios[index] = eigenvalues[j], eigenvalues[j] / total
    end
    local fisher = {"fisher features " .. table.concat(features, " "), "center " .. plot.reals(center), "sweeps " .. sweeps,
        "eigenvalues " .. plot.reals(ordered_values), "ratios " .. plot.reals(ratios)}
    local pooled = models[2].covariances[1]
    for dimension, direction in ipairs(directions) do
        local standardized = {}
        for j = 1, d do
            standardized[j] = direction[j] * math.sqrt(pooled[j][j])
        end
        append(fisher, {"direction " .. dimension .. " " .. plot.reals(direction), "standardized " .. dimension .. " " .. plot.reals(standardized)})
    end
    for k, name in ipairs(classes) do
        local spread = {}
        for dimension = 1, 2 do
            local subtotal = 0.0
            for index, point in ipairs(train_points) do
                if train_actual[index] == k then
                    local delta = point[dimension] - centroids[k][dimension]
                    subtotal = subtotal + delta * delta
                end
            end
            spread[dimension] = math.sqrt(subtotal / stats.counts[k])
        end
        fisher[#fisher + 1] = "centroid " .. name .. " " .. plot.reals(centroids[k]) .. " spread " .. plot.reals(spread)
    end
    local function nearest_correct(points, actual, dimensions)
        local correct = 0
        for index, point in ipairs(points) do
            local distances = {}
            for k, centroid in ipairs(centroids) do
                local delta = point[1] - centroid[1]
                local distance = delta * delta
                if dimensions == 2 then
                    delta = point[2] - centroid[2]
                    distance = distance + delta * delta
                end
                distances[k] = distance
            end
            if gaussian.argmin(distances) == actual[index] then
                correct = correct + 1
            end
        end
        return correct
    end
    for dimensions = 1, 2 do
        fisher[#fisher + 1] = "nearest_centroid dims " .. dimensions .. " train " .. plot.ratio(nearest_correct(train_points, train_actual, dimensions), n) .. " test " .. plot.ratio(nearest_correct(test_points, test_actual, dimensions), m)
    end
    local limits = limits_of(train_points)
    local width, height = params.PLOT_SIZE[1], params.PLOT_SIZE[2]
    local grid = point_grid(train_points, train_actual, limits, params.PLOT_SIZE)
    for k, point in ipairs(centroids) do
        local column = plot.cell(point[1], limits[1], limits[2], width) + 1
        local row = height - plot.cell(point[2], limits[3], limits[4], height)
        grid[row][column] = upper[k]
    end
    local scatter = {"plot x " .. plot.real(limits[1]) .. " " .. plot.real(limits[2]) .. " y " .. plot.real(limits[3]) .. " " .. plot.real(limits[4]) .. " size " .. width .. "x" .. height}
    append(scatter, plot.frame(grid))
    return {univariate, fisher, scatter}
end
os.execute('mkdir -p output')
plot.save("models.txt", plot.join_sections(model_sections()))
plot.save("predictions.csv", prediction_lines())
plot.save("evaluation.txt", plot.join_sections(evaluation_sections()))
plot.save("boundaries.txt", plot.join_sections(boundary_sections()))
plot.save("projection.txt", plot.join_sections(projection_sections()))
