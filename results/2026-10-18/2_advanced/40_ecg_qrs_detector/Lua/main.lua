local signal_io = require("signal_io")
local filters = require("filters")
local detector = require("detector")
local hrv = require("hrv")
local report = require("report")
local labels = {"N", "V", "A"}
local peak_classes = {"qrs", "searchback", "twave", "refractory", "noise"}
local function append(target, values)
    for _, value in ipairs(values) do
        target[#target + 1] = value
    end
end
local function sum(values)
    local result = 0
    for _, value in ipairs(values) do
        result = result + value
    end
    return result
end
local function extrema(values)
    local low, high = values[1], values[1]
    for _, value in ipairs(values) do
        low, high = math.min(low, value), math.max(high, value)
    end
    return low, high
end
local function keys(values)
    local result = {}
    for key in pairs(values) do
        result[#result + 1] = key
    end
    table.sort(result)
    return result
end
local function pad(value, width)
    local text = tostring(value)
    return string.rep(" ", math.max(0, width - #text)) .. text
end
local function csv(fields)
    for index, value in ipairs(fields) do
        fields[index] = tostring(value)
    end
    return table.concat(fields, ",")
end
local function thresholds(levels)
    local thi = levels.npki + (levels.spki - levels.npki) // 4
    local thf = levels.npkf + (levels.spkf - levels.npkf) // 4
    return thi, thf, thi // 2, thf // 2
end
local function detect(peaks, signals, params)
    local initial = detector.initial_levels(signals)
    local levels = {spki = initial.spki, npki = initial.npki, spkf = initial.spkf, npkf = initial.npkf}
    local registered, intervals, ra1, ra2 = {}, {}, 200, 200
    local function register(peak)
        if #registered > 0 then
            local elapsed = peak.time - registered[#registered].time
            intervals[#intervals + 1] = elapsed
            if #intervals > 8 then
                table.remove(intervals, 1)
            end
            ra1 = sum(intervals) // #intervals
            if 92 * ra1 <= 100 * elapsed and 100 * elapsed <= 116 * ra1 then
                ra2 = ra1
            end
        end
        registered[#registered + 1] = peak
    end
    local function update(peak, kind)
        if kind == "noise" then
            levels.npki, levels.npkf = (peak.peak_i + 7 * levels.npki) // 8, (peak.peak_f + 7 * levels.npkf) // 8
        else
            local factor, divisor = kind == "signal" and 7 or 3, kind == "signal" and 8 or 4
            levels.spki, levels.spkf = (peak.peak_i + factor * levels.spki) // divisor, (peak.peak_f + factor * levels.spkf) // divisor
        end
    end
    local function searchback(moment)
        while true do
            local last = #registered > 0 and registered[#registered].time or 0
            if moment - last <= ra2 * params.searchback_percent // 100 then
                break
            end
            local _, _, thi, thf = thresholds(levels)
            local chosen
            for _, peak in ipairs(peaks) do
                if peak.class == "noise" and peak.time > last and peak.time < moment and peak.peak_i > thi and peak.peak_f > thf and (not chosen or peak.peak_i > chosen.peak_i) then
                    chosen = peak
                end
            end
            if not chosen then
                break
            end
            update(chosen, "searchback")
            chosen.class = "searchback"
            register(chosen)
        end
    end
    for _, peak in ipairs(peaks) do
        searchback(peak.time)
        peak.thr_i, peak.thr_f = thresholds(levels)
        local last = registered[#registered]
        if last and peak.time - last.time < params.refractory_ms // 5 then
            peak.class = "refractory"
        elseif peak.peak_i > peak.thr_i and peak.peak_f > peak.thr_f then
            if last and peak.time - last.time < params.twave_ms // 5 and 2 * peak.slope < last.slope then
                peak.class = "twave"
                update(peak, "noise")
            else
                peak.class = "qrs"
                update(peak, "signal")
                register(peak)
            end
        else
            peak.class = "noise"
            update(peak, "noise")
        end
    end
    searchback(#signals.integrated)
    return {registered = registered, initial = initial, final = levels, ra1 = ra1, ra2 = ra2}
end
local function beat_list(registered, band, params)
    local beats = {}
    for number, peak in ipairs(registered) do
        local sample = math.max(0, peak.r - 21)
        local rr = number > 1 and 5 * (sample - beats[number - 1].sample) or nil
        local width, label = detector.width(band, peak.r), "N"
        if number >= 10 then
            local preceding = 0
            for index = number - 8, number - 1 do
                preceding = preceding + beats[index].rr
            end
            if 800 * rr < params.premature_percent * preceding then
                label = width > params.qrs_width_ms and "V" or "A"
            end
        end
        beats[number] = {number = number, sample = sample, rr = rr, hr = rr and report.rdiv(6000000, rr), width = width, label = label,
            method = peak.class == "qrs" and "threshold" or "searchback"}
    end
    return beats
end
local function match(beats, refs, tolerance)
    for _, beat in ipairs(beats) do
        local chosen, distance
        for index, ref in ipairs(refs) do
            local delta = math.abs(ref.sample - beat.sample)
            if not ref.beat and delta <= tolerance and (not chosen or delta < distance) then
                chosen, distance = index, delta
            end
        end
        if chosen then
            beat.annotation, refs[chosen].beat = chosen, beat.number
            beat.offset = 5 * (beat.sample - refs[chosen].sample)
        end
    end
end
local function segments(beats, refs, peaks, count, params)
    local width, result = params.segment_ms // 5, {}
    for start = 0, count - 1, width do
        local stop = math.min(start + width, count)
        local segment = {start = 5 * start, stop = 5 * stop, refs = 0, tp = 0, fp = 0, fn = 0, noise = 0, beats = 0, rr = {}}
        for _, ref in ipairs(refs) do
            if ref.sample >= start and ref.sample < stop then
                segment.refs = segment.refs + 1
                if ref.beat then
                    segment.tp = segment.tp + 1
                else
                    segment.fn = segment.fn + 1
                end
            end
        end
        for _, beat in ipairs(beats) do
            if beat.sample >= start and beat.sample < stop then
                segment.beats = segment.beats + 1
                if not beat.annotation then
                    segment.fp = segment.fp + 1
                end
                if beat.rr then
                    segment.rr[#segment.rr + 1] = beat.rr
                end
            end
        end
        for _, peak in ipairs(peaks) do
            if peak.time >= start and peak.time < stop and peak.class == "noise" then
                segment.noise = segment.noise + 1
            end
        end
        result[#result + 1] = segment
    end
    return result
end
local function beat_csv(beats, refs)
    local lines = {"beat,sample,time_ms,rr_ms,hr_bpm,width_ms,label,method,ref_sample,ref_label"}
    for _, beat in ipairs(beats) do
        local ref = beat.annotation and refs[beat.annotation]
        lines[#lines + 1] = csv({beat.number, beat.sample, 5 * beat.sample, report.missing(beat.rr), beat.hr and report.two(beat.hr) or "-",
            beat.width, beat.label, beat.method, ref and ref.sample or "-", ref and ref.label or "-"})
    end
    return lines
end
local function peak_csv(peaks)
    local lines = {"peak,sample,r_sample,peak_i,peak_f,slope,thr_i,thr_f,class"}
    for index, peak in ipairs(peaks) do
        lines[#lines + 1] = csv({index, peak.time, peak.r, peak.peak_i, peak.peak_f, peak.slope, peak.thr_i, peak.thr_f, peak.class})
    end
    return lines
end
local function matching_csv(beats, refs)
    local records = {}
    for _, ref in ipairs(refs) do
        local beat = ref.beat and beats[ref.beat]
        local fields = beat and {ref.sample, ref.label, beat.number, beat.sample, beat.label, beat.offset, "TP", ref.label == beat.label and "yes" or "no"}
            or {ref.sample, ref.label, "-", "-", "-", "-", "FN", "-"}
        records[#records + 1] = {sample = ref.sample, priority = 0, line = csv(fields)}
    end
    for _, beat in ipairs(beats) do
        if not beat.annotation then
            records[#records + 1] = {sample = beat.sample, priority = 1, line = csv({"-", "-", beat.number, beat.sample, beat.label, "-", "FP", "-"})}
        end
    end
    table.sort(records, function(a, b) return a.sample < b.sample or (a.sample == b.sample and a.priority < b.priority) end)
    local lines = {"ref_sample,ref_label,beat,beat_sample,beat_label,offset_ms,status,agree"}
    for _, record in ipairs(records) do
        lines[#lines + 1] = record.line
    end
    return lines
end
local function excerpt(samples, signals, count)
    local lines = {"sample,ecg,lowpass,bandpass,derivative,squared,integrated"}
    for n = 0, count - 1 do
        lines[#lines + 1] = csv({n, samples[n + 1], signals.lowpass[n + 1], signals.bandpass[n + 1], signals.derivative[n + 1], signals.squared[n + 1], signals.integrated[n + 1]})
    end
    return lines
end
local function performance(beats, refs, peaks, detection, params, parts, count)
    local classes, types, detected = {}, {N = 0, V = 0, A = 0}, {N = 0, V = 0, A = 0}
    local tp, fp, offsets, confusion, misses, extras = 0, 0, {}, {}, {}, {}
    local method_total, method_tp, errors = {threshold = 0, searchback = 0}, {threshold = 0, searchback = 0}, {}
    for _, label in ipairs(labels) do
        confusion[label], misses[label], extras[label] = {N = 0, V = 0, A = 0}, 0, 0
    end
    for _, peak in ipairs(peaks) do
        classes[peak.class] = (classes[peak.class] or 0) + 1
    end
    for _, ref in ipairs(refs) do
        types[ref.label] = types[ref.label] + 1
        if ref.beat then
            local beat = beats[ref.beat]
            tp = tp + 1
            confusion[ref.label][beat.label] = confusion[ref.label][beat.label] + 1
        else
            misses[ref.label] = misses[ref.label] + 1
            errors[#errors + 1] = {sample = ref.sample, priority = 1, line = "false_negative sample=" .. ref.sample .. " time_ms=" .. 5 * ref.sample .. " label=" .. ref.label}
        end
    end
    for _, beat in ipairs(beats) do
        detected[beat.label] = detected[beat.label] + 1
        method_total[beat.method] = method_total[beat.method] + 1
        if beat.annotation then
            method_tp[beat.method] = method_tp[beat.method] + 1
            offsets[#offsets + 1] = beat.offset
        else
            fp = fp + 1
            extras[beat.label] = extras[beat.label] + 1
            errors[#errors + 1] = {sample = beat.sample, priority = 0, line = "false_positive beat=" .. beat.number .. " sample=" .. beat.sample .. " time_ms=" .. 5 * beat.sample .. " label=" .. beat.label}
        end
    end
    local fn = #refs - tp
    local class_items = {}
    for _, kind in ipairs(peak_classes) do
        class_items[#class_items + 1] = kind .. "=" .. (classes[kind] or 0)
    end
    local function level_line(prefix, levels)
        return prefix .. " spki=" .. levels.spki .. " npki=" .. levels.npki .. " spkf=" .. levels.spkf .. " npkf=" .. levels.npkf
    end
    local thi, thf = thresholds(detection.final)
    local lines = {"DETECTOR", "samples " .. count, "duration_ms " .. 5 * count, "peaks " .. #peaks .. " " .. table.concat(class_items, " "),
        level_line("initial_levels", detection.initial), level_line("final_levels", detection.final), "final_thresholds thr_i=" .. thi .. " thr_f=" .. thf,
        "final_rr_averages rravg1_ms=" .. 5 * detection.ra1 .. " rravg2_ms=" .. 5 * detection.ra2, "MATCHING", "tolerance_ms " .. params.match_ms,
        "references " .. #refs .. " N=" .. types.N .. " V=" .. types.V .. " A=" .. types.A, "detections " .. #beats .. " N=" .. detected.N .. " V=" .. detected.V .. " A=" .. detected.A,
        "true_positives " .. tp, "false_positives " .. fp, "false_negatives " .. fn,
        "sensitivity " .. report.ratio(tp, #refs), "positive_predictivity " .. report.ratio(tp, #beats), "detection_error_rate " .. report.ratio(fp + fn, #refs),
        "by_method threshold=" .. method_tp.threshold .. "/" .. method_total.threshold .. " searchback=" .. method_tp.searchback .. "/" .. method_total.searchback}
    if #offsets == 0 then
        lines[#lines + 1] = "offset_ms none"
    else
        local absolute_sum, absolute_max = 0, 0
        for _, offset in ipairs(offsets) do
            absolute_sum, absolute_max = absolute_sum + math.abs(offset), math.max(absolute_max, math.abs(offset))
        end
        lines[#lines + 1] = "offset_ms mean=" .. report.two(report.rdiv(100 * sum(offsets), #offsets)) .. " mean_abs=" .. report.two(report.rdiv(100 * absolute_sum, #offsets)) .. " max_abs=" .. absolute_max
    end
    append(lines, {"CONFUSION", "ref  " .. pad("N", 6) .. pad("V", 6) .. pad("A", 6) .. "  miss"})
    for _, label in ipairs(labels) do
        lines[#lines + 1] = label .. "    " .. pad(confusion[label].N, 6) .. pad(confusion[label].V, 6) .. pad(confusion[label].A, 6) .. pad(misses[label], 6)
    end
    lines[#lines + 1] = "extra" .. pad(extras.N, 6) .. pad(extras.V, 6) .. pad(extras.A, 6)
    for _, label in ipairs({"V", "A"}) do
        local prefix = label == "V" and "veb" or "sveb"
        lines[#lines + 1] = prefix .. "_sensitivity " .. report.ratio(confusion[label][label], types[label])
        lines[#lines + 1] = prefix .. "_positive_predictivity " .. report.ratio(confusion[label][label], detected[label])
    end
    lines[#lines + 1] = "SEGMENTS segment_ms=" .. params.segment_ms .. " segments=" .. #parts
    for _, part in ipairs(parts) do
        lines[#lines + 1] = pad(part.start, 6) .. "-" .. pad(part.stop, 6) .. " refs=" .. part.refs .. " tp=" .. part.tp .. " fp=" .. part.fp .. " fn=" .. part.fn .. " noise_peaks=" .. part.noise
    end
    lines[#lines + 1] = "ERRORS count=" .. #errors
    table.sort(errors, function(a, b) return a.sample < b.sample or (a.sample == b.sample and a.priority < b.priority) end)
    for _, item in ipairs(errors) do
        lines[#lines + 1] = item.line
    end
    return lines
end
local function variability_inputs(beats)
    local rr, nn, pairs, selected = {}, {}, {}, {}
    for index = 2, #beats do
        rr[#rr + 1] = beats[index].rr
        if index >= 3 and beats[index - 1].label == "N" and beats[index].label == "N" and 5 * math.abs(beats[index].rr - beats[index - 1].rr) <= beats[index - 1].rr then
            nn[#nn + 1] = beats[index].rr
            selected[index] = true
            if selected[index - 1] then
                pairs[#pairs + 1] = {beats[index - 1].rr, beats[index].rr}
            end
        end
    end
    return rr, nn, pairs
end
local function event_lines(beats, params)
    local lines = {}
    for number = 2, #beats do
        local beat = beats[number]
        if beat.rr > params.pause_ms then
            lines[#lines + 1] = "pause beats=" .. (number - 1) .. "-" .. number .. " rr_ms=" .. beat.rr .. " start_ms=" .. 5 * beats[number - 1].sample
        end
    end
    for _, kind in ipairs({"bradycardia", "tachycardia"}) do
        local indices = {}
        for number = 2, #beats do
            if (kind == "bradycardia" and beats[number].rr > params.brady_ms) or (kind == "tachycardia" and beats[number].rr < params.tachy_ms) then
                indices[#indices + 1] = number
            end
        end
        for _, range in ipairs(hrv.ranges(indices)) do
            local first, last = range[1], range[2]
            local count, total = last - first + 1, 0
            if count >= 3 then
                for number = first, last do
                    total = total + beats[number].rr
                end
                lines[#lines + 1] = kind .. " beats=" .. (first - 1) .. "-" .. last .. " intervals=" .. count .. " mean_hr=" .. report.two(report.rdiv(6000000 * count, total)) .. " start_ms=" .. 5 * beats[first - 1].sample
            end
        end
    end
    local ventricular = {}
    for _, beat in ipairs(beats) do
        if beat.label == "V" then
            ventricular[#ventricular + 1] = beat.number
        end
    end
    for span = 2, 3 do
        local chains = {}
        for _, number in ipairs(ventricular) do
            local chain = chains[#chains]
            local linked = chain and number == chain[#chain] + span
            if linked then
                for between = chain[#chain] + 1, number - 1 do
                    linked = linked and beats[between].label == "N"
                end
            end
            if linked then
                chain[#chain + 1] = number
            else
                chains[#chains + 1] = {number}
            end
        end
        for _, chain in ipairs(chains) do
            if #chain >= 3 then
                lines[#lines + 1] = (span == 2 and "bigeminy" or "trigeminy") .. " beats=" .. chain[1] .. "-" .. chain[#chain] .. " cycles=" .. #chain .. " start_ms=" .. 5 * beats[chain[1]].sample
            end
        end
    end
    return lines
end
local function variability(beats, refs, parts, params)
    local rr, nn, pairs = variability_inputs(beats)
    local stats = hrv.statistics(rr, nn, pairs)
    local lines = {"RR", "beats " .. #beats, "intervals " .. #rr, "mean_rr_ms " .. report.maybe_two(stats.mean_rr)}
    if #rr == 0 then
        append(lines, {"min_rr_ms none", "max_rr_ms none", "mean_hr_bpm none"})
    else
        append(lines, {"min_rr_ms " .. rr[stats.shortest] .. " beat=" .. (stats.shortest + 1), "max_rr_ms " .. rr[stats.longest] .. " beat=" .. (stats.longest + 1), "mean_hr_bpm " .. report.two(stats.mean_hr)})
    end
    append(lines, {"NN", "intervals " .. stats.e, "mean_nn_ms " .. report.maybe_two(stats.mean_nn), "sdnn_ms " .. report.maybe_two(stats.sdnn),
        "differences " .. stats.k, "rmssd_ms " .. report.maybe_two(stats.rmssd), "sdsd_ms " .. report.maybe_two(stats.sdsd), "nn50 " .. stats.nn50,
        stats.pnn50 and "pnn50 " .. report.two(stats.pnn50) .. "%" or "pnn50 none", "sd1_ms " .. report.maybe_two(stats.sd1), "sd2_ms " .. report.maybe_two(stats.sd2),
        "HISTOGRAM bin_ms=7.8125 bins=" .. #keys(stats.histogram) .. " max=" .. stats.histogram_max})
    for _, bucket in ipairs(keys(stats.histogram)) do
        local count = stats.histogram[bucket]
        lines[#lines + 1] = pad(report.four(78125 * bucket), 10) .. " " .. pad(report.four(78125 * (bucket + 1)), 10) .. " " .. pad(count, 3) .. " |" .. string.rep("#", count)
    end
    lines[#lines + 1] = stats.e == 0 and "triangular_index none" or "triangular_index " .. report.fraction(stats.e, stats.histogram_max) .. " " .. report.two(stats.triangular_index)
    local premature, counts, runs = {}, {V = 0, A = 0}, {}
    for _, beat in ipairs(beats) do
        if beat.label ~= "N" then
            premature[#premature + 1] = beat
            counts[beat.label] = counts[beat.label] + 1
        end
    end
    lines[#lines + 1] = "PREMATURE count=" .. #premature .. " V=" .. counts.V .. " A=" .. counts.A
    for _, beat in ipairs(premature) do
        local preceding = 0
        for index = beat.number - 8, beat.number - 1 do
            preceding = preceding + beats[index].rr
        end
        local next_rr = beat.number < #beats and beats[beat.number + 1].rr or nil
        local compensation = "-"
        if next_rr then
            local total = beat.rr + next_rr
            compensation = 10 * math.abs(4 * total - preceding) <= preceding and "full" or 4 * total < preceding and "partial" or "long"
        end
        local ref = beat.annotation and refs[beat.annotation]
        lines[#lines + 1] = "beat=" .. beat.number .. " sample=" .. beat.sample .. " label=" .. beat.label .. " rr_ms=" .. beat.rr .. " next_rr_ms=" .. report.missing(next_rr)
            .. " mean_ms=" .. report.two(report.rdiv(100 * preceding, 8)) .. " prematurity=" .. report.two(report.rdiv(80000 * beat.rr, preceding)) .. "% compensation=" .. compensation .. " width_ms=" .. beat.width .. " ref=" .. (ref and ref.label or "-")
    end
    for _, label in ipairs({"V", "A"}) do
        local indices = {}
        for _, beat in ipairs(premature) do
            if beat.label == label then
                indices[#indices + 1] = beat.number
            end
        end
        for _, range in ipairs(hrv.ranges(indices)) do
            local first, last = range[1], range[2]
            local count = last - first + 1
            runs[#runs + 1] = {first = first, line = label .. " " .. (count == 1 and "isolated" or count == 2 and "couplet" or "run") .. " beats=" .. first .. "-" .. last .. " length=" .. count .. " start_ms=" .. 5 * beats[first].sample}
        end
    end
    table.sort(runs, function(a, b) return a.first < b.first end)
    lines[#lines + 1] = "RUNS count=" .. #runs
    for _, run in ipairs(runs) do
        lines[#lines + 1] = run.line
    end
    local events = event_lines(beats, params)
    lines[#lines + 1] = "EVENTS count=" .. #events
    append(lines, events)
    lines[#lines + 1] = "TREND segment_ms=" .. params.segment_ms .. " segments=" .. #parts
    for _, part in ipairs(parts) do
        local prefix = pad(part.start, 6) .. "-" .. pad(part.stop, 6) .. " beats=" .. part.beats .. " "
        if #part.rr == 0 then
            lines[#lines + 1] = prefix .. "mean_hr=none min_hr=none max_hr=none |"
        else
            local low, high = extrema(part.rr)
            local mean_hr = report.rdiv(6000000 * #part.rr, sum(part.rr))
            lines[#lines + 1] = prefix .. "mean_hr=" .. report.two(mean_hr) .. " min_hr=" .. report.two(report.rdiv(6000000, high)) .. " max_hr=" .. report.two(report.rdiv(6000000, low)) .. " |" .. string.rep("#", report.rdiv(mean_hr, 500))
        end
    end
    return lines
end
local function scale(value, top, bottom, rows)
    return top > bottom and report.rdiv((top - value) * (rows - 1), top - bottom) or 0
end
local function axis(columns, period, offset)
    local cells = {}
    for column = 0, columns - 1 do
        cells[#cells + 1] = period > 0 and (column + offset) % period == 0 and "+" or "-"
    end
    return "       +" .. table.concat(cells) .. "+"
end
local function chart_labels(heading, markers)
    local text = pad(heading, 6) .. "  "
    for _, marker in ipairs(markers) do
        text = text .. string.rep(" ", math.max(0, 8 + marker[1] - #text)) .. marker[2]
    end
    return text:gsub(" +$", "")
end
local function waveform(upper, lower, height)
    local bottom, top = lower[1], upper[1]
    for index = 1, #upper do
        bottom, top = math.min(bottom, lower[index]), math.max(top, upper[index])
    end
    local zero = bottom <= 0 and top >= 0 and scale(0, top, bottom, height) or nil
    local lines = {}
    for row = 0, height - 1 do
        local label = row == 0 and tostring(top) or row == height - 1 and tostring(bottom) or row == zero and "0" or ""
        local cells = {}
        for column = 1, #upper do
            cells[column] = scale(upper[column], top, bottom, height) <= row and row <= scale(lower[column], top, bottom, height) and "#" or row == zero and "-" or " "
        end
        lines[#lines + 1] = pad(label, 6) .. " |" .. table.concat(cells) .. "|"
    end
    return lines
end
local function charts(samples, beats, params)
    local rr = {}
    for index = 2, #beats do
        rr[#rr + 1] = beats[index].rr
    end
    local lines, height = {}, params.chart_rows
    if #rr == 0 then
        append(lines, {"TACHOGRAM intervals=0", "POINCARE points=0"})
    else
        local low, high = extrema(rr)
        lines[#lines + 1] = "TACHOGRAM intervals=" .. #rr .. " min_ms=" .. low .. " max_ms=" .. high .. " rows=" .. height
        for row = 0, height - 1 do
            local label = row == 0 and tostring(high) or row == height - 1 and tostring(low) or ""
            local cells = {}
            for index, value in ipairs(rr) do
                cells[index] = scale(value, high, low, height) == row and "*" or " "
            end
            lines[#lines + 1] = pad(label, 6) .. " |" .. table.concat(cells) .. "|"
        end
        lines[#lines + 1] = axis(#rr, 10, 2)
        local markers, beat_labels = {}, {}
        for index = 2, #beats do
            if index % 10 == 0 then
                markers[#markers + 1] = {index - 2, tostring(index)}
            end
            beat_labels[#beat_labels + 1] = beats[index].label
        end
        lines[#lines + 1] = chart_labels("beat", markers)
        lines[#lines + 1] = " label |" .. table.concat(beat_labels) .. "|"
        local size, grid = params.poincare_size, {}
        for row = 1, size do
            grid[row] = {}
            for column = 1, size do
                grid[row][column] = 0
            end
        end
        for index = 1, #rr - 1 do
            local column = high > low and report.rdiv((rr[index] - low) * (size - 1), high - low) or 0
            local row = scale(rr[index + 1], high, low, size)
            grid[row + 1][column + 1] = grid[row + 1][column + 1] + 1
        end
        lines[#lines + 1] = "POINCARE points=" .. (#rr - 1) .. " size=" .. size .. " min_ms=" .. low .. " max_ms=" .. high
        for row = 0, size - 1 do
            local label = row == 0 and tostring(high) or row == size - 1 and tostring(low) or ""
            local cells = {}
            for column, count in ipairs(grid[row + 1]) do
                cells[column] = count == 0 and "." or count < 10 and tostring(count) or "#"
            end
            lines[#lines + 1] = pad(label, 6) .. " |" .. table.concat(cells) .. "|"
        end
        lines[#lines + 1] = axis(size, 0, 0)
        local text = "        " .. low
        lines[#lines + 1] = text .. string.rep(" ", math.max(0, 8 + size - #tostring(high) - #text)) .. high
    end
    for _, label in ipairs(labels) do
        local chosen, baselines = {}, {}
        for _, beat in ipairs(beats) do
            if beat.label == label and beat.sample >= 60 and beat.sample <= #samples - 100 then
                chosen[#chosen + 1] = beat
                local baseline = 0
                for offset = -60, -51 do
                    baseline = baseline + samples[beat.sample + offset + 1]
                end
                baselines[#baselines + 1] = baseline
            end
        end
        if #chosen == 0 then
            lines[#lines + 1] = "TEMPLATE " .. label .. " beats=0"
        else
            local averaged = {}
            for offset = -60, 99 do
                local total = 0
                for index, beat in ipairs(chosen) do
                    total = total + 10 * samples[beat.sample + offset + 1] - baselines[index]
                end
                averaged[#averaged + 1] = report.rdiv(total, 10 * #chosen)
            end
            local low, high = extrema(averaged)
            local maximum, minimum
            for index, value in ipairs(averaged) do
                if value == high and not maximum then
                    maximum = index - 61
                end
                if value == low and not minimum then
                    minimum = index - 61
                end
            end
            lines[#lines + 1] = "TEMPLATE " .. label .. " beats=" .. #chosen .. " max_uv=" .. high .. " max_ms=" .. 5 * maximum .. " min_uv=" .. low .. " min_ms=" .. 5 * minimum .. " rows=" .. height
            local upper, lower = {}, {}
            for column = 0, 79 do
                upper[column + 1], lower[column + 1] = math.max(averaged[2 * column + 1], averaged[2 * column + 2]), math.min(averaged[2 * column + 1], averaged[2 * column + 2])
            end
            append(lines, waveform(upper, lower, height))
            lines[#lines + 1] = axis(80, 10, 0)
            local markers = {}
            for column = 0, 70, 10 do
                markers[#markers + 1] = {column, tostring(10 * column - 300)}
            end
            lines[#lines + 1] = chart_labels("ms", markers)
        end
    end
    return lines
end
local function rhythm_strip(samples, beats, refs, params)
    local start, count = params.strip_start_ms // 5, params.strip_ms // 5
    local columns, upper, lower = count // 10, {}, {}
    for column = 0, columns - 1 do
        local low, high = samples[start + 10 * column + 1], samples[start + 10 * column + 1]
        for offset = 1, 9 do
            local value = samples[start + 10 * column + offset + 1]
            low, high = math.min(low, value), math.max(high, value)
        end
        upper[column + 1], lower[column + 1] = high, low
    end
    local low, high = lower[1], upper[1]
    for column = 1, columns do
        low, high = math.min(low, lower[column]), math.max(high, upper[column])
    end
    local lines = {"RHYTHM start_ms=" .. params.strip_start_ms .. " end_ms=" .. (params.strip_start_ms + params.strip_ms) .. " columns=" .. columns .. " rows=" .. params.strip_rows .. " max_uv=" .. high .. " min_uv=" .. low}
    append(lines, waveform(upper, lower, params.strip_rows))
    lines[#lines + 1] = axis(columns, 20, 0)
    local markers, beat_marks, ref_marks = {}, {}, {}
    for column = 0, columns - 1 do
        beat_marks[column + 1], ref_marks[column + 1] = " ", " "
        if column % 20 == 0 then
            markers[#markers + 1] = {column, tostring((params.strip_start_ms + 50 * column) // 1000)}
        end
    end
    lines[#lines + 1] = chart_labels("s", markers)
    for _, beat in ipairs(beats) do
        if beat.sample >= start and beat.sample < start + count then
            beat_marks[(beat.sample - start) // 10 + 1] = beat.label
        end
    end
    for _, ref in ipairs(refs) do
        if ref.sample >= start and ref.sample < start + count then
            ref_marks[(ref.sample - start) // 10 + 1] = ref.label
        end
    end
    append(lines, {" beats |" .. table.concat(beat_marks) .. "|", "  refs |" .. table.concat(ref_marks) .. "|"})
    return lines
end
local samples, refs, params = signal_io.read_ecg(), signal_io.read_annotations(), signal_io.read_params()
local signals = filters.run(samples)
local peaks = detector.find_peaks(signals)
local detection = detect(peaks, signals, params)
local beats = beat_list(detection.registered, signals.bandpass, params)
match(beats, refs, params.match_ms // 5)
local parts = segments(beats, refs, peaks, #samples, params)
os.execute('mkdir -p output')
signal_io.write_lines("beats.csv", beat_csv(beats, refs))
signal_io.write_lines("peaks.csv", peak_csv(peaks))
signal_io.write_lines("matching.csv", matching_csv(beats, refs))
signal_io.write_lines("signals_excerpt.csv", excerpt(samples, signals, params.excerpt_ms // 5))
signal_io.write_lines("performance.txt", performance(beats, refs, peaks, detection, params, parts, #samples))
signal_io.write_lines("hrv.txt", variability(beats, refs, parts, params))
signal_io.write_lines("charts.txt", charts(samples, beats, params))
signal_io.write_lines("rhythm_strip.txt", rhythm_strip(samples, beats, refs, params))
