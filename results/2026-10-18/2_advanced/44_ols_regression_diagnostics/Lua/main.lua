local dataframe = require("dataframe")
local formula = require("formula")
local qr = require("qr_solver")
local inference = require("inference")
local diagnostics = require("diagnostics")
local four, probability, significance = inference.four, inference.probability, inference.significance
local function append(destination, source)
    for _, value in ipairs(source) do
        destination[#destination + 1] = value
    end
end
local function copy(values)
    return {table.unpack(values)}
end
local function table_lines(header, rows, marks)
    local widths = {}
    local all = {header}
    append(all, rows)
    for _, row in ipairs(all) do
        for column, value in ipairs(row) do
            row[column] = tostring(value)
            widths[column] = math.max(widths[column] or 0, #row[column])
        end
    end
    local lines = {}
    for index, row in ipairs(all) do
        local fields = {row[1] .. string.rep(" ", widths[1] - #row[1])}
        for column = 2, #row do
            fields[#fields + 1] = string.rep(" ", widths[column] - #row[column]) .. row[column]
        end
        local line = table.concat(fields, "  ")
        local mark = index > 1 and marks and marks[index - 1] or ""
        if mark ~= "" then
            line = line .. " " .. mark
        end
        lines[#lines + 1] = line:gsub(" +$", "")
    end
    return lines
end
local function data_summary(data)
    local numeric, rows = {}, {}
    for _, column in ipairs(data.columns) do
        if data.kinds[column] == "numeric" then
            numeric[#numeric + 1] = column
            local values, sum = {}, 0.0
            for _, row in ipairs(data.rows) do
                if row[column] ~= nil then
                    values[#values + 1] = row[column]
                    sum = sum + row[column]
                end
            end
            local mean, variance = sum / #values, 0.0
            local minimum, maximum = values[1], values[1]
            for _, value in ipairs(values) do
                variance = variance + (value - mean) * (value - mean)
                minimum, maximum = math.min(minimum, value), math.max(maximum, value)
            end
            rows[#rows + 1] = {column, #values, #data.rows - #values, four(mean), four(math.sqrt(variance / (#values - 1))), four(minimum), four(maximum)}
        end
    end
    local lines = {"Data: " .. #data.rows .. " rows, " .. #data.columns .. " columns", "", "Numeric columns:"}
    append(lines, table_lines({"column", "n", "missing", "Mean", "SD", "Min", "Max"}, rows))
    append(lines, {"", "Categorical columns:"})
    for _, column in ipairs(data.columns) do
        if data.kinds[column] == "categorical" then
            local counts, labels, present = {}, {}, 0
            for _, row in ipairs(data.rows) do
                local value = row[column]
                if value ~= nil then
                    present = present + 1
                    if not counts[value] then
                        counts[value] = 0
                        labels[#labels + 1] = value
                    end
                    counts[value] = counts[value] + 1
                end
            end
            table.sort(labels)
            local fields = {}
            for _, label in ipairs(labels) do
                fields[#fields + 1] = label .. " " .. counts[label]
            end
            lines[#lines + 1] = column .. ": " .. present .. " values, " .. #data.rows - present .. " missing, " .. #labels .. " levels: " .. table.concat(fields, ", ")
        end
    end
    append(lines, {"", "Correlations (pairwise complete observations):"})
    rows = {}
    for _, a in ipairs(numeric) do
        local fields = {a}
        for _, b in ipairs(numeric) do
            local xs, ys, sum_x, sum_y = {}, {}, 0.0, 0.0
            for _, row in ipairs(data.rows) do
                if row[a] ~= nil and row[b] ~= nil then
                    xs[#xs + 1], ys[#ys + 1] = row[a], row[b]
                    sum_x, sum_y = sum_x + row[a], sum_y + row[b]
                end
            end
            local mean_x, mean_y = sum_x / #xs, sum_y / #ys
            local cross, square_x, square_y = 0.0, 0.0, 0.0
            for index = 1, #xs do
                local x, y = xs[index] - mean_x, ys[index] - mean_y
                cross, square_x, square_y = cross + x * y, square_x + x * x, square_y + y * y
            end
            fields[#fields + 1] = four(cross / math.sqrt(square_x * square_y))
        end
        rows[#rows + 1] = fields
    end
    local header = {"column"}
    append(header, numeric)
    append(lines, table_lines(header, rows))
    lines[#lines + 1] = ""
    return lines
end
local function information_criteria(fitted)
    local log_weights = 0.0
    for _, weight in ipairs(fitted.weights) do
        log_weights = log_weights + math.log(weight)
    end
    local likelihood = 0.5 * (log_weights - fitted.n * (math.log(2.0 * 3.141592653589793) + 1.0 - math.log(fitted.n) + math.log(fitted.rss)))
    return likelihood, -2.0 * likelihood + 2.0 * (fitted.rank + 1), -2.0 * likelihood + math.log(fitted.n) * (fitted.rank + 1)
end
local function quantile(values, proportion)
    local position = (#values - 1) * proportion
    local index = math.floor(position) + 1
    if index < #values then
        return values[index] + (position - (index - 1)) * (values[index + 1] - values[index])
    end
    return values[index]
end
local function model_statistics(fitted, confidence)
    local n, rank = fitted.n, fitted.rank
    local degrees = n - rank
    local sigma, weight_sum, weighted_sum = math.sqrt(fitted.rss / degrees), 0.0, 0.0
    for i = 1, n do
        weight_sum = weight_sum + fitted.weights[i]
        weighted_sum = weighted_sum + fitted.weights[i] * fitted.response[i]
    end
    local mean, tss, press = weighted_sum / weight_sum, 0.0, 0.0
    for i = 1, n do
        tss = tss + fitted.weights[i] * (fitted.response[i] - mean) * (fitted.response[i] - mean)
        local value = fitted.weighted_residual[i] / (1.0 - fitted.leverage[i])
        press = press + value * value
    end
    local r_squared = 1.0 - fitted.rss / tss
    local adjusted = 1.0 - (1.0 - r_squared) * (n - 1) / degrees
    local statistic = ((tss - fitted.rss) / (rank - 1)) / (fitted.rss / degrees)
    local likelihood, aic, bic = information_criteria(fitted)
    local residuals = copy(fitted.weighted_residual)
    table.sort(residuals)
    local quantiles = {}
    for _, proportion in ipairs({0.0, 0.25, 0.5, 0.75, 1.0}) do
        quantiles[#quantiles + 1] = quantile(residuals, proportion)
    end
    return {df = degrees, sigma = sigma, weight_sum = weight_sum, tss = tss, r_squared = r_squared,
        adjusted = adjusted, f = statistic, p = inference.f_pvalue(statistic, rank - 1, degrees),
        ll = likelihood, aic = aic, bic = bic, press = press, predicted = 1.0 - press / tss,
        quantiles = quantiles, critical = inference.t_quantile(confidence, degrees)}
end
local function coefficient_inference(fitted, stats)
    local accepted, omega, result = {}, {}, {}
    for k, column in ipairs(fitted.accepted) do
        accepted[column] = k
    end
    for i = 1, fitted.n do
        omega[i] = fitted.weighted_residual[i] * fitted.weighted_residual[i] / ((1.0 - fitted.leverage[i]) * (1.0 - fitted.leverage[i]))
    end
    for column = 1, fitted.p do
        local estimate = fitted.beta[column]
        if estimate == nil then
            result[column] = {}
        else
            local k = accepted[column]
            local error = stats.sigma * math.sqrt(fitted.variance[k])
            local t = estimate / error
            local half = stats.critical * error
            local robust_variance = 0.0
            for i = 1, fitted.n do
                robust_variance = robust_variance + omega[i] * fitted.g[i][k] * fitted.g[i][k]
            end
            local robust_error = math.sqrt(robust_variance)
            local robust_t = estimate / robust_error
            result[column] = {estimate = estimate, se = error, t = t, p = inference.t_pvalue(t, stats.df),
                lower = estimate - half, upper = estimate + half, robust_se = robust_error,
                robust_t = robust_t, robust_p = inference.t_pvalue(robust_t, stats.df)}
        end
    end
    return result
end
local function all_terms(model)
    local result = {}
    for index = 1, #model.terms do
        result[index] = index
    end
    return result
end
local function without(indices, omitted)
    local result = {}
    for _, index in ipairs(indices) do
        if index ~= omitted then
            result[#result + 1] = index
        end
    end
    return result
end
local function fit_subset(design, terms, tolerance)
    return qr.fit(design:subset_matrix(terms), design.response, design.weights, tolerance)
end
local function sequential_anova(design, fitted)
    local result, residual_df = {}, fitted.n - fitted.rank
    for index, term in ipairs(design.model.terms) do
        local degrees, squares = 0, 0.0
        for k, column in ipairs(fitted.accepted) do
            if design.columns[column].term_index == index then
                degrees = degrees + 1
                squares = squares + fitted.effects[k] * fitted.effects[k]
            end
        end
        if degrees > 0 then
            local mean = squares / degrees
            local statistic = mean / (fitted.rss / residual_df)
            result[#result + 1] = {name = term.name, df = degrees, ss = squares, ms = mean,
                f = statistic, p = inference.f_pvalue(statistic, degrees, residual_df)}
        end
    end
    return result
end
local function marginal_tests(design, fitted, terms, tolerance)
    local result, residual_df = {}, fitted.n - fitted.rank
    for _, index in ipairs(design.model:removable(terms)) do
        local reduced = fit_subset(design, without(terms, index), tolerance)
        local degrees, squares = fitted.rank - reduced.rank, reduced.rss - fitted.rss
        local statistic, p
        if degrees > 0 then
            statistic = (squares / degrees) / (fitted.rss / residual_df)
            p = inference.f_pvalue(statistic, degrees, residual_df)
        end
        result[#result + 1] = {index = index, name = design.model.terms[index].name, df = degrees,
            ss = squares, rss = reduced.rss, f = statistic, p = p}
    end
    return result
end
local function variance_inflation(design, fitted, stats, params)
    local result = {}
    for k = 2, fitted.rank do
        local column = fitted.accepted[k]
        local response, matrix, sum = {}, {}, 0.0
        for i = 1, fitted.n do
            response[i], matrix[i] = fitted.matrix[i][column], {}
            sum = sum + fitted.weights[i] * response[i]
            for _, other in ipairs(fitted.accepted) do
                if other ~= column then
                    matrix[i][#matrix[i] + 1] = fitted.matrix[i][other]
                end
            end
        end
        local auxiliary = qr.fit(matrix, response, fitted.weights, params.RANK_TOL)
        local mean, tss = sum / stats.weight_sum, 0.0
        for i = 1, fitted.n do
            tss = tss + fitted.weights[i] * (response[i] - mean) * (response[i] - mean)
        end
        local r_squared = 1.0 - auxiliary.rss / tss
        local vif = 1.0 / (1.0 - r_squared)
        result[#result + 1] = {name = design.columns[column].name, value = vif, high = vif > params.VIF}
    end
    return result
end
local function reset_test(fitted, tolerance)
    local matrix = {}
    for i = 1, fitted.n do
        matrix[i] = {}
        for _, column in ipairs(fitted.accepted) do
            matrix[i][#matrix[i] + 1] = fitted.matrix[i][column]
        end
        local value = fitted.fitted[i]
        matrix[i][#matrix[i] + 1], matrix[i][#matrix[i] + 2] = value * value, value * value * value
    end
    local augmented = qr.fit(matrix, fitted.response, fitted.weights, tolerance)
    local added, residual_df = augmented.rank - fitted.rank, fitted.n - augmented.rank
    local statistic = ((fitted.rss - augmented.rss) / added) / (augmented.rss / residual_df)
    return {statistic, added, residual_df, inference.f_pvalue(statistic, added, residual_df)}
end
local function diagnostic_decisions(design, fitted, diagnostic, params)
    local dw_label = "no autocorrelation"
    if diagnostic.dw < params.DURBIN_WATSON then
        dw_label = "positive autocorrelation"
    elseif diagnostic.dw > 4.0 - params.DURBIN_WATSON then
        dw_label = "negative autocorrelation"
    end
    local outlier, order, counts = 1, {}, {H = 0, O = 0, C = 0, F = 0, any = 0}
    for i, row in ipairs(diagnostic.rows) do
        if math.abs(row.studentized) > math.abs(diagnostic.rows[outlier].studentized) then
            outlier = i
        end
        order[i] = i
        for flag in ("HOCF"):gmatch(".") do
            if row.flags:find(flag, 1, true) then
                counts[flag] = counts[flag] + 1
            end
        end
        if row.flags ~= "-" then
            counts.any = counts.any + 1
        end
    end
    table.sort(order, function(a, b)
        if diagnostic.rows[a].cooks ~= diagnostic.rows[b].cooks then
            return diagnostic.rows[a].cooks > diagnostic.rows[b].cooks
        end
        return a < b
    end)
    local largest_cooks, largest_dfbetas = {}, {}
    for position = 1, math.min(3, #order) do
        largest_cooks[position] = order[position]
    end
    for k, column in ipairs(fitted.accepted) do
        local index = 1
        for i = 2, fitted.n do
            if math.abs(diagnostic.rows[i].dfbetas[k]) > math.abs(diagnostic.rows[index].dfbetas[k]) then
                index = i
            end
        end
        largest_dfbetas[#largest_dfbetas + 1] = {design.columns[column].name, design.row_numbers[index], four(diagnostic.rows[index].dfbetas[k])}
    end
    local unadjusted = inference.t_pvalue(diagnostic.rows[outlier].studentized, fitted.n - fitted.rank - 1)
    return {dw_label = dw_label, bp_label = diagnostic.bp[3] < params.BREUSCH_PAGAN and "heteroscedastic" or "homoscedastic",
        jb_label = diagnostic.jb[2] < params.NORMALITY and "non-normal" or "normal", outlier = outlier,
        unadjusted = unadjusted, bonferroni = math.min(1.0, fitted.n * unadjusted), counts = counts,
        largest_cooks = largest_cooks, largest_dfbetas = largest_dfbetas}
end
local function prediction_report(model_number, design, fitted, stats, prediction_data)
    local lines, predicted_count, actual_count, covered_count, squared_errors = {}, 0, 0, 0, 0.0
    for row_number, record in ipairs(prediction_data.rows) do
        local fields = {model_number, row_number}
        if not design:predictable(record) then
            for _ = 1, 9 do
                fields[#fields + 1] = "NA"
            end
        else
            predicted_count = predicted_count + 1
            local values, predicted, variance = design:values(record), 0.0, 0.0
            for _, column in ipairs(fitted.accepted) do
                predicted = predicted + values[column] * fitted.beta[column]
            end
            for k = 1, fitted.rank do
                local sum = 0.0
                for m = 1, fitted.rank do
                    sum = sum + values[fitted.accepted[m]] * fitted.inverse[m][k]
                end
                variance = variance + sum * sum
            end
            local error = stats.sigma * math.sqrt(variance)
            local confidence_width = stats.critical * error
            local prediction_width = stats.critical * math.sqrt(stats.sigma * stats.sigma + error * error)
            local lower, upper = predicted - prediction_width, predicted + prediction_width
            for _, value in ipairs({predicted, error, predicted - confidence_width, predicted + confidence_width, lower, upper}) do
                fields[#fields + 1] = four(value)
            end
            local actual = record[design.model.response]
            if actual == nil then
                append(fields, {"NA", "NA", "NA"})
            else
                actual_count = actual_count + 1
                local difference = actual - predicted
                squared_errors = squared_errors + difference * difference
                local covered = lower <= actual and actual <= upper
                covered_count = covered_count + (covered and 1 or 0)
                append(fields, {four(actual), four(difference), covered and "yes" or "no"})
            end
        end
        lines[#lines + 1] = table.concat(fields, ",")
    end
    local rmse = actual_count > 0 and math.sqrt(squared_errors / actual_count) or nil
    return lines, {predicted = predicted_count, actual = actual_count, rmse = rmse, covered = covered_count}
end
local function analyze_model(model_number, design, params, prediction_data)
    local fitted = qr.fit(design.matrix, design.response, design.weights, params.RANK_TOL)
    local stats = model_statistics(fitted, params.CONFIDENCE)
    local diagnostic = diagnostics.calculate(fitted, params)
    local predictions, check = prediction_report(model_number, design, fitted, stats, prediction_data)
    return {number = model_number, design = design, fit = fitted, stats = stats,
        coefficients = coefficient_inference(fitted, stats), anova = sequential_anova(design, fitted),
        marginal = marginal_tests(design, fitted, all_terms(design.model), params.RANK_TOL),
        vif = variance_inflation(design, fitted, stats, params), diagnostics = diagnostic,
        decisions = diagnostic_decisions(design, fitted, diagnostic, params), reset = reset_test(fitted, params.RANK_TOL),
        predictions = predictions, prediction_check = check}
end
local function coefficient_tables(report, confidence)
    local rows, marks = {}, {}
    for index, column in ipairs(report.design.columns) do
        local value = report.coefficients[index]
        rows[index] = {column.name, four(value.estimate), four(value.se), four(value.t), probability(value.p)}
        marks[index] = significance(value.p)
    end
    local ordinary = table_lines({"term", "Estimate", "Std. Error", "t value", "Pr(>|t|)"}, rows, marks)
    rows = {}
    for index, column in ipairs(report.design.columns) do
        local value = report.coefficients[index]
        rows[index] = {column.name, four(value.lower), four(value.upper)}
    end
    local intervals = {"Confidence intervals (level " .. four(confidence) .. ", t " .. four(report.stats.critical) .. "):"}
    append(intervals, table_lines({"term", "Lower", "Upper"}, rows))
    rows, marks = {}, {}
    for index, column in ipairs(report.design.columns) do
        local value = report.coefficients[index]
        rows[index] = {column.name, four(value.robust_se), four(value.robust_t), probability(value.robust_p)}
        marks[index] = significance(value.robust_p)
    end
    return ordinary, intervals, table_lines({"term", "Std. Error", "t value", "Pr(>|t|)"}, rows, marks)
end
local function anova_tables(report)
    local rows, marks = {}, {}
    for index, entry in ipairs(report.anova) do
        rows[index] = {entry.name, entry.df, four(entry.ss), four(entry.ms), four(entry.f), probability(entry.p)}
        marks[index] = significance(entry.p)
    end
    rows[#rows + 1] = {"Residuals", report.stats.df, four(report.fit.rss), four(report.fit.rss / report.stats.df)}
    marks[#marks + 1] = ""
    local sequential = table_lines({"term", "Df", "Sum Sq", "Mean Sq", "F value", "Pr(>F)"}, rows, marks)
    rows, marks = {}, {}
    for index, entry in ipairs(report.marginal) do
        rows[index] = {entry.name, entry.df, four(entry.ss), four(entry.rss), four(entry.f), probability(entry.p)}
        marks[index] = significance(entry.p)
    end
    return sequential, table_lines({"term", "Df", "Sum Sq", "RSS", "F value", "Pr(>F)"}, rows, marks)
end
local function diagnostic_summary(report)
    local design, fitted, diagnostic, decisions = report.design, report.fit, report.diagnostics, report.decisions
    local bp, jb, reset = diagnostic.bp, diagnostic.jb, report.reset
    local outlier, counts = decisions.outlier, decisions.counts
    local lines = {
        "Diagnostics:",
        "Durbin-Watson: " .. four(diagnostic.dw) .. " (" .. decisions.dw_label .. ")",
        "Breusch-Pagan: " .. four(bp[1]) .. " on " .. bp[2] .. " DF, p-value: " .. probability(bp[3]) .. " (" .. decisions.bp_label .. ")",
        "Jarque-Bera: " .. four(jb[1]) .. " on 2 DF, p-value: " .. probability(jb[2]) .. ", skewness " .. four(jb[3]) .. ", kurtosis " .. four(jb[4]) .. " (" .. decisions.jb_label .. ")",
        "RESET (powers 2 and 3): F " .. four(reset[1]) .. " on " .. reset[2] .. " and " .. reset[3] .. " DF, p-value: " .. probability(reset[4]),
        "Outlier test: row " .. design.row_numbers[outlier] .. ", studentized " .. four(diagnostic.rows[outlier].studentized) .. ", unadjusted p-value: " .. probability(decisions.unadjusted) .. ", Bonferroni p-value: " .. probability(decisions.bonferroni),
        "Flagged rows: leverage " .. counts.H .. ", outlier " .. counts.O .. ", cooks " .. counts.C .. ", dffits " .. counts.F .. ", any " .. counts.any,
        "Largest Cook's distances:"
    }
    for _, index in ipairs(decisions.largest_cooks) do
        local row = diagnostic.rows[index]
        lines[#lines + 1] = "row " .. design.row_numbers[index] .. ": cooks_d " .. four(row.cooks) .. ", leverage " .. four(fitted.leverage[index]) .. ", studentized " .. four(row.studentized) .. ", flags " .. row.flags
    end
    lines[#lines + 1] = "Largest absolute DFBETAS:"
    append(lines, table_lines({"column", "row", "DFBETAS"}, decisions.largest_dfbetas))
    return lines
end
local function model_summary(report, total_rows, confidence)
    local design, fitted, stats = report.design, report.fit, report.stats
    local aliases, terms = {}, {}
    for _, column in ipairs(fitted.aliases) do
        aliases[#aliases + 1] = design.columns[column].name
    end
    for _, term in ipairs(design.model.terms) do
        terms[#terms + 1] = term.name
    end
    local alias_text = #aliases == 0 and "none" or table.concat(aliases, ", ")
    local q = stats.quantiles
    local ordinary, intervals, robust = coefficient_tables(report, confidence)
    local sequential, marginal = anova_tables(report)
    local lines = {
        "Model " .. report.number .. ": " .. design.model.original,
        "Terms: " .. table.concat(terms, ", "), "Weights: " .. (design.model.weight or "none"),
        "Observations: " .. fitted.n .. " used, " .. total_rows - fitted.n .. " dropped",
        "Columns: " .. fitted.p .. ", rank " .. fitted.rank .. ", aliased: " .. alias_text, "",
        "Residuals: Min " .. four(q[1]) .. ", 1Q " .. four(q[2]) .. ", Median " .. four(q[3]) .. ", 3Q " .. four(q[4]) .. ", Max " .. four(q[5]),
        "", "Coefficients:"
    }
    append(lines, ordinary)
    append(lines, {"---", "Signif. codes: 0 '***' 0.001 '**' 0.01 '*' 0.05 '.' 0.1 ' ' 1", "",
        "Residual standard error: " .. four(stats.sigma) .. " on " .. stats.df .. " degrees of freedom",
        "Multiple R-squared: " .. four(stats.r_squared) .. ", Adjusted R-squared: " .. four(stats.adjusted),
        "F-statistic: " .. four(stats.f) .. " on " .. fitted.rank - 1 .. " and " .. stats.df .. " DF, p-value: " .. probability(stats.p),
        "Log-likelihood: " .. four(stats.ll) .. ", AIC: " .. four(stats.aic) .. ", BIC: " .. four(stats.bic),
        "PRESS: " .. four(stats.press) .. ", Predicted R-squared: " .. four(stats.predicted), ""})
    append(lines, intervals)
    append(lines, {"", "Robust standard errors (HC3):"})
    append(lines, robust)
    append(lines, {"", "Analysis of variance (sequential):"})
    append(lines, sequential)
    append(lines, {"", "Marginal F tests (drop one term):"})
    append(lines, marginal)
    append(lines, {"", "Variance inflation factors:"})
    local rows, marks = {}, {}
    for index, entry in ipairs(report.vif) do
        rows[index], marks[index] = {entry.name, four(entry.value)}, entry.high and "high" or ""
    end
    append(lines, table_lines({"column", "VIF"}, rows, marks))
    lines[#lines + 1] = ""
    append(lines, diagnostic_summary(report))
    return lines
end
local function summary_report(data, reports, params)
    local lines = data_summary(data)
    for index, report in ipairs(reports) do
        if index > 1 then
            lines[#lines + 1] = ""
        end
        append(lines, model_summary(report, #data.rows, params.CONFIDENCE))
    end
    append(lines, {"", "Model comparison:"})
    local rows = {}
    for _, report in ipairs(reports) do
        local fitted, stats = report.fit, report.stats
        rows[#rows + 1] = {report.number, fitted.n, fitted.rank, four(stats.sigma), four(stats.r_squared), four(stats.adjusted), four(stats.predicted), four(stats.aic), four(stats.bic)}
    end
    append(lines, table_lines({"model", "n", "rank", "sigma", "R-squared", "Adj. R-squared", "Pred. R-squared", "AIC", "BIC"}, rows))
    append(lines, {"", "Prediction check:"})
    for _, report in ipairs(reports) do
        local check = report.prediction_check
        lines[#lines + 1] = "model " .. report.number .. ": " .. check.predicted .. " predicted, " .. check.actual .. " with actual values, RMSE " .. four(check.rmse) .. ", inside prediction interval " .. check.covered
    end
    return lines
end
local function diagnostics_csv(reports)
    local lines = {"model,row,fitted,residual,leverage,studentized,cooks_d,dffits,flags"}
    for _, report in ipairs(reports) do
        local fitted = report.fit
        for index, row in ipairs(report.diagnostics.rows) do
            lines[#lines + 1] = table.concat({report.number, report.design.row_numbers[index], four(fitted.fitted[index]), four(fitted.residual[index]), four(fitted.leverage[index]), four(row.studentized), four(row.cooks), four(row.dffits), row.flags}, ",")
        end
    end
    return lines
end
local function backward_selection(report, params)
    local design, terms, fitted = report.design, all_terms(report.design.model), report.fit
    local model, alpha = design.model, params.ALPHA_REMOVE
    local lines = {"Backward elimination (model 1, alpha " .. four(alpha) .. ", rows " .. #design.rows .. ")"}
    local step = 1
    while true do
        local _, aic = information_criteria(fitted)
        local degrees = fitted.n - fitted.rank
        lines[#lines + 1] = "Step " .. step .. ": " .. model:format(terms) .. " (RSS " .. four(fitted.rss) .. ", df " .. degrees .. ", AIC " .. four(aic) .. ")"
        if #terms == 0 then
            lines[#lines + 1] = "  stop: no removable terms"
            break
        end
        local results = marginal_tests(design, fitted, terms, params.RANK_TOL)
        local largest = results[1]
        for _, result in ipairs(results) do
            lines[#lines + 1] = "  - " .. result.name .. ": F " .. four(result.f) .. " on " .. result.df .. " and " .. degrees .. " DF, p-value " .. probability(result.p)
            if result.p > largest.p then
                largest = result
            end
        end
        if largest.p <= alpha then
            lines[#lines + 1] = "  stop: largest p-value " .. probability(largest.p) .. " is not above " .. four(alpha)
            break
        end
        lines[#lines + 1] = "  remove " .. largest.name
        terms = without(terms, largest.index)
        fitted = fit_subset(design, terms, params.RANK_TOL)
        step = step + 1
    end
    lines[#lines + 1] = "Final model: " .. model:format(terms)
    return lines
end
local function forward_selection(report, params)
    local design, terms = report.design, {}
    local model = design.model
    local lines = {"Forward selection by AIC (model 1, rows " .. #design.rows .. ")"}
    local step = 1
    while true do
        local fitted = fit_subset(design, terms, params.RANK_TOL)
        local _, aic = information_criteria(fitted)
        lines[#lines + 1] = "Step " .. step .. ": " .. model:format(terms) .. " (AIC " .. four(aic) .. ")"
        local candidates = model:candidates(terms)
        if #candidates == 0 then
            lines[#lines + 1] = "  stop: no candidate terms remain"
            break
        end
        local best
        for _, index in ipairs(candidates) do
            local candidate_terms = copy(terms)
            candidate_terms[#candidate_terms + 1] = index
            table.sort(candidate_terms)
            local candidate = fit_subset(design, candidate_terms, params.RANK_TOL)
            local _, candidate_aic = information_criteria(candidate)
            lines[#lines + 1] = "  + " .. model.terms[index].name .. ": AIC " .. four(candidate_aic)
            if not best or candidate_aic < best.aic then
                best = {index = index, aic = candidate_aic, terms = candidate_terms}
            end
        end
        if best.aic >= aic then
            lines[#lines + 1] = "  stop: no candidate lowers the AIC"
            break
        end
        lines[#lines + 1] = "  add " .. model.terms[best.index].name
        terms, step = best.terms, step + 1
    end
    lines[#lines + 1] = "Final model: " .. model:format(terms)
    return lines
end
local function best_subsets(report, params)
    local design, subsets = report.design, {}
    local model = design.model
    for mask = 0, (1 << #model.terms) - 1 do
        local terms = {}
        for index = 1, #model.terms do
            if (mask & (1 << (index - 1))) ~= 0 then
                terms[#terms + 1] = index
            end
        end
        if model:hierarchical(terms) then
            local fitted = fit_subset(design, terms, params.RANK_TOL)
            local _, aic, bic = information_criteria(fitted)
            subsets[#subsets + 1] = {bic = bic, mask = mask, aic = aic, rank = fitted.rank, terms = terms}
        end
    end
    table.sort(subsets, function(a, b)
        if a.bic ~= b.bic then
            return a.bic < b.bic
        end
        return a.mask < b.mask
    end)
    local lines = {"Best subsets by BIC (model 1, rows " .. #design.rows .. ", subsets " .. #subsets .. ")"}
    for position = 1, math.min(params.BEST_SUBSETS, #subsets) do
        local subset = subsets[position]
        lines[#lines + 1] = position .. ". BIC " .. four(subset.bic) .. ", AIC " .. four(subset.aic) .. ", rank " .. subset.rank .. ": " .. model:format(subset.terms)
    end
    return lines
end
local function selection_report(report, params)
    local lines = backward_selection(report, params)
    lines[#lines + 1] = ""
    append(lines, forward_selection(report, params))
    lines[#lines + 1] = ""
    append(lines, best_subsets(report, params))
    return lines
end
local function plot_grid(horizontal, vertical, lo, hi, width, height, limit)
    local grid = {}
    for row = 1, height do
        grid[row] = {}
        for column = 1, width do
            grid[row][column] = 0
        end
    end
    for index, x in ipairs(horizontal) do
        local column = math.min(math.floor((x - lo) / (hi - lo) * width), width - 1)
        local row = math.floor((limit - vertical[index]) / (2.0 * limit) * height)
        row = math.max(0, math.min(row, height - 1))
        grid[row + 1][column + 1] = grid[row + 1][column + 1] + 1
    end
    return grid
end
local function plot_frame(grid)
    local border = "+" .. string.rep("-", #grid[1]) .. "+"
    local lines = {border}
    for index, row in ipairs(grid) do
        local empty = index - 1 == #grid // 2 and "-" or "."
        local cells = {}
        for _, count in ipairs(row) do
            cells[#cells + 1] = count >= 10 and "*" or count > 0 and tostring(count) or empty
        end
        lines[#lines + 1] = "|" .. table.concat(cells) .. "|"
    end
    lines[#lines + 1] = border
    return lines
end
local function residual_plot(report, params)
    local width, height, limit = table.unpack(params.PLOT)
    local fitted, studentized = report.fit, {}
    local lo, hi = fitted.fitted[1], fitted.fitted[1]
    for index, row in ipairs(report.diagnostics.rows) do
        studentized[index] = row.studentized
        lo, hi = math.min(lo, fitted.fitted[index]), math.max(hi, fitted.fitted[index])
    end
    local grid = plot_grid(fitted.fitted, studentized, lo, hi, width, height, limit)
    local lines = {"Model " .. report.number .. ": studentized residuals vs fitted values",
        "fitted " .. four(lo) .. " to " .. four(hi) .. ", studentized " .. four(-limit) .. " to " .. four(limit)}
    append(lines, plot_frame(grid))
    local above, below, outside = 0, 0, 0
    for _, value in ipairs(studentized) do
        above = above + (value > 2.0 and 1 or 0)
        below = below + (value < -2.0 and 1 or 0)
        outside = outside + (math.abs(value) > limit and 1 or 0)
    end
    lines[#lines + 1] = "points: " .. fitted.n .. ", above +2: " .. above .. ", below -2: " .. below .. ", outside range: " .. outside
    lines[#lines + 1] = "Histogram of studentized residuals:"
    local counts, maximum = {}, 0
    for index, row in ipairs(grid) do
        local count = 0
        for _, value in ipairs(row) do
            count = count + value
        end
        counts[index], maximum = count, math.max(maximum, count)
    end
    for index, count in ipairs(counts) do
        local lower = limit - 2.0 * limit * index / height
        local upper = limit - 2.0 * limit * (index - 1) / height
        local length = (count * 40 + maximum - 1) // maximum
        local line = four(lower) .. " to " .. four(upper) .. ": " .. count
        if length > 0 then
            line = line .. " " .. string.rep("#", length)
        end
        lines[#lines + 1] = line
    end
    hi = 0.0
    for _, value in ipairs(fitted.leverage) do
        hi = math.max(hi, value)
    end
    append(lines, {"Model " .. report.number .. ": studentized residuals vs leverage",
        "leverage 0.0000 to " .. four(hi) .. ", studentized " .. four(-limit) .. " to " .. four(limit)})
    append(lines, plot_frame(plot_grid(fitted.leverage, studentized, 0.0, hi, width, height, limit)))
    return lines
end
local function save(name, lines)
    local file = assert(io.open("output/" .. name, "w"))
    for _, line in ipairs(lines) do
        file:write(line, "\n")
    end
    file:close()
end
local data = dataframe.read_csv("input/data.csv")
local prediction_data = dataframe.read_csv("input/predict.csv", data.kinds)
local params, reports = dataframe.read_params(), {}
for model_number, line in ipairs(dataframe.lines("input/model.txt")) do
    local design = formula.design(formula.parse(line), data)
    reports[#reports + 1] = analyze_model(model_number, design, params, prediction_data)
end
local predictions = {"model,row,fit,se_fit,conf_lower,conf_upper,pred_lower,pred_upper,actual,error,covered"}
local plots = {}
for index, report in ipairs(reports) do
    append(predictions, report.predictions)
    if index > 1 then
        plots[#plots + 1] = ""
    end
    append(plots, residual_plot(report, params))
end
save("summary.txt", summary_report(data, reports, params))
save("diagnostics.csv", diagnostics_csv(reports))
save("selection.txt", selection_report(reports[1], params))
save("predictions.csv", predictions)
save("residual_plot.txt", plots)
