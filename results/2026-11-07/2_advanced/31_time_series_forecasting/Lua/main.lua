local series_io, decomposition, smoothing, ar, evaluation = require("series_io"), require("decomposition"), require("smoothing"), require("autoregression"), require("evaluation")
local real, total, mean, variance = series_io.real, decomposition.total, decomposition.mean, decomposition.sample_variance
local methods = {"naive", "snaive", "drift", "ses", "holt", "damped", "hw_add", "hw_mult", "decomp_add", "decomp_mult", "ar"}
local models_order = {table.unpack(methods)}
models_order[#models_order + 1] = "combo"
local parameters_for = {ses = {"alpha"}, holt = {"alpha", "beta"}, damped = {"alpha", "beta", "phi"}, hw_add = {"alpha", "beta", "gamma"}, hw_mult = {"alpha", "beta", "gamma"}}
local function copy(values)
    return {table.unpack(values)}
end
local function slice(values, first, last)
    return {table.unpack(values, first, last or #values)}
end
local function map(values, operation)
    local result = {}
    for i, value in ipairs(values) do
        result[i] = operation(value, i)
    end
    return result
end
local function append(destination, source)
    for _, value in ipairs(source) do
        destination[#destination + 1] = value
    end
end
local function rmse(errors)
    return math.sqrt(total(map(errors, function(value)
        return value * value
    end)) / #errors)
end
local function reals(values)
    return table.concat(map(values, real), " ")
end
local function count_keys(values)
    local count = 0
    for _ in pairs(values) do
        count = count + 1
    end
    return count
end
local function future_periods(last, horizon)
    local periods = {}
    for i = 1, horizon do
        last = series_io.next_month(last)
        periods[i] = last
    end
    return periods
end
local function prepare(record, events, settings)
    local raw, values, missing, past, kinds, grouped, outliers, lifts = record.raw, copy(record.raw), {}, {}, {}, {}, {}, {}
    local left = 1
    while left < #raw do
        local right = left + 1
        while raw[right] == false do
            right = right + 1
        end
        for t = left + 1, right - 1 do
            values[t] = raw[left] + (raw[right] - raw[left]) * (t - left) / (right - left)
        end
        left = right
    end
    for t, value in ipairs(raw) do
        if value == false then
            missing[t] = true
        else
            values[t] = value * 1.0
        end
    end
    local components = decomposition.decompose(values, settings.season)
    local residuals = map(components.defined, function(t)
        return components.residual_add[t]
    end)
    local average, deviation = mean(residuals), math.sqrt(variance(residuals))
    for t, period in ipairs(record.periods) do
        local kind = events[period]
        if kind then
            past[t] = kind
            if not grouped[kind] then
                grouped[kind], kinds[#kinds + 1] = {}, kind
            end
            grouped[kind][#grouped[kind] + 1] = t
        end
    end
    for _, t in ipairs(components.defined) do
        local residual = components.residual_add[t]
        if not missing[t] and not past[t] and math.abs(residual - average) > settings.outlier * deviation then
            outliers[t] = (residual - average) / deviation
        end
    end
    for _, kind in ipairs(kinds) do
        local times = grouped[kind]
        lifts[kind] = {occurrences = #times, lift = mean(map(times, function(t)
            return values[t] / (components.trend[t] + components.additive[(t - 1) % settings.season + 1])
        end))}
    end
    local corrected = map(values, function(value, t)
        return (past[t] or outliers[t]) and components.trend[t] + components.additive[(t - 1) % settings.season + 1] or value
    end)
    local variance_r = variance(residuals)
    local variance_t = variance(map(components.defined, function(t)
        return components.trend[t] + components.residual_add[t]
    end))
    local variance_s = variance(map(components.defined, function(t)
        return components.additive[(t - 1) % settings.season + 1] + components.residual_add[t]
    end))
    return {name = record.name, periods = record.periods, raw = raw, values = values, corrected = corrected, missing = missing, past = past, kinds = kinds, outliers = outliers, lifts = lifts, components = components, future = future_periods(record.periods[#record.periods], settings.horizon), strength_trend = math.max(0.0, 1.0 - variance_r / variance_t), strength_seasonal = math.max(0.0, 1.0 - variance_r / variance_s)}
end
local function decomposition_prediction(model, time)
    local base, seasonal = model.intercept + model.slope * (time + 1), model.seasonal[time % model.season + 1]
    return model.name == "decomp_add" and base + seasonal or base * seasonal
end
local function fit_ar(model, values, settings)
    local selected, candidates = nil, {}
    for i, kind in ipairs(ar.kinds) do
        local transformed, offset = ar.difference(values, settings.season, kind)
        local average, spread = ar.autocorrelation(transformed, 0)
        local candidate = {kind = kind, differenced = transformed, offset = offset, average = average, variance = spread}
        candidates[i] = candidate
        if not selected or spread < selected.variance then
            selected = candidate
        end
    end
    model.kind, model.differenced, model.offset = selected.kind, selected.differenced, selected.offset
    local average, spread, correlations = ar.autocorrelation(selected.differenced, settings.max_lag)
    local coefficients, partial, variances = ar.durbin_levinson(correlations)
    local aic, order = {}, 0
    for p = 0, settings.max_ar do
        aic[p + 1] = #selected.differenced * math.log(spread * variances[p + 1]) + 2 * p
        if aic[p + 1] < aic[order + 1] then
            order = p
        end
    end
    model.average, model.order, model.sigma2, model.aic = average, order, spread * variances[order + 1], aic
    model.variances = map(candidates, function(candidate)
        return candidate.variance
    end)
    model.coefficients, model.correlations, model.partial = coefficients[order + 1], correlations, partial
    model.residuals = ar.residuals(selected.differenced, average, model.coefficients)
end
local function fit(name, values, settings)
    local season, count = settings.season, #values
    local model = {name = name, series = values, season = season}
    local errors = {}
    if name == "naive" or name == "snaive" or name == "drift" then
        local offset = name == "snaive" and season or 1
        model.slope = name == "drift" and (values[count] - values[1]) / (count - 1) or 0.0
        for t = offset + 1, count do
            errors[#errors + 1] = values[t] - values[t - offset] - model.slope
        end
    elseif parameters_for[name] then
        local keys, chosen, best_score = parameters_for[name], {}, nil
        local function search(position)
            if position > #keys then
                local residuals, states = smoothing.recurse(name, values, season, chosen)
                local score = total(map(residuals, function(value)
                    return value * value
                end))
                if not best_score or score < best_score then
                    best_score, model.parameters, model.states, errors = score, {}, states, residuals
                    for key, value in pairs(chosen) do
                        model.parameters[key] = value
                    end
                end
                return
            end
            local key = keys[position]
            for _, value in ipairs(settings[key]) do
                chosen[key] = value
                search(position + 1)
            end
        end
        search(1)
    elseif name == "decomp_add" or name == "decomp_mult" then
        local components = decomposition.decompose(values, season)
        model.seasonal = name == "decomp_add" and components.additive or components.multiplicative
        local adjusted = map(values, function(value, t)
            local index = model.seasonal[(t - 1) % season + 1]
            return name == "decomp_add" and value - index or value / index
        end)
        model.intercept, model.slope = decomposition.least_squares_line(adjusted)
        errors = map(values, function(value, t)
            return value - decomposition_prediction(model, t - 1)
        end)
    else
        fit_ar(model, values, settings)
        errors = model.residuals
    end
    model.residuals = errors
    return model
end
local function forecast(model, origin, steps)
    local name, values, season = model.name, model.series, model.season
    if name == "combo" then
        local predictions = map(model.members, function(member)
            return forecast(member, origin, steps)
        end)
        local result = {}
        for i = 1, steps do
            result[i] = total(map(predictions, function(row)
                return row[i]
            end)) / #predictions
        end
        return result
    end
    local result = {}
    if name == "naive" then
        for i = 1, steps do
            result[i] = values[origin]
        end
        return result
    end
    if name == "snaive" then
        for i = 1, steps do
            result[i] = values[origin - season + (i - 1) % season + 1]
        end
    elseif name == "drift" then
        local slope = (values[origin] - values[1]) / (origin - 1)
        for i = 1, steps do
            result[i] = values[origin] + i * slope
        end
    elseif parameters_for[name] then
        return smoothing.forecast(name, model.states[origin + 1], model.parameters, origin, steps, season)
    elseif name == "decomp_add" or name == "decomp_mult" then
        for i = 1, steps do
            result[i] = decomposition_prediction(model, origin + i - 1)
        end
    else
        return ar.forecast(values, model.differenced, model.offset, model.kind, model.average, model.coefficients, origin, steps, season)
    end
    return result
end
local function cross_validate(model, settings)
    local counts, squared, absolute = {}, {}, {}
    for i = 1, settings.horizon do
        counts[i], squared[i], absolute[i] = 0, 0.0, 0.0
    end
    for origin = settings.cv_start, #model.series - 1 do
        local predictions = forecast(model, origin, math.min(settings.horizon, #model.series - origin))
        for i, value in ipairs(predictions) do
            local error = model.series[origin + i] - value
            counts[i], squared[i], absolute[i] = counts[i] + 1, squared[i] + error * error, absolute[i] + math.abs(error)
        end
    end
    local sigma, mae = {}, {}
    for i = 1, settings.horizon do
        sigma[i], mae[i] = math.sqrt(squared[i] / counts[i]), absolute[i] / counts[i]
    end
    local count = 0
    for i = 1, settings.holdout do
        count = count + counts[i]
    end
    return {counts = counts, sigma = sigma, mae = mae, cv_rmse = math.sqrt(total(slice(squared, 1, settings.holdout)) / count)}
end
local function intervals(predicted, sigma, coefficients, multipliers)
    local rows = {}
    for i, value in ipairs(predicted) do
        local multiplier, error = multipliers and multipliers[i] or 1.0, sigma[i]
        rows[i] = {forecast = value * multiplier, lo80 = (value - coefficients[1] * error) * multiplier, hi80 = (value + coefficients[1] * error) * multiplier, lo95 = (value - coefficients[2] * error) * multiplier, hi95 = (value + coefficients[2] * error) * multiplier}
    end
    return rows
end
local function inventory_plan(model, demands, policy, settings)
    local protection, errors = policy.lead_time + policy.review, {}
    for origin = settings.cv_start, #model.series - protection do
        local predictions, total_error = forecast(model, origin, protection), 0.0
        for i, value in ipairs(predictions) do
            total_error = total_error + (model.series[origin + i] - value)
        end
        errors[#errors + 1] = total_error
    end
    local safety = policy.service * rmse(errors)
    local reviews, last = {}, 1
    for step = 1, #demands - protection + 1, policy.review do
        reviews[step], last = true, step
    end
    local on_hand, outstanding, receipts = policy.on_hand * 1.0, 0, {}
    local result = {safety = safety, rows = {}, orders = 0, ordered = 0, short_periods = 0}
    for step = 1, last - 1 + protection do
        local receipt = receipts[step] or 0
        receipts[step], on_hand, outstanding = nil, on_hand + receipt, outstanding - receipt
        local row = {step = step, receipt = receipt, demand = demands[step]}
        if reviews[step] then
            local position = on_hand + outstanding
            local target = total(slice(demands, step, step - 1 + protection)) + safety
            local quantity = math.max(0, math.ceil(target - position))
            row.review = {position = position, target = target, order = quantity}
            if quantity > 0 then
                result.orders, result.ordered, outstanding, receipts[step + policy.lead_time] = result.orders + 1, result.ordered + quantity, outstanding + quantity, quantity
            end
        end
        on_hand = on_hand - demands[step]
        row.on_hand, row.status = on_hand, on_hand < 0.0 and "short" or on_hand < safety and "low" or "ok"
        if row.status == "short" then
            result.short_periods = result.short_periods + 1
        end
        result.rows[#result.rows + 1] = row
        result.lowest = result.lowest and math.min(result.lowest, on_hand) or on_hand
    end
    result.average = mean(map(result.rows, function(row)
        return row.on_hand
    end))
    return result
end
local function diagnostics(errors, lags)
    local count, average = #errors, mean(errors)
    local centered = map(errors, function(value)
        return value - average
    end)
    local squares = total(map(centered, function(value)
        return value * value
    end))
    local m2 = squares / count
    local m3 = total(map(centered, function(value)
        return value * value * value
    end)) / count
    local m4 = total(map(centered, function(value)
        return value * value * value * value
    end)) / count
    local differences = {}
    for i = 2, count do
        differences[#differences + 1] = (errors[i] - errors[i - 1]) * (errors[i] - errors[i - 1])
    end
    local skewness, kurtosis = m3 / (m2 * math.sqrt(m2)), m4 / (m2 * m2) - 3.0
    return {count = count, mean = average, sd = math.sqrt(squares / (count - 1)), dw = total(differences) / total(map(errors, function(value)
        return value * value
    end)), skewness = skewness, kurtosis = kurtosis, jb = count / 6.0 * (skewness * skewness + kurtosis * kurtosis / 4.0), ljung_box = ar.ljung_box(errors, lags)}
end
local function analyze(record, events, policy, settings)
    local data = prepare(record, events, settings)
    local training_count = #data.values - settings.holdout
    local training, actual, models, cvs = slice(data.corrected, 1, training_count), slice(data.values, training_count + 1), {}, {}
    for _, name in ipairs(methods) do
        models[name] = fit(name, training, settings)
        cvs[name] = cross_validate(models[name], settings)
    end
    local indices = {}
    for i = 1, #methods do
        indices[i] = i
    end
    table.sort(indices, function(a, b)
        return cvs[methods[a]].cv_rmse < cvs[methods[b]].cv_rmse or cvs[methods[a]].cv_rmse == cvs[methods[b]].cv_rmse and a < b
    end)
    local selected, members, member_models = {}, {}, {}
    for i = 1, settings.combo do
        selected[methods[indices[i]]] = true
    end
    for _, name in ipairs(methods) do
        if selected[name] then
            members[#members + 1], member_models[#member_models + 1] = name, models[name]
        end
    end
    models.combo = {name = "combo", series = training, season = settings.season, members = member_models}
    cvs.combo = cross_validate(models.combo, settings)
    local scale, measures, holdout_rows = evaluation.seasonal_scale(training, settings.season), {}, {}
    for _, name in ipairs(models_order) do
        local predicted = forecast(models[name], training_count, #actual)
        local rows = intervals(predicted, cvs[name].sigma, settings.interval)
        local metrics = evaluation.accuracy(actual, predicted, scale)
        metrics.cv_rmse, metrics.cover80, metrics.cover95 = cvs[name].cv_rmse, 0, 0
        local winkler80, winkler95 = 0.0, 0.0
        for i, value in ipairs(actual) do
            local row = rows[i]
            if row.lo80 <= value and value <= row.hi80 then
                metrics.cover80 = metrics.cover80 + 1
            end
            if row.lo95 <= value and value <= row.hi95 then
                metrics.cover95 = metrics.cover95 + 1
            end
            winkler80 = winkler80 + evaluation.winkler(value, row.lo80, row.hi80, 10.0)
            winkler95 = winkler95 + evaluation.winkler(value, row.lo95, row.hi95, 40.0)
        end
        metrics.winkler80, metrics.winkler95 = winkler80 / #actual, winkler95 / #actual
        measures[name], holdout_rows[name] = metrics, rows
    end
    for _, name in ipairs(models_order) do
        measures[name].fva = 100.0 * (measures.naive.mae - measures[name].mae) / measures.naive.mae
    end
    local ranking = evaluation.rank_models(models_order, measures)
    for rank, name in ipairs(ranking) do
        measures[name].rank = rank
    end
    local best, final_fits, final = ranking[1], {}, nil
    local final_names = best == "combo" and members or {best}
    for _, name in ipairs(final_names) do
        final_fits[#final_fits + 1] = fit(name, data.corrected, settings)
    end
    final = best == "combo" and {name = "combo", series = data.corrected, season = settings.season, members = final_fits} or final_fits[1]
    local final_cv = cross_validate(final, settings)
    local future = forecast(final, #data.values, settings.horizon)
    local multipliers = map(data.future, function(period)
        return events[period] and data.lifts[events[period]].lift or 1.0
    end)
    local future_rows = intervals(future, final_cv.sigma, settings.interval, multipliers)
    local demands = map(future_rows, function(row)
        return row.forecast
    end)
    data.training_count, data.models, data.cv, data.members, data.metrics, data.intervals, data.best = training_count, models, cvs, members, measures, holdout_rows, best
    data.final_fits, data.future_rows, data.policy, data.plan = final_fits, future_rows, policy, inventory_plan(final, demands, policy, settings)
    data.residual_diagnostics = {}
    for _, name in ipairs(methods) do
        data.residual_diagnostics[name] = diagnostics(models[name].residuals, settings.ljung_box)
    end
    local years = {}
    local function year_row(period)
        local year = period:sub(1, 4)
        if not years[year] then
            years[year] = {year = year, actual_months = 0, actual = 0.0, forecast_months = 0, forecast = 0.0}
        end
        return years[year]
    end
    for i, period in ipairs(data.periods) do
        local row = year_row(period)
        row.actual_months, row.actual = row.actual_months + 1, row.actual + data.values[i]
    end
    for i, period in ipairs(data.future) do
        local row = year_row(period)
        row.forecast_months, row.forecast = row.forecast_months + 1, row.forecast + demands[i]
    end
    local keys = {}
    for year in pairs(years) do
        keys[#keys + 1] = year
    end
    table.sort(keys)
    data.years = {}
    local previous
    for _, year in ipairs(keys) do
        local row = years[year]
        row.total = row.actual + row.forecast
        if row.actual_months + row.forecast_months == 12 and previous and previous.actual_months + previous.forecast_months == 12 then
            row.growth = 100.0 * (row.total - previous.total) / previous.total
        end
        data.years[#data.years + 1], previous = row, row
    end
    return data
end
local function model_lines(model)
    local name, errors = model.name, model.residuals
    local common = "rmse " .. real(rmse(errors)) .. " residuals " .. #errors
    if name == "naive" or name == "snaive" then
        return {name .. " " .. common}
    end
    if name == "drift" then
        return {"drift slope " .. real(model.slope) .. " " .. common}
    end
    if parameters_for[name] then
        local parameters = {}
        for _, key in ipairs(parameters_for[name]) do
            parameters[#parameters + 1] = key .. " " .. real(model.parameters[key])
        end
        local state = model.states[#model.states]
        local first = name .. " " .. table.concat(parameters, " ") .. " " .. common .. " level " .. real(state.level)
        if name ~= "ses" then
            first = first .. " slope " .. real(state.slope)
        end
        local lines = {first}
        if name == "hw_add" or name == "hw_mult" then
            local components = {}
            for i = 0, model.season - 1 do
                components[#components + 1] = state.components[(#model.series + i) % model.season + 1]
            end
            lines[#lines + 1] = name .. " seasonal " .. reals(components)
        end
        return lines
    end
    if name == "decomp_add" or name == "decomp_mult" then
        return {name .. " intercept " .. real(model.intercept) .. " slope " .. real(model.slope) .. " " .. common, name .. " seasonal " .. reals(model.seasonal)}
    end
    local variances = {}
    for i, kind in ipairs(ar.kinds) do
        variances[#variances + 1] = kind .. " " .. real(model.variances[i])
    end
    return {"ar variance " .. table.concat(variances, " "), "ar difference " .. model.kind .. " n " .. #model.differenced .. " mean " .. real(model.average) .. " order " .. model.order .. " sigma2 " .. real(model.sigma2) .. " " .. common, "ar aic " .. reals(model.aic), "ar coefficients " .. (#model.coefficients == 0 and "none" or reals(model.coefficients))}
end
local function correlation_bar(value, band)
    local width, threshold, cells = math.floor(math.abs(value) * 20.0 + 0.5), math.floor(band * 20.0 + 0.5), {}
    for i = 1, 41 do
        cells[i] = " "
    end
    cells[21 - threshold], cells[21 + threshold], cells[21] = ":", ":", "|"
    if value > 0.0 then
        for i = 22, 21 + width do
            cells[i] = "#"
        end
    elseif value < 0.0 then
        for i = 21 - width, 20 do
            cells[i] = "#"
        end
    end
    return table.concat(cells)
end
local function forecast_chart(row, low, high, actual)
    local function column(value)
        return math.floor((value - low) / (high - low) * 60.0 + 0.5) + 1
    end
    local cells = {}
    for i = 1, 61 do
        cells[i] = " "
    end
    for i = column(row.lo95), column(row.hi95) do
        cells[i] = "-"
    end
    for i = column(row.lo80), column(row.hi80) do
        cells[i] = "="
    end
    cells[column(row.forecast)] = "o"
    if actual ~= nil then
        cells[column(actual)] = "*"
    end
    return table.concat(cells)
end
local function seasonal_profile(value, peak)
    local width, cells = math.floor(math.abs(value - 1.0) / peak * 30.0 + 0.5), {}
    for i = 1, 61 do
        cells[i] = " "
    end
    cells[31] = "|"
    if value > 1.0 then
        for i = 32, 31 + width do
            cells[i] = "#"
        end
    elseif value < 1.0 then
        for i = 31 - width, 30 do
            cells[i] = "#"
        end
    end
    return table.concat(cells)
end
local series, events, policies, settings = series_io.read_inputs()
local analyses = {}
for _, record in ipairs(series) do
    analyses[#analyses + 1] = analyze(record, events[record.name], policies[record.name], settings)
end
local interval_fields = {"forecast", "lo80", "hi80", "lo95", "hi95"}
local accuracy_fields = {"me", "mae", "rmse", "mape", "smape", "mase", "fva", "cv_rmse", "cover80", "cover95", "winkler80", "winkler95", "rank"}
local decomposition_lines = {"series,period,value,cleaned,trend,seasonal_add,residual_add,seasonal_mult,residual_mult,flag"}
local fitted_lines, forecasts, accuracy_lines, cv_lines, correlogram, charts, plans = {}, {"series,stage,method,period,actual,forecast,lo80,hi80,lo95,hi95"}, {"series,method," .. table.concat(accuracy_fields, ",")}, {"series,method,step,origins,mae,rmse"}, {}, {}, {}
for _, data in ipairs(analyses) do
    local name, components = data.name, data.components
    for t, period in ipairs(data.periods) do
        local position = (t - 1) % settings.season + 1
        local flag = data.past[t] or data.missing[t] and "missing" or data.outliers[t] and "outlier" or "ok"
        local fields = {name, period, real(data.values[t]), real(data.corrected[t]), real(components.trend[t]), real(components.additive[position]), real(components.residual_add[t]), real(components.multiplicative[position]), real(components.residual_mult[t]), flag}
        decomposition_lines[#decomposition_lines + 1] = table.concat(fields, ",")
    end
    append(fitted_lines, {"series " .. name, string.format("data observations %d train %d holdout %d missing %d outliers %d events %d", #data.values, data.training_count, settings.holdout, count_keys(data.missing), count_keys(data.outliers), count_keys(data.past))})
    for _, kind in ipairs(data.kinds) do
        local lift = data.lifts[kind]
        fitted_lines[#fitted_lines + 1] = "event " .. kind .. " occurrences " .. lift.occurrences .. " lift " .. real(lift.lift)
    end
    for t = 1, #data.values do
        if data.outliers[t] then
            fitted_lines[#fitted_lines + 1] = "outlier " .. data.periods[t] .. " value " .. real(data.values[t]) .. " expected " .. real(data.corrected[t]) .. " score " .. real(data.outliers[t])
        end
    end
    fitted_lines[#fitted_lines + 1] = "strength trend " .. real(data.strength_trend) .. " seasonal " .. real(data.strength_seasonal)
    for _, method in ipairs(methods) do
        append(fitted_lines, model_lines(data.models[method]))
    end
    append(fitted_lines, {"combo members " .. table.concat(data.members, " "), "best " .. data.best .. " rmse " .. real(data.metrics[data.best].rmse)})
    for _, model in ipairs(data.final_fits) do
        for _, line in ipairs(model_lines(model)) do
            fitted_lines[#fitted_lines + 1] = "final " .. line
        end
    end
    for _, method in ipairs(models_order) do
        for i, row in ipairs(data.intervals[method]) do
            local fields = {name, "holdout", method, data.periods[data.training_count + i], tostring(data.raw[data.training_count + i])}
            for _, key in ipairs(interval_fields) do
                fields[#fields + 1] = real(row[key])
            end
            forecasts[#forecasts + 1] = table.concat(fields, ",")
        end
        local measures, fields = data.metrics[method], {name, method}
        for _, key in ipairs(accuracy_fields) do
            fields[#fields + 1] = (key == "cover80" or key == "cover95" or key == "rank") and tostring(measures[key]) or real(measures[key])
        end
        accuracy_lines[#accuracy_lines + 1] = table.concat(fields, ",")
        local cv = data.cv[method]
        for i, count in ipairs(cv.counts) do
            cv_lines[#cv_lines + 1] = table.concat({name, method, i, count, real(cv.mae[i]), real(cv.sigma[i])}, ",")
        end
    end
    for i, row in ipairs(data.future_rows) do
        local fields = {name, "future", data.best, data.future[i], "NA"}
        for _, key in ipairs(interval_fields) do
            fields[#fields + 1] = real(row[key])
        end
        forecasts[#forecasts + 1] = table.concat(fields, ",")
    end
    local model = data.models.ar
    local band = 2.0 / math.sqrt(#model.differenced)
    correlogram[#correlogram + 1] = "series " .. name .. " difference " .. model.kind .. " n " .. #model.differenced .. " band " .. real(band)
    for _, group in ipairs({{"acf", model.correlations}, {"pacf", model.partial}}) do
        for lag = 1, #group[2] - 1 do
            local value = group[2][lag + 1]
            correlogram[#correlogram + 1] = string.format("%s %2d %7s [%s]%s", group[1], lag, real(value), correlation_bar(value, band), math.abs(value) > band and " *" or "")
        end
    end
    for _, method in ipairs(methods) do
        local stats, test_parts = data.residual_diagnostics[method], {}
        correlogram[#correlogram + 1] = "residuals " .. method .. " n " .. stats.count .. " mean " .. real(stats.mean) .. " sd " .. real(stats.sd) .. " dw " .. real(stats.dw) .. " skewness " .. real(stats.skewness) .. " kurtosis " .. real(stats.kurtosis) .. " jb " .. real(stats.jb)
        for _, test in ipairs(stats.ljung_box) do
            test_parts[#test_parts + 1] = "lag " .. test.lag .. " q " .. real(test.q) .. " p " .. real(test.probability)
        end
        correlogram[#correlogram + 1] = "ljung_box " .. method .. " " .. table.concat(test_parts, " ")
    end
    local chart_rows = {}
    for i, row in ipairs(data.intervals[data.best]) do
        chart_rows[#chart_rows + 1] = {period = data.periods[data.training_count + i], actual = data.values[data.training_count + i], interval = row}
    end
    for i, row in ipairs(data.future_rows) do
        chart_rows[#chart_rows + 1] = {period = data.future[i], interval = row}
    end
    local low, high = chart_rows[1].interval.lo95, chart_rows[1].interval.hi95
    for _, row in ipairs(chart_rows) do
        low, high = math.min(low, row.interval.lo95), math.max(high, row.interval.hi95)
        if row.actual then
            low, high = math.min(low, row.actual), math.max(high, row.actual)
        end
    end
    append(charts, {"chart " .. name .. " method " .. data.best, "scale low " .. real(low) .. " high " .. real(high)})
    for _, row in ipairs(chart_rows) do
        charts[#charts + 1] = row.period .. " |" .. forecast_chart(row.interval, low, high, row.actual) .. "|"
    end
    local peak = 0.0
    for _, value in ipairs(components.multiplicative) do
        peak = math.max(peak, math.abs(value - 1.0))
    end
    charts[#charts + 1] = "profile peak " .. real(peak)
    for i, value in ipairs(components.multiplicative) do
        charts[#charts + 1] = string.format("season %2d %s [%s]", i, real(value), seasonal_profile(value, peak))
    end
    local policy, plan = data.policy, data.plan
    append(plans, {"series " .. name .. " method " .. data.best, string.format("policy on_hand %d lead_time %d review %d service %s safety_stock %s", policy.on_hand, policy.lead_time, policy.review, real(policy.service), real(plan.safety))})
    for _, row in ipairs(plan.rows) do
        local period = data.future[row.step]
        if row.review then
            plans[#plans + 1] = "review " .. period .. " position " .. real(row.review.position) .. " target " .. real(row.review.target) .. " order " .. row.review.order
        end
        plans[#plans + 1] = "period " .. period .. " demand " .. real(row.demand) .. " receipt " .. row.receipt .. " on_hand " .. real(row.on_hand) .. " status " .. row.status
    end
    plans[#plans + 1] = string.format("summary orders %d ordered %d short_periods %d lowest %s average %s", plan.orders, plan.ordered, plan.short_periods, real(plan.lowest), real(plan.average))
    for _, year in ipairs(data.years) do
        plans[#plans + 1] = string.format("year %s actual_months %d actual %s forecast_months %d forecast %s total %s growth %s", year.year, year.actual_months, real(year.actual), year.forecast_months, real(year.forecast), real(year.total), real(year.growth))
    end
end
os.execute("mkdir -p output")
series_io.write_lines("decomposition.csv", decomposition_lines)
series_io.write_lines("models.txt", fitted_lines)
series_io.write_lines("forecasts.csv", forecasts)
series_io.write_lines("accuracy.csv", accuracy_lines)
series_io.write_lines("cv.csv", cv_lines)
series_io.write_lines("correlogram.txt", correlogram)
series_io.write_lines("chart.txt", charts)
series_io.write_lines("plan.txt", plans)
