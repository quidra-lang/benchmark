local dataset = require("dataset")
local kernels = require("kernels")
local loess = require("loess")
local spline = require("spline")
local selection = require("selection")
local function append(target, values)
    for _, value in ipairs(values) do
        target[#target + 1] = value
    end
end
local function positions_values(points)
    local positions, values = {}, {}
    for i, point in ipairs(points) do
        positions[i], values[i] = point[1], point[2] / 100
    end
    return positions, values
end
local function rss(values, fitted)
    local total = 0.0
    for i, value in ipairs(values) do
        local residual = value - fitted[i]
        total = total + residual * residual
    end
    return total
end
local function linear(points)
    local positions, values = positions_values(points)
    local x, fitted, leverage = {}, {}, {}
    for i, position in ipairs(positions) do
        x[i] = position / 100
    end
    local n = #points
    local xbar, ybar = selection.sum(x) / n, selection.sum(values) / n
    local sxx, sxy = 0.0, 0.0
    for i, value in ipairs(x) do
        sxx = sxx + (value - xbar) * (value - xbar)
        sxy = sxy + (value - xbar) * (values[i] - ybar)
    end
    local slope = sxy / sxx
    local intercept = ybar - slope * xbar
    for i, value in ipairs(x) do
        fitted[i] = intercept + slope * value
        leverage[i] = 1 / n + (value - xbar) * (value - xbar) / sxx
    end
    local model = {fitted = fitted, leverage = leverage, edf = 2.0}
    function model:estimate(position)
        return intercept + slope * (position / 100)
    end
    function model:weights(position)
        local result = {}
        for i, value in ipairs(x) do
            result[i] = 1 / n + (position / 100 - xbar) * (value - xbar) / sxx
        end
        return result
    end
    return model
end
local function running(points, width, use_median)
    local windows, fitted, leverage = {}, {}, {}
    local n, half = #points, (width - 1) // 2
    for i = 1, n do
        local radius = math.min(half, i - 1, n - i)
        local values, total = {}, 0
        for j = i - radius, i + radius do
            values[#values + 1] = points[j][2]
            total = total + points[j][2]
        end
        windows[i] = {i - radius, i + radius}
        if use_median then
            table.sort(values)
            fitted[i] = values[radius + 1] / 100
        else
            fitted[i] = total / (100 * #values)
        end
        leverage[i] = 1 / #values
    end
    local model = {fitted = fitted}
    if not use_median then
        model.leverage, model.edf = leverage, selection.sum(leverage)
    end
    local function nearest(position)
        local best, distance = 1, math.abs(points[1][1] - position)
        for i = 2, n do
            local delta = math.abs(points[i][1] - position)
            if delta < distance then
                best, distance = i, delta
            end
        end
        return best
    end
    function model:estimate(position)
        return fitted[nearest(position)]
    end
    function model:weights(position)
        local window, result = windows[nearest(position)], {}
        for i = 1, n do
            result[i] = i >= window[1] and i <= window[2] and 1 / (window[2] - window[1] + 1) or 0.0
        end
        return result
    end
    return model
end
local function pava(points, direction)
    local blocks = {}
    for i, point in ipairs(points) do
        blocks[#blocks + 1] = {i, i, point[2], 1}
        while #blocks >= 2 do
            local a, b = blocks[#blocks - 1], blocks[#blocks]
            local left, right = a[3] * b[4], b[3] * a[4]
            local violates = direction == "increasing" and left > right or direction == "decreasing" and left < right
            if not violates then
                break
            end
            blocks[#blocks] = nil
            blocks[#blocks] = {a[1], b[2], a[3] + b[3], a[4] + b[4]}
        end
    end
    local fitted = {}
    for _, block in ipairs(blocks) do
        local value = block[3] / (100 * block[4])
        for i = block[1], block[2] do
            fitted[i] = value
        end
    end
    return fitted, blocks
end
local function isotonic(points, mode)
    local model = {mode = mode, direction = mode}
    if mode == "auto" then
        local increasing, iblocks = pava(points, "increasing")
        local decreasing, dblocks = pava(points, "decreasing")
        local _, values = positions_values(points)
        model.rss_increasing, model.rss_decreasing = rss(values, increasing), rss(values, decreasing)
        if model.rss_increasing <= model.rss_decreasing then
            model.direction, model.fitted, model.blocks = "increasing", increasing, iblocks
        else
            model.direction, model.fitted, model.blocks = "decreasing", decreasing, dblocks
        end
    else
        model.fitted, model.blocks = pava(points, mode)
    end
    model.edf = #model.blocks + 0.0
    function model:estimate(position)
        local index = 1
        for i, point in ipairs(points) do
            if point[1] <= position then
                index = i
            else
                break
            end
        end
        return self.fitted[index]
    end
    return model
end
local function methods_in_order(settings)
    local methods = {"linear", "running_mean", "running_median"}
    for _, prefix in ipairs({"nw_", "ll_"}) do
        for _, name in ipairs(settings.KERNELS) do
            methods[#methods + 1] = prefix .. name
        end
    end
    for _, degree in ipairs(settings.LOESS_DEGREES) do
        methods[#methods + 1] = "loess" .. degree
    end
    append(methods, {"spline", "isotonic"})
    return methods
end
local function parameters(method, settings)
    if method:sub(1, 8) == "running_" then
        return settings.WINDOWS
    elseif method:sub(1, 3) == "nw_" or method:sub(1, 3) == "ll_" then
        return settings.BANDWIDTHS
    elseif method:sub(1, 5) == "loess" then
        return settings.SPANS
    elseif method == "spline" then
        return settings.LAMBDAS
    end
    return {}
end
local function fit_model(method, parameter, points, settings, direction, robust, diagnostics)
    if method == "linear" then
        return linear(points)
    elseif method:sub(1, 8) == "running_" then
        return running(points, tonumber(parameter), method == "running_median")
    elseif method == "isotonic" then
        return isotonic(points, direction)
    end
    local positions, values = positions_values(points)
    if method:sub(1, 3) == "nw_" or method:sub(1, 3) == "ll_" then
        return kernels.fit(positions, values, dataset.hundredths(parameter), method:sub(4), method:sub(1, 3) == "ll_", diagnostics)
    elseif method:sub(1, 5) == "loess" then
        return loess.fit(positions, values, dataset.hundredths(parameter), tonumber(method:sub(6)), robust and settings.ROBUST_ITERATIONS or 0, diagnostics)
    end
    return spline.fit(positions, values, tonumber(parameter), diagnostics)
end
local function validation(method, parameter, points, settings, direction, folds)
    local predictions = {}
    for group = 0, folds - 1 do
        local training = {}
        for i, point in ipairs(points) do
            if (i - 1) % folds ~= group then
                training[#training + 1] = point
            end
        end
        local model = fit_model(method, parameter, training, settings, direction, false, false)
        for i = group + 1, #points, folds do
            predictions[i] = model:estimate(points[i][1])
        end
    end
    return predictions
end
local function select_models(points, settings, methods, mode)
    local _, observed = positions_values(points)
    local entries = {}
    for _, method in ipairs(methods) do
        local candidates = {}
        for _, parameter in ipairs(parameters(method, settings)) do
            local candidate = fit_model(method, parameter, points, settings, mode, false, true)
            local score
            if method == "spline" then
                score = selection.gcv(observed, candidate.fitted, candidate.edf)
            else
                score = selection.cv(observed, validation(method, parameter, points, settings, mode, #points))
            end
            candidates[#candidates + 1] = {parameter = parameter, score = score, edf = candidate.edf}
        end
        local best = #candidates > 0 and selection.choose(candidates) or nil
        local parameter = best and candidates[best].parameter or (method == "linear" and "-" or mode)
        if best then
            candidates[best].selected = true
        end
        local model = fit_model(method, parameter, points, settings, mode, true, true)
        local direction = method == "isotonic" and model.direction or mode
        if method == "isotonic" then
            parameter = direction
        end
        local loo
        if best and method ~= "spline" then
            loo = candidates[best].score
        else
            loo = selection.cv(observed, validation(method, parameter, points, settings, direction, #points))
        end
        entries[method] = {model = model, parameter = parameter, loo = loo, candidates = candidates,
            kfold = selection.cv(observed, validation(method, parameter, points, settings, direction, settings.CV_FOLDS)),
            gcv = method == "spline" and candidates[best].score or nil}
    end
    return entries
end
local function quantiles(residuals)
    local ordered, result = {table.unpack(residuals)}, {}
    table.sort(ordered)
    for k = 0, 4 do
        local j, remainder = ((#ordered - 1) * k) // 4, ((#ordered - 1) * k) % 4
        local value = ordered[j + 1]
        if remainder ~= 0 then
            value = value + remainder / 4 * (ordered[j + 2] - ordered[j + 1])
        end
        result[#result + 1] = value
    end
    return result
end
local function diagnostics(method, model, observed, grid_values, grid_count, linear_rss)
    local n, residuals, centered = #observed, {}, {}
    local mean = selection.sum(observed) / n
    local tss = 0.0
    for i, value in ipairs(observed) do
        residuals[i] = value - model.fitted[i]
        tss = tss + (value - mean) * (value - mean)
    end
    local total = 0.0
    for _, residual in ipairs(residuals) do
        total = total + residual * residual
    end
    local edf, df, rse, nonlinear = model.edf
    if edf then
        df, rse = n - edf, math.sqrt(total / (n - edf))
        if method ~= "linear" and edf > 2 then
            nonlinear = ((linear_rss - total) / (edf - 2)) / (total / df)
        end
    end
    local residual_mean, denominator, acf = selection.sum(residuals) / n, 0.0, {}
    for i, value in ipairs(residuals) do
        centered[i] = value - residual_mean
        denominator = denominator + centered[i] * centered[i]
    end
    for lag = 1, 5 do
        local sum = 0.0
        for i = 1, n - lag do
            sum = sum + centered[i] * centered[i + lag]
        end
        acf[lag] = sum / denominator
    end
    local dw, largest, runs, positive, negative, previous_sign = 0.0, 1, 0, 0, 0, nil
    for i, value in ipairs(residuals) do
        if i > 1 then
            dw = dw + (value - residuals[i - 1]) * (value - residuals[i - 1])
        end
        if math.abs(value) > math.abs(residuals[largest]) then
            largest = i
        end
        if value ~= 0 then
            local sign = value > 0
            if sign then
                positive = positive + 1
            else
                negative = negative + 1
            end
            if previous_sign == nil or sign ~= previous_sign then
                runs = runs + 1
            end
            previous_sign = sign
        end
    end
    local count, product = positive + negative, 2 * positive * negative
    local runs_mean = 1 + product / count
    local variance = product * (product - count) / (count * count * (count - 1))
    local turning, previous_value, previous_difference = 0, nil, nil
    for i = 1, grid_count do
        local value = grid_values[i]
        if value ~= nil then
            if previous_value ~= nil and value ~= previous_value then
                local sign = value > previous_value
                if previous_difference ~= nil and sign ~= previous_difference then
                    turning = turning + 1
                end
                previous_difference = sign
            end
            previous_value = value
        end
    end
    return {residuals = residuals, rss = total, edf = edf, df = df, rse = rse, r2 = 1 - total / tss,
        nonlinear = nonlinear, acf = acf, dw = dw / total, runs = runs, positive = positive, negative = negative,
        runs_z = (runs - runs_mean) / math.sqrt(variance), largest = largest, quantiles = quantiles(residuals), turning = turning}
end
local function squared_sum(values)
    local sum = 0.0
    for _, value in ipairs(values) do
        sum = sum + value * value
    end
    return sum
end
local function analyze(points, settings, methods, mode, generator)
    local positions, values = positions_values(points)
    local grid = {}
    for k = 0, settings.GRID_POINTS - 1 do
        grid[k + 1] = positions[1] + k * (positions[#positions] - positions[1]) // (settings.GRID_POINTS - 1)
    end
    local entries = select_models(points, settings, methods, mode)
    local linear_rss = rss(values, entries.linear.model.fitted)
    local ranking = {}
    for index, method in ipairs(methods) do
        local entry = entries[method]
        entry.grid_values = {}
        entry.index = index
        for i, position in ipairs(grid) do
            entry.grid_values[i] = entry.model:estimate(position)
        end
        entry.stats = diagnostics(method, entry.model, values, entry.grid_values, #grid, linear_rss)
        ranking[index] = method
    end
    table.sort(ranking, function(a, b)
        return entries[a].loo < entries[b].loo or (entries[a].loo == entries[b].loo and entries[a].index < entries[b].index)
    end)
    local agreements = {}
    for _, method in ipairs(methods) do
        if method ~= ranking[1] then
            local count, sum, maximum, at = 0, 0.0, -1.0, 1
            for i = 1, #grid do
                local a, b = entries[method].grid_values[i], entries[ranking[1]].grid_values[i]
                if a ~= nil and b ~= nil then
                    local delta = math.abs(a - b)
                    count, sum = count + 1, sum + delta * delta
                    if delta > maximum then
                        maximum, at = delta, i
                    end
                end
            end
            agreements[method] = {count, math.sqrt(sum / count), maximum, grid[at]}
        end
    end
    local slopes = {}
    local sv = entries.spline.grid_values
    for i = 2, #grid - 1 do
        slopes[#slopes + 1] = {(sv[i + 1] - sv[i - 1]) / ((grid[i + 1] - grid[i - 1]) / 100), grid[i]}
    end
    local high, low = slopes[1], slopes[1]
    for _, slope in ipairs(slopes) do
        if slope[1] > high[1] then
            high = slope
        end
        if slope[1] < low[1] then
            low = slope
        end
    end
    local outlier = {standardized = {}, cooks = {}, outliers = {}, influential = {}}
    for _, method in ipairs(ranking) do
        if entries[method].model.leverage then
            outlier.method = method
            break
        end
    end
    local entry = entries[outlier.method]
    for i, leverage in ipairs(entry.model.leverage) do
        if leverage < 1 then
            local t = entry.stats.residuals[i] / (entry.stats.rse * math.sqrt(1 - leverage))
            outlier.standardized[i] = t
            outlier.cooks[i] = t * t * leverage / ((1 - leverage) * entry.model.edf)
            if math.abs(t) > settings.OUTLIER_THRESHOLD then
                outlier.outliers[#outlier.outliers + 1] = i
            end
            outlier.influential[#outlier.influential + 1] = i
        end
    end
    table.sort(outlier.outliers, function(a, b)
        local x, y = math.abs(outlier.standardized[a]), math.abs(outlier.standardized[b])
        return x > y or (x == y and a < b)
    end)
    table.sort(outlier.influential, function(a, b)
        return outlier.cooks[a] > outlier.cooks[b] or (outlier.cooks[a] == outlier.cooks[b] and a < b)
    end)
    while #outlier.influential > 3 do
        table.remove(outlier.influential)
    end
    local bands, summaries = {}, {}
    for _, method in ipairs(settings.BAND_METHODS) do
        local own, rows = entries[method], {}
        local se_sum, count, covered = 0.0, 0, 0
        for i, position in ipairs(grid) do
            local value = own.model:estimate(position)
            rows[i] = {}
            if value ~= nil then
                local se = own.stats.rse * math.sqrt(squared_sum(own.model:weights(position)))
                rows[i] = {value, se, value - settings.BAND_Z * se, value + settings.BAND_Z * se}
                se_sum, count = se_sum + se, count + 1
            end
        end
        for i, position in ipairs(positions) do
            local se = own.stats.rse * math.sqrt(squared_sum(own.model:weights(position)))
            if math.abs(own.stats.residuals[i]) <= settings.BAND_Z * math.sqrt(own.stats.rse * own.stats.rse + se * se) then
                covered = covered + 1
            end
        end
        bands[method], summaries[method] = rows, {se_sum / count, covered}
    end
    local own, estimates = entries.spline, {}
    local residual_mean = selection.sum(own.stats.residuals) / #points
    local centered = {}
    for i, residual in ipairs(own.stats.residuals) do
        centered[i] = residual - residual_mean
    end
    for i = 1, #grid do
        estimates[i] = {}
    end
    local repetitions, trim = settings.BOOTSTRAP[1], settings.BOOTSTRAP[2]
    for b = 1, repetitions do
        local response = {}
        for i, value in ipairs(own.model.fitted) do
            generator.state = 48271 * generator.state % 2147483647
            response[i] = value + centered[generator.state % #centered + 1]
        end
        local fit = own.model:fit_values(response)
        for i, position in ipairs(grid) do
            estimates[i][b] = own.model:evaluate_fit(fit, position)
        end
    end
    bands.spline_bootstrap = {}
    for i, estimates_at in ipairs(estimates) do
        local mean, sum = selection.sum(estimates_at) / repetitions, 0.0
        for _, value in ipairs(estimates_at) do
            sum = sum + (value - mean) * (value - mean)
        end
        table.sort(estimates_at)
        bands.spline_bootstrap[i] = {own.model:estimate(grid[i]), math.sqrt(sum / (repetitions - 1)),
            estimates_at[trim + 1], estimates_at[repetitions - trim]}
    end
    return {points = points, grid = grid, entries = entries, ranking = ranking, agreement = agreements,
        slope = {high[1], high[2], low[1], low[2]}, outlier = outlier, bands = bands, summaries = summaries}
end
local function real(value, places)
    if value == nil then
        return "NA"
    end
    places = places or 4
    local result = string.format("%." .. places .. "f", value)
    local zero = string.format("%." .. places .. "f", 0)
    return result == "-" .. zero and zero or result
end
local function position(value)
    local magnitude = math.abs(value)
    return (value < 0 and "-" or "") .. string.format("%d.%02d", magnitude // 100, magnitude % 100)
end
local function real_list(values)
    local fields = {}
    for i, value in ipairs(values) do
        fields[i] = real(value)
    end
    return table.concat(fields, " ")
end
local function bounds(points)
    local low, high = points[1][2], points[1][2]
    for _, point in ipairs(points) do
        low, high = math.min(low, point[2]), math.max(high, point[2])
    end
    return low, high
end
local function diagnostics_block(name, analysis, methods, settings)
    local points, entries, ranking = analysis.points, analysis.entries, analysis.ranking
    local low, high = bounds(points)
    local lines = {"series " .. name .. " n " .. #points .. " x " .. position(points[1][1]) .. " " .. position(points[#points][1]) .. " y " .. position(low) .. " " .. position(high)}
    for _, method in ipairs(methods) do
        local entry = entries[method]
        local stats = entry.stats
        local first = "method " .. method .. " parameter " .. entry.parameter .. " loo " .. real(entry.loo)
        if method == "spline" then
            first = first .. " gcv " .. real(entry.gcv)
        end
        append(lines, {first,
            "  rss " .. real(stats.rss) .. " edf " .. real(stats.edf) .. " df " .. real(stats.df) .. " rse " .. real(stats.rse) .. " r2 " .. real(stats.r2) .. " f_nonlinear " .. real(stats.nonlinear),
            "  acf " .. real_list(stats.acf) .. " dw " .. real(stats.dw),
            "  runs " .. stats.runs .. " positive " .. stats.positive .. " negative " .. stats.negative .. " z " .. real(stats.runs_z),
            "  max_residual " .. real(stats.residuals[stats.largest]) .. " at " .. position(points[stats.largest][1]) .. " turning " .. stats.turning,
            "  quantiles " .. real_list(stats.quantiles)})
        if method:sub(1, 5) == "loess" then
            for _, record in ipairs(entry.model.records) do
                lines[#lines + 1] = "  robust " .. record[1] .. " scale " .. real(record[2]) .. " zero_weight " .. record[3] .. " max_change " .. real(record[4])
            end
            local zeros = {}
            for i, weight in ipairs(entry.model.rho) do
                if weight == 0 then
                    zeros[#zeros + 1] = position(points[i][1])
                end
            end
            lines[#lines + 1] = "  zero_weight_points " .. (#zeros > 0 and table.concat(zeros, " ") or "none")
        end
    end
    lines[#lines + 1] = "ranking"
    for rank, method in ipairs(ranking) do
        lines[#lines + 1] = "  " .. rank .. " " .. method .. " " .. real(entries[method].loo) .. " kfold " .. real(entries[method].kfold)
    end
    lines[#lines + 1] = "agreement with " .. ranking[1]
    for _, method in ipairs(methods) do
        if method ~= ranking[1] then
            local values = analysis.agreement[method]
            lines[#lines + 1] = "  " .. method .. " points " .. values[1] .. " rms " .. real(values[2]) .. " max " .. real(values[3]) .. " at " .. position(values[4])
        end
    end
    local slope, outlier = analysis.slope, analysis.outlier
    lines[#lines + 1] = "slope spline max " .. real(slope[1]) .. " at " .. position(slope[2]) .. " min " .. real(slope[3]) .. " at " .. position(slope[4])
    local entry = entries[outlier.method]
    lines[#lines + 1] = "outliers method " .. outlier.method .. " threshold " .. real(settings.OUTLIER_THRESHOLD, 2)
    for _, i in ipairs(outlier.outliers) do
        lines[#lines + 1] = "  x " .. position(points[i][1]) .. " y " .. position(points[i][2]) .. " fit " .. real(entry.model.fitted[i]) .. " residual " .. real(entry.stats.residuals[i]) .. " standardized " .. real(outlier.standardized[i])
    end
    if #outlier.outliers == 0 then
        lines[#lines + 1] = "  none"
    end
    lines[#lines + 1] = "influence method " .. outlier.method
    for _, i in ipairs(outlier.influential) do
        lines[#lines + 1] = "  x " .. position(points[i][1]) .. " lev " .. real(entry.model.leverage[i]) .. " cook " .. real(outlier.cooks[i])
    end
    lines[#lines + 1] = "bands"
    for _, method in ipairs(settings.BAND_METHODS) do
        local summary = analysis.summaries[method]
        lines[#lines + 1] = "  " .. method .. " mean_se " .. real(summary[1]) .. " coverage " .. summary[2] .. " of " .. #points
    end
    return lines
end
local function isotonic_block(name, analysis)
    local entry, points = analysis.entries.isotonic, analysis.points
    local model = entry.model
    local first = "series " .. name .. " direction " .. model.direction .. " mode " .. model.mode
    if model.mode == "auto" then
        first = first .. " rss_increasing " .. real(model.rss_increasing) .. " rss_decreasing " .. real(model.rss_decreasing)
    end
    local lines = {first, "blocks " .. #model.blocks .. " rss " .. real(entry.stats.rss) .. " loo " .. real(entry.loo)}
    for j, block in ipairs(model.blocks) do
        lines[#lines + 1] = "block " .. j .. " x " .. position(points[block[1]][1]) .. " " .. position(points[block[2]][1]) .. " count " .. block[4] .. " value " .. real(block[3] / (100 * block[4]))
    end
    return lines
end
local function empty_grid(width, height)
    local grid = {}
    for row = 1, height do
        grid[row] = {}
        for column = 1, width do
            grid[row][column] = " "
        end
    end
    return grid
end
local function framed(grid)
    local border, lines = "+" .. string.rep("-", #grid[1]) .. "+", {}
    lines[1] = border
    for _, row in ipairs(grid) do
        lines[#lines + 1] = "|" .. table.concat(row) .. "|"
    end
    lines[#lines + 1] = border
    return lines
end
local function plot_block(name, analysis, settings)
    local points, entries = analysis.points, analysis.entries
    local width, height = settings.PLOT_SIZE[1], settings.PLOT_SIZE[2]
    local xa, xb = points[1][1], points[#points][1]
    local ya, yb = bounds(points)
    local columns, grid = {}, empty_grid(width, height)
    for i, point in ipairs(points) do
        columns[i] = math.min(width - 1, width * (point[1] - xa) // (xb - xa)) + 1
        local row = math.min(height - 1, height * (yb - point[2]) // (yb - ya)) + 1
        grid[row][columns[i]] = "."
    end
    local legend = {"legend . data"}
    for number, method in ipairs(settings.PLOT_METHODS) do
        legend[#legend + 1] = number .. " " .. method
        local digit = tostring(number)
        for column = 0, width - 1 do
            local at = xa + (2 * column + 1) * (xb - xa) // (2 * width)
            local value = entries[method].model:estimate(at)
            if value ~= nil then
                local pi = height * (yb / 100 - value) / (yb / 100 - ya / 100)
                local row = math.max(0, math.min(height - 1, math.floor(pi))) + 1
                local old = grid[row][column + 1]
                grid[row][column + 1] = (old == " " or old == "." or old == digit) and digit or "*"
            end
        end
    end
    local lines = {"plot " .. name .. " size " .. width .. "x" .. height .. " x " .. position(xa) .. " " .. position(xb) .. " y " .. position(ya) .. " " .. position(yb), table.concat(legend, " ")}
    append(lines, framed(grid))
    local data, curve, overlap = 0, 0, 0
    for _, row in ipairs(grid) do
        for _, value in ipairs(row) do
            if value == "." then
                data = data + 1
            elseif value == "*" then
                overlap = overlap + 1
            elseif value:match("%d") then
                curve = curve + 1
            end
        end
    end
    lines[#lines + 1] = "cells data " .. data .. " curve " .. curve .. " overlap " .. overlap
    local method, limit = analysis.ranking[1], 0.0
    local residuals = entries[method].stats.residuals
    for _, value in ipairs(residuals) do
        limit = math.max(limit, math.abs(value))
    end
    grid = empty_grid(width, height)
    for column = 1, width do
        grid[height // 2 + 1][column] = "-"
    end
    for i, value in ipairs(residuals) do
        local row = math.max(0, math.min(height - 1, math.floor(height * ((limit - value) / (2 * limit))))) + 1
        grid[row][columns[i]] = "o"
    end
    append(lines, {"", "residuals " .. name .. " method " .. method .. " limit " .. real(limit)})
    append(lines, framed(grid))
    append(lines, {"", "histogram " .. name .. " method " .. analysis.outlier.method})
    local counts = {}
    for i = 0, 13 do
        counts[i] = 0
    end
    for i = 1, #points do
        local value = analysis.outlier.standardized[i]
        if value ~= nil then
            local bin = value < -3 and 0 or (value >= 3 and 13 or 1 + math.floor((value + 3) / 0.5))
            counts[bin] = counts[bin] + 1
        end
    end
    for i = 0, 13 do
        local lower = i == 0 and "-inf" or real(-3 + 0.5 * (i - 1), 2)
        local upper = i == 13 and "inf" or real(-3 + 0.5 * i, 2)
        lines[#lines + 1] = lower .. " " .. upper .. " " .. counts[i] .. " |" .. string.rep("#", counts[i])
    end
    return lines
end
local function join_blocks(blocks)
    local lines = {}
    for i, block in ipairs(blocks) do
        if i > 1 then
            lines[#lines + 1] = ""
        end
        append(lines, block)
    end
    return lines
end
local function write_lines(name, lines)
    local file = assert(io.open("output/" .. name, "w"))
    file:write(table.concat(lines, "\n"), "\n")
    file:close()
end
local series, names, tests, settings = dataset.read()
local methods = methods_in_order(settings)
local analyses, generator = {}, {state = settings.BOOTSTRAP[3]}
for i, name in ipairs(names) do
    analyses[name] = analyze(series[name], settings, methods, settings.ISOTONIC[i], generator)
end
local selection_output = {"series,method,parameter,score,edf,selected"}
local fit_output = {"series,x," .. table.concat(methods, ",")}
local prediction_output = {fit_output[1]}
local band_output = {"series,method,x,fit,se,lower,upper"}
local diagnostic_blocks, isotonic_blocks, plot_blocks = {}, {}, {}
for _, name in ipairs(names) do
    local analysis = analyses[name]
    for _, method in ipairs(methods) do
        for _, candidate in ipairs(analysis.entries[method].candidates) do
            selection_output[#selection_output + 1] = table.concat({name, method, candidate.parameter, real(candidate.score), real(candidate.edf), candidate.selected and "1" or "0"}, ",")
        end
    end
    for i, at in ipairs(analysis.grid) do
        local fields = {name, position(at)}
        for _, method in ipairs(methods) do
            fields[#fields + 1] = real(analysis.entries[method].grid_values[i])
        end
        fit_output[#fit_output + 1] = table.concat(fields, ",")
    end
    local band_methods = {table.unpack(settings.BAND_METHODS)}
    band_methods[#band_methods + 1] = "spline_bootstrap"
    for _, method in ipairs(band_methods) do
        for i, at in ipairs(analysis.grid) do
            local fields, row = {name, method, position(at)}, analysis.bands[method][i]
            for j = 1, 4 do
                fields[#fields + 1] = real(row[j])
            end
            band_output[#band_output + 1] = table.concat(fields, ",")
        end
    end
    diagnostic_blocks[#diagnostic_blocks + 1] = diagnostics_block(name, analysis, methods, settings)
    isotonic_blocks[#isotonic_blocks + 1] = isotonic_block(name, analysis)
end
for _, point in ipairs(tests) do
    local fields = {point[1], position(point[2])}
    for _, method in ipairs(methods) do
        fields[#fields + 1] = real(analyses[point[1]].entries[method].model:estimate(point[2]))
    end
    prediction_output[#prediction_output + 1] = table.concat(fields, ",")
end
for _, name in ipairs(settings.PLOT_SERIES) do
    plot_blocks[#plot_blocks + 1] = plot_block(name, analyses[name], settings)
end
os.execute('mkdir -p output')
write_lines("selection.csv", selection_output)
write_lines("fits.csv", fit_output)
write_lines("predictions.csv", prediction_output)
write_lines("bands.csv", band_output)
write_lines("diagnostics.txt", join_blocks(diagnostic_blocks))
write_lines("isotonic.txt", join_blocks(isotonic_blocks))
write_lines("plots.txt", join_blocks(plot_blocks))
