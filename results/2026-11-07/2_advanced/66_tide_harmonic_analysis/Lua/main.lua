package.path = 'Lua/?.lua;' .. package.path
local records = require('records')
local cleaning = require('cleaning')
local harmonic = require('harmonic_fit')
local predict = require('predict')
local report = require('report')
local function average(a)
    local sum = 0.0
    for _, value in ipairs(a) do sum = sum + value end
    return sum / #a
end
local function select_constituents(cs, length, rayleigh)
    local selected, status = {}, {}
    for _, c in ipairs(cs) do
        local reason = c.speed * length < 360 * rayleigh and 'short' or 'fitted'
        if reason == 'fitted' then
            for _, other in ipairs(selected) do
                if math.abs(c.speed - other.speed) * length < 360 * rayleigh then reason = 'conflict:' .. other.name; break end
            end
        end
        status[c.name] = reason
        if reason == 'fitted' then selected[#selected + 1] = c end
    end
    return selected, status
end
local function residual_statistics(c, model)
    local r, ss, sum = {}, 0.0, 0.0
    local maximum = 0.0
    for _, t in ipairs(c.usable) do
        local v = c.values[t] - predict.height(model, t)
        r[t] = v; ss = ss + v * v; sum = sum + c.values[t]
        maximum = math.max(maximum, math.abs(v))
    end
    local mean = sum / #c.usable
    local tv, num, den = 0.0, 0.0, 0.0
    for _, t in ipairs(c.usable) do
        tv = tv + (c.values[t] - mean) ^ 2
        if r[t + 1] then num = num + r[t] * r[t + 1]; den = den + r[t] ^ 2 end
    end
    local dof = #c.usable - model.unknowns
    return {values = r, squared = ss, variance = ss / dof, dof = dof, rms = math.sqrt(ss / #c.usable),
        max_abs = maximum, explained_percent = 100 * (1 - ss / tv), lag1 = num / den}
end
local function errors(model, variance, minimum)
    local out, inv = {}, model.inverse
    for _, row in ipairs(model.selected) do
        local c = model.constants[row.name]
        local a, b, amp = c.a, c.b, c.amplitude
        local va, vb, cab = variance * inv[c.ia][c.ia], variance * inv[c.ib][c.ib], variance * inv[c.ia][c.ib]
        local ae = math.sqrt(a * a * va + b * b * vb + 2 * a * b * cab) / amp
        local pe = math.sqrt(b * b * va + a * a * vb - 2 * a * b * cab) / (amp * amp) * 180 / harmonic.PI
        local snr = (amp / ae) ^ 2
        out[row.name] = {amplitude_error = ae, phase_error = pe, snr = snr, significant = snr >= minimum and 'yes' or 'no'}
    end
    return out
end
local function validate(c, constituents, s, residuals)
    local mid = c.first + c.length // 2
    local train, test = {}, {}
    for _, t in ipairs(c.usable) do
        local target = t <= mid and train or test
        target[#target + 1] = t
    end
    local selected = select_constituents(constituents, train[#train] - train[1], s.rayleigh)
    local model = harmonic.fit(c.values, train, selected)
    local squared, insample, sum = 0.0, 0.0, 0.0
    for _, t in ipairs(test) do
        squared = squared + (c.values[t] - predict.height(model, t)) ^ 2
        insample = insample + residuals[t] ^ 2
        sum = sum + c.values[t]
    end
    local mean, tv = sum / #test, 0.0
    for _, t in ipairs(test) do tv = tv + (c.values[t] - mean) ^ 2 end
    return {midpoint = mid, training_count = #train, testing_count = #test, constituents = #selected,
        rms = math.sqrt(squared / #test), in_sample_rms = math.sqrt(insample / #test), skill = 1 - squared / tv}
end
local function events(c, residuals, s)
    local out, current, sign = {}, {}, nil
    local function flush()
        if #current < s.surge_hours then return end
        local peak = current[1]
        for _, t in ipairs(current) do
            if (sign == 'positive' and residuals[t] > residuals[peak]) or (sign == 'negative' and residuals[t] < residuals[peak]) then peak = t end
        end
        out[#out + 1] = {kind = sign, start = current[1], finish = current[#current], peak = peak, value = residuals[peak]}
    end
    for _, t in ipairs(c.usable) do
        local v = residuals[t]
        local next_sign = v > s.surge_threshold and 'positive' or (v < -s.surge_threshold and 'negative' or nil)
        if next_sign and next_sign == sign and #current > 0 and t == current[#current] + 1 then current[#current + 1] = t else
            flush(); current = next_sign and {t} or {}; sign = next_sign
        end
    end
    flush()
    return out
end
local weights = {[0] = 0, 2, 1, 1, 2, 0, 1, 1, 0, 2, 0, 1, 1, 0, 1, 0, 0, 1, 0, 1}
local function daily_means(c, model, s)
    local usable = {}
    for _, t in ipairs(c.usable) do usable[t] = true end
    local rows, levels = {}, {}
    for day = records.day(s, c.first), records.day(s, c.last) do
        local noon = (day * 1440 - s.epoch) // 60 + 12
        if noon - 19 >= c.first and noon + 19 <= c.last then
            local weighted, filled = 0.0, 0
            for j = -19, 19 do
                local t = noon + j
                local v
                if usable[t] then v = c.values[t] else v = predict.height(model, t); filled = filled + 1 end
                weighted = weighted + weights[math.abs(j)] * v
            end
            rows[#rows + 1] = {day = day, level = weighted / 30, filled = filled}
            levels[#levels + 1] = weighted / 30
        end
    end
    local mean, md = average(levels), (#rows - 1) / 2
    local num, den = 0.0, 0.0
    local highest, lowest = rows[1], rows[1]
    for i, row in ipairs(rows) do
        num = num + (i - 1 - md) * (row.level - mean)
        den = den + (i - 1 - md) ^ 2
        if row.level > highest.level then highest = row end
        if row.level < lowest.level then lowest = row end
    end
    return {rows = rows, days = #rows, average = mean, slope = 1000 * num / den, highest = highest, lowest = lowest}
end
local function finalize_extrema(out, s)
    local raw = #out
    while #out >= 2 do
        local best, smallest = 1, math.abs(out[1].height - out[2].height)
        for i = 2, #out - 1 do
            local gap = math.abs(out[i].height - out[i + 1].height)
            if gap < smallest then best, smallest = i, gap end
        end
        if smallest >= s.min_range then break end
        table.remove(out, best); table.remove(out, best)
    end
    for _, item in ipairs(out) do item.rounded = math.floor(item.minute + 0.5) end
    local groups = {}
    for _, item in ipairs(out) do
        item.day = (s.epoch + item.rounded) // 1440
        local key = item.day .. ':' .. item.kind
        local best = groups[key]
        if not best or (item.kind == 'high' and item.height > best.height) or (item.kind == 'low' and item.height < best.height) then groups[key] = item end
    end
    for _, item in ipairs(out) do
        local best = groups[item.day .. ':' .. item.kind] == item
        item.label = item.kind == 'high' and (best and 'HHW' or 'LHW') or (best and 'LLW' or 'HLW')
    end
    return out, raw
end
local function daily_extrema(extrema, s)
    local out = {}
    local start = records.day(s, s.prediction_start)
    for day = start, start + s.prediction_hours // 24 - 1 do
        local row = {day = day, high_waters = 0, low_waters = 0}
        for _, e in ipairs(extrema) do
            if e.day == day then
                if e.kind == 'high' then
                    row.high_waters = row.high_waters + 1
                    if row.hhw == nil or e.height > row.hhw then row.hhw = e.height end
                else
                    row.low_waters = row.low_waters + 1
                    if row.llw == nil or e.height < row.llw then row.llw = e.height end
                end
            end
        end
        if row.hhw ~= nil and row.llw ~= nil then row.range = row.hhw - row.llw end
        out[#out + 1] = row
    end
    return out
end
local function characteristics(model, extrema, daily, hourly, s)
    local k = model.constants
    local highs, lows, hv, lv, hhw, llw = {}, {}, {}, {}, {}, {}
    for _, e in ipairs(extrema) do
        local list, values = highs, hv
        if e.kind == 'low' then list, values = lows, lv end
        list[#list + 1] = e; values[#values + 1] = e.height
    end
    local highest, lowest = highs[1], lows[1]
    for _, e in ipairs(highs) do if e.height > highest.height then highest = e end end
    for _, e in ipairs(lows) do if e.height < lowest.height then lowest = e end end
    local widest, narrowest
    for _, d in ipairs(daily) do
        if d.hhw ~= nil then hhw[#hhw + 1] = d.hhw end
        if d.llw ~= nil then llw[#llw + 1] = d.llw end
        if d.range ~= nil then
            if not widest or d.range > widest.range then widest = d end
            if not narrowest or d.range < narrowest.range then narrowest = d end
        end
    end
    local mhhw, mllw, mhw, mlw = average(hhw), average(llw), average(hv), average(lv)
    local rises, falls = {}, {}
    for i = 2, #extrema do
        local prev, cur = extrema[i - 1], extrema[i]
        if prev.kind == 'low' and cur.kind == 'high' then rises[#rises + 1] = cur.rounded - prev.rounded end
        if prev.kind == 'high' and cur.kind == 'low' then falls[#falls + 1] = cur.rounded - prev.rounded end
    end
    local phase = (2 * k.M2.phase - k.M4.phase) % 360
    local form = (k.K1.amplitude + k.O1.amplitude) / (k.M2.amplitude + k.S2.amplitude)
    local kind = form < 0.25 and 'semidiurnal' or (form < 1.5 and 'mixed_semidiurnal' or (form < 3 and 'mixed_diurnal' or 'diurnal'))
    local amp_sum, above, below = 0.0, 0, 0
    for _, c in ipairs(model.selected) do amp_sum = amp_sum + k[c.name].amplitude end
    for _, h in ipairs(hourly) do if h > mhhw then above = above + 1 end; if h < mllw then below = below + 1 end end
    local dw, dg = k.S2.speed - k.M2.speed, k.S2.phase - k.M2.phase
    local q1 = (dw * s.prediction_start - dg) / 180
    local q2 = (dw * (s.prediction_start + s.prediction_hours) - dg) / 180
    local spring_neap = {}
    for q = math.ceil(math.min(q1, q2)), math.floor(math.max(q1, q2)) do
        local t = (dg + 180 * q) / dw
        if t >= s.prediction_start and t <= s.prediction_start + s.prediction_hours then
            spring_neap[#spring_neap + 1] = {kind = q % 2 == 0 and 'spring' or 'neap', minute = math.floor(t * 60 + 0.5)}
        end
    end
    return {mhhw = mhhw, mllw = mllw, mhw = mhw, mlw = mlw, mtl = (mhw + mlw) / 2,
        dtl = (mhhw + mllw) / 2, mn = mhw - mlw, gt = mhhw - mllw, highs = highs, lows = lows,
        rise_minutes = average(rises), fall_minutes = average(falls), m4_m2_ratio = k.M4.amplitude / k.M2.amplitude,
        relative_phase = phase, dominance = phase < 180 and 'flood' or 'ebb', form_number = form, type = kind,
        spring = 2 * (k.M2.amplitude + k.S2.amplitude), neap = 2 * (k.M2.amplitude - k.S2.amplitude),
        hat = model.mean_level + amp_sum, lat = model.mean_level - amp_sum, highest = highest, lowest = lowest,
        widest = widest, narrowest = narrowest, above_mhhw = 100 * above / #hourly, below_mllw = 100 * below / #hourly,
        spring_neap = spring_neap}
end
local function inspect(station, observations, constituents, s)
    local c = cleaning.prepare(observations, s.flat_run)
    local selected, status = select_constituents(constituents, c.length, s.rayleigh)
    local prelim = harmonic.fit(c.values, c.candidates, selected)
    local pr, ss = {}, 0.0
    for _, t in ipairs(c.candidates) do pr[t] = c.values[t] - predict.height(prelim, t); ss = ss + pr[t] * pr[t] end
    c.prefit_rms = math.sqrt(ss / #c.candidates)
    cleaning.spikes(c, pr, s)
    local model = harmonic.fit(c.values, c.usable, selected)
    local residual = residual_statistics(c, model)
    local hourly = predict.hours(model, s.prediction_start, s.prediction_hours)
    local extrema, raw = finalize_extrema(predict.extrema(model, s), s)
    local daily = daily_extrema(extrema, s)
    return {code = station.code, name = station.name, cleaning = c, status = status, model = model, residual = residual,
        errors = errors(model, residual.variance, s.snr_min), validation = validate(c, constituents, s, residual.values),
        surges = events(c, residual.values, s), daily_means = daily_means(c, model, s), hourly = hourly,
        extrema = extrema, raw_extrema = raw, daily = daily, characteristics = characteristics(model, extrema, daily, hourly, s)}
end
local function lag(own, reference)
    local offsets = {}
    for _, e in ipairs(own) do
        local best = reference[1]
        for _, r in ipairs(reference) do
            if math.abs(r.rounded - e.rounded) < math.abs(best.rounded - e.rounded) then best = r end
        end
        offsets[#offsets + 1] = e.rounded - best.rounded
    end
    return average(offsets)
end
local function compare(stations, s)
    local ref = stations[s.reference]
    local out = {}
    for _, entry in ipairs(s.stations) do
        if entry.code ~= s.reference then
            local station = stations[entry.code]
            local own, rc = station.characteristics, ref.characteristics
            local row = {code = entry.code, hw_lag_min = lag(own.highs, rc.highs), lw_lag_min = lag(own.lows, rc.lows),
                range_ratio = own.gt / rc.gt, mtl_diff = own.mtl - rc.mtl, constituents = {}}
            for _, name in ipairs({'M2', 'S2', 'K1', 'O1'}) do
                local a, b = station.model.constants[name], ref.model.constants[name]
                local phase = a.phase - b.phase
                if phase > 180 then phase = phase - 360 end
                if phase <= -180 then phase = phase + 360 end
                row.constituents[#row.constituents + 1] = {name = name, amplitude_ratio = a.amplitude / b.amplitude,
                    phase_diff = phase, time_lag_min = phase / a.speed * 60}
            end
            out[#out + 1] = row
        end
    end
    return out
end
local function correlate(a, b, lag_value)
    local xs, ys = {}, {}
    for _, t in ipairs(a.cleaning.usable) do
        if b.residual.values[t + lag_value] ~= nil then
            xs[#xs + 1] = a.residual.values[t]; ys[#ys + 1] = b.residual.values[t + lag_value]
        end
    end
    local mx, my = average(xs), average(ys)
    local cov, vx, vy = 0.0, 0.0, 0.0
    for i, x in ipairs(xs) do
        cov = cov + (x - mx) * (ys[i] - my); vx = vx + (x - mx) ^ 2; vy = vy + (ys[i] - my) ^ 2
    end
    return cov / math.sqrt(vx * vy), #xs
end
local function correlations(stations, s)
    local out = {}
    for i = 1, #s.stations do
        for j = i + 1, #s.stations do
            local ac, bc = s.stations[i].code, s.stations[j].code
            local row = {first = ac, second = bc}
            for l = -s.correlation_lag, s.correlation_lag do
                local rho, count = correlate(stations[ac], stations[bc], l)
                if l == 0 then row.lag_zero = rho end
                if row.best == nil or rho > row.best or (rho == row.best and (math.abs(l) < math.abs(row.lag) or (math.abs(l) == math.abs(row.lag) and l < row.lag))) then
                    row.best, row.lag, row.pairs = rho, l, count
                end
            end
            out[#out + 1] = row
        end
    end
    return out
end
local decimal = report.decimal
local function optional(value, places) return value == nil and 'none' or decimal(value, places) end
local function add(lines, prefix, ...)
    local values, parts = {...}, {}
    if prefix ~= '' then parts[1] = prefix end
    for i = 1, #values, 2 do parts[#parts + 1] = values[i] .. '=' .. tostring(values[i + 1]) end
    lines[#lines + 1] = table.concat(parts, ' ')
end
local function plot(lines, station, s)
    add(lines, '[plot]', 'station', s.plot_code, 'start', records.hour(s, s.prediction_start), 'hours', s.plot_hours, 'step_cm', s.plot_step)
    local rows = (s.plot_top - s.plot_bottom) // s.plot_step + 1
    local grid, labels, marks = {}, {}, {}
    local label_width = 0
    for r = 0, rows - 1 do
        grid[r] = {}; for col = 0, s.plot_hours - 1 do grid[r][col] = ' ' end
        labels[r] = decimal((s.plot_top - r * s.plot_step) / 100, 2)
        label_width = math.max(label_width, #labels[r])
    end
    local zero = math.floor((s.plot_top - 100 * station.model.mean_level) / s.plot_step + 0.5)
    if zero >= 0 and zero < rows then for col = 0, s.plot_hours - 1 do grid[zero][col] = '-' end end
    for _, e in ipairs(station.extrema) do
        local col = (e.rounded - 60 * s.prediction_start + 30) // 60
        if col >= 0 and col < s.plot_hours then marks[col] = e.kind == 'high' and 'H' or 'L' end
    end
    for col = 0, s.plot_hours - 1 do
        local h = predict.height(station.model, s.prediction_start + col)
        local row = math.floor((s.plot_top - 100 * h) / s.plot_step + 0.5)
        if row < 0 then grid[0][col] = '^' elseif row >= rows then grid[rows - 1][col] = 'v' else grid[row][col] = marks[col] or '*' end
    end
    for _, line in ipairs(report.plot_lines(grid, labels, label_width, s)) do lines[#lines + 1] = line end
end
local function write_outputs(stations, constituents, s, comparisons, correlations)
    local clean, cs, predictions, extremes, summary = {}, {}, {}, {}, {}
    cs[1] = 'station,constituent,speed,status,amplitude,phase,amplitude_error,phase_error,snr,significant'
    local order = {}
    for _, entry in ipairs(s.stations) do order[#order + 1] = entry.code end
    predictions[1] = 'time,' .. table.concat(order, ',')
    for _, entry in ipairs(s.stations) do
        local code, station = entry.code, stations[entry.code]
        local c, model, residual = station.cleaning, station.model, station.residual
        add(clean, '', 'station', code, 'name', station.name)
        add(clean, 'span', 'start', records.hour(s, c.first), 'end', records.hour(s, c.last), 'hours', c.last - c.first + 1, 'record_length', c.length)
        local counts = {na = 0, absent = 0, flat = 0}
        for _, reason in pairs(c.reasons) do if counts[reason] then counts[reason] = counts[reason] + 1 end end
        add(clean, 'counts', 'rows', c.rows, 'numeric', #c.numeric_times, 'na', counts.na, 'absent', counts.absent,
            'flat', counts.flat, 'spikes', #c.spikes, 'usable', #c.usable)
        for _, f in ipairs(c.flat_runs) do
            add(clean, 'flat', 'start', records.hour(s, f.start), 'end', records.hour(s, f.finish), 'value', decimal(f.value, 3), 'removed', f.finish - f.start)
        end
        add(clean, 'spike_test', 'window', s.spike_window, 'candidates', #c.candidates, 'tested', c.tested, 'prefit_rms', decimal(c.prefit_rms, 4))
        for _, spike in ipairs(c.spikes) do
            add(clean, 'spike', 'time', records.hour(s, spike.time), 'value', decimal(spike.value, 3), 'residual', decimal(spike.residual, 4),
                'median', decimal(spike.median, 4), 'mad', decimal(spike.mad, 4), 'limit', decimal(spike.limit, 4))
        end
        for _, gap in ipairs(c.gaps) do
            add(clean, 'gap', 'start', records.hour(s, gap.start), 'end', records.hour(s, gap.finish), 'hours', gap.finish - gap.start + 1, 'cause', gap.cause)
        end
        for _, row in ipairs(constituents) do
            local status = station.status[row.name]
            local prefix = code .. ',' .. row.name .. ',' .. decimal(row.speed, 7) .. ',' .. status
            if status ~= 'fitted' then cs[#cs + 1] = prefix .. ',,,,,,' else
                local k, e = model.constants[row.name], station.errors[row.name]
                cs[#cs + 1] = table.concat({prefix, decimal(k.amplitude, 4), decimal(k.phase, 2), decimal(e.amplitude_error, 4),
                    decimal(e.phase_error, 2), decimal(e.snr, 1), e.significant}, ',')
            end
        end
        add(extremes, '', 'station', code, 'extremes', #station.extrema, 'raw', station.raw_extrema, 'removed', station.raw_extrema - #station.extrema)
        for i, e in ipairs(station.extrema) do
            local change = i == 1 and 'none' or decimal(e.height - station.extrema[i - 1].height, 3)
            add(extremes, records.minute(s, e.rounded) .. ' ' .. e.label .. ' ' .. decimal(e.height, 3), 'change', change)
        end
        for _, day in ipairs(station.daily) do
            add(extremes, 'day', 'date', records.date(day.day), 'high_waters', day.high_waters, 'low_waters', day.low_waters,
                'hhw', optional(day.hhw, 3), 'llw', optional(day.llw, 3), 'range', optional(day.range, 3))
        end
        summary[#summary + 1] = '[station ' .. code .. '] ' .. station.name
        add(summary, 'record', 'first', records.hour(s, c.first), 'last', records.hour(s, c.last), 'length', c.length, 'usable', #c.usable)
        add(summary, 'fit', 'constituents', #model.selected, 'unknowns', model.unknowns, 'dof', residual.dof, 'mean_level', decimal(model.mean_level, 4))
        add(summary, 'residual', 'rms', decimal(residual.rms, 4), 'max_abs', decimal(residual.max_abs, 4),
            'explained_percent', decimal(residual.explained_percent, 4), 'lag1_autocorrelation', decimal(residual.lag1, 4))
        local ordered = {}
        for _, t in ipairs(c.usable) do ordered[#ordered + 1] = t end
        table.sort(ordered, function(a, b)
            local aa, bb = math.abs(residual.values[a]), math.abs(residual.values[b])
            return aa > bb or (aa == bb and a < b)
        end)
        for rank = 1, math.min(s.top_residuals, #ordered) do
            local t = ordered[rank]
            add(summary, 'top_residual', 'rank', rank, 'time', records.hour(s, t), 'observed', decimal(c.values[t], 3),
                'fitted', decimal(predict.height(model, t), 4), 'residual', decimal(residual.values[t], 4))
        end
        local v = station.validation
        add(summary, 'validation', 'split', records.hour(s, v.midpoint), 'train', v.training_count, 'test', v.testing_count, 'constituents', v.constituents,
            'rms', decimal(v.rms, 4), 'in_sample_rms', decimal(v.in_sample_rms, 4), 'skill', decimal(v.skill, 4))
        local h = station.characteristics
        add(summary, '', 'form_number', decimal(h.form_number, 4), 'type', h.type)
        add(summary, 'ranges', 'spring', decimal(h.spring, 3), 'neap', decimal(h.neap, 3), 'mn', decimal(h.mn, 3), 'gt', decimal(h.gt, 3))
        add(summary, 'asymmetry', 'rise_minutes', decimal(h.rise_minutes, 1), 'fall_minutes', decimal(h.fall_minutes, 1), 'm4_m2_ratio', decimal(h.m4_m2_ratio, 4),
            'relative_phase', decimal(h.relative_phase, 2), 'dominance', h.dominance)
        add(summary, 'datums', 'mhhw', decimal(h.mhhw, 3), 'mhw', decimal(h.mhw, 3), 'mtl', decimal(h.mtl, 3), 'dtl', decimal(h.dtl, 3),
            'mlw', decimal(h.mlw, 3), 'mllw', decimal(h.mllw, 3))
        add(summary, 'bounds', 'hat', decimal(h.hat, 3), 'lat', decimal(h.lat, 3))
        add(summary, 'window', 'high_waters', #h.highs, 'low_waters', #h.lows, 'highest', decimal(h.highest.height, 3),
            'highest_time', records.minute(s, h.highest.rounded), 'lowest', decimal(h.lowest.height, 3), 'lowest_time', records.minute(s, h.lowest.rounded))
        add(summary, 'daily_range', 'widest', decimal(h.widest.range, 3), 'widest_date', records.date(h.widest.day),
            'narrowest', decimal(h.narrowest.range, 3), 'narrowest_date', records.date(h.narrowest.day))
        add(summary, 'exceedance', 'above_mhhw', decimal(h.above_mhhw, 2), 'below_mllw', decimal(h.below_mllw, 2))
        for _, event in ipairs(h.spring_neap) do add(summary, event.kind, 'time', records.minute(s, event.minute)) end
        add(summary, 'surges', 'count', #station.surges, 'threshold', decimal(s.surge_threshold, 3), 'min_hours', s.surge_hours)
        for _, surge in ipairs(station.surges) do
            add(summary, 'surge', 'type', surge.kind, 'start', records.hour(s, surge.start), 'end', records.hour(s, surge.finish),
                'hours', surge.finish - surge.start + 1, 'peak', decimal(surge.value, 4), 'peak_time', records.hour(s, surge.peak))
        end
        local means = station.daily_means
        add(summary, 'daily_mean', 'days', means.days, 'average', decimal(means.average, 4), 'slope_mm_per_day', decimal(means.slope, 3),
            'max', decimal(means.highest.level, 4), 'max_date', records.date(means.highest.day),
            'min', decimal(means.lowest.level, 4), 'min_date', records.date(means.lowest.day))
        for _, row in ipairs(means.rows) do add(summary, 'daily_mean', 'date', records.date(row.day), 'level', decimal(row.level, 4), 'filled', row.filled) end
    end
    for i = 0, s.prediction_hours do
        local fields = {records.hour(s, s.prediction_start + i)}
        for _, code in ipairs(order) do fields[#fields + 1] = decimal(stations[code].hourly[i + 1], 3) end
        predictions[#predictions + 1] = table.concat(fields, ',')
    end
    add(summary, '[comparison]', 'reference', s.reference)
    for _, item in ipairs(comparisons) do
        add(summary, item.code .. ' tide', 'hw_lag_min', decimal(item.hw_lag_min, 1), 'lw_lag_min', decimal(item.lw_lag_min, 1),
            'range_ratio', decimal(item.range_ratio, 4), 'mtl_diff', decimal(item.mtl_diff, 3))
        for _, k in ipairs(item.constituents) do
            add(summary, item.code .. ' ' .. k.name, 'amplitude_ratio', decimal(k.amplitude_ratio, 4), 'phase_diff', decimal(k.phase_diff, 2), 'time_lag_min', decimal(k.time_lag_min, 1))
        end
    end
    add(summary, '[correlation]', 'max_lag', s.correlation_lag)
    for _, c in ipairs(correlations) do
        add(summary, c.first .. '-' .. c.second, 'lag0', decimal(c.lag_zero, 4), 'best_lag', c.lag, 'best', decimal(c.best, 4), 'pairs', c.pairs)
    end
    plot(summary, stations[s.plot_code], s)
    report.write_lines('cleaning.txt', clean); report.write_lines('constituents.csv', cs); report.write_lines('predictions.csv', predictions)
    report.write_lines('extremes.txt', extremes); report.write_lines('summary.txt', summary)
end
local settings, constituents, observations = records.read()
local stations = {}
for _, entry in ipairs(settings.stations) do stations[entry.code] = inspect(entry, observations[entry.code], constituents, settings) end
write_outputs(stations, constituents, settings, compare(stations, settings), correlations(stations, settings))
