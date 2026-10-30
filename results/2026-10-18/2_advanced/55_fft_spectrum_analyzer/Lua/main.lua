local signal_io = require("signal_io")
local fft = require("fft")
local windows = require("windows")
local spectral = require("spectral")
local report = require("report")
local real = report.real
local function sum(values)
    local total = 0.0
    for _, value in ipairs(values) do total = total + value end
    return total
end
local function energy(values)
    local total = 0.0
    for _, value in ipairs(values) do total = total + value * value end
    return total
end
local function rms(values) return math.sqrt(energy(values) / #values) end
local function db(value, factor) return (factor or 20) * math.log(value, 10) end
local function phase(value) return math.atan(value[2], value[1]) * 180 / fft.pi end
local function slice(values, first, last)
    local result = {}
    for i = first, last do result[#result + 1] = values[i] end
    return result
end
local function strongest(values, limit)
    local result = {}
    for i = 2, #values - 1 do if spectral.local_maximum(values, i) then result[#result + 1] = i end end
    table.sort(result, function(a, b) return values[a] > values[b] or values[a] == values[b] and a < b end)
    while #result > limit do result[#result] = nil end
    return result
end
local function maximum(values, first, last, accept)
    local best
    for i = first, last do
        if (not accept or accept(i)) and (not best or values[i] > values[best]) then best = i end
    end
    return best
end
local function detrend(samples, fs)
    local count, average = #samples, sum(samples) / #samples
    local center, numerator, denominator = (count - 1) / 2, 0.0, 0.0
    local low, high = samples[1], samples[1]
    for i, value in ipairs(samples) do
        local offset = i - 1 - center
        numerator, denominator = numerator + offset * (value - average), denominator + offset * offset
        low, high = math.min(low, value), math.max(high, value)
    end
    local slope, residual = numerator / denominator, {}
    local peak, third, fourth = 0.0, 0.0, 0.0
    for i, value in ipairs(samples) do
        local v = value - average - slope * (i - 1 - center)
        residual[i], peak = v, math.max(peak, math.abs(v))
        third, fourth = third + v ^ 3, fourth + v ^ 4
    end
    local level = rms(residual)
    return residual, {average, slope * fs, level, low, high, peak / level, (third / count) / level ^ 3, (fourth / count) / level ^ 4}
end
local function bandwidth(a, index)
    local cutoff = a[index] / math.sqrt(2)
    local left, right = 0.0, #a - 1.0
    for j = index + 1, #a do
        if a[j] <= cutoff then right = j - 2 + (a[j - 1] - cutoff) / (a[j - 1] - a[j]); break end
    end
    for j = index - 1, 1, -1 do
        if a[j] <= cutoff then left = j - (a[j + 1] - cutoff) / (a[j + 1] - a[j]); break end
    end
    return right - left
end
local function analyze_peaks(a, transformed, params, fs, welch)
    local length, nominal, width = params.main_length[1], params.fundamental[1], params.fundamental[2]
    local largest = a[maximum(a, 1, #a)]
    local floor = spectral.median(slice(a, 2, #a - 1))
    local peaks = {}
    for _, index in ipairs(strongest(a, #a)) do
        if db(a[index] / largest) >= params.peak_threshold_db[1] and #peaks < params.peak_count[1] then
            local position, amplitude = spectral.interpolate(a, index)
            local k = index - 1
            local coherence_bin = (2 * k * params.welch[1] + length) // (2 * length)
            peaks[#peaks + 1] = {index = index, bin = k, position = position, amplitude = amplitude,
                frequency = k * fs / length, refined = position * fs / length, level_db = db(a[index] / largest),
                phase = phase(transformed[index]), bandwidth = bandwidth(a, index) * fs / length,
                snr_db = db(a[index] / floor), coherence = welch.coherence[coherence_bin + 1]}
        end
    end
    for _, peak in ipairs(peaks) do
        peak.label = "other"
        for h = 1, 10 do
            if math.abs(peak.position - h * nominal * length / fs) <= width then peak.label = "h" .. h; break end
        end
        if peak.label == "other" then
            local fq, fn, wn = peak.refined, params.notch[1], params.notch[2]
            local multiple = math.floor(fq / fn + 0.5)
            if multiple >= 1 and math.abs(fq - multiple * fn) <= wn then peak.label = "mains" end
        end
        if peak.label == "other" then
            for rank, pivot in ipairs(peaks) do
                if pivot ~= peak and a[pivot.index] > a[peak.index] then
                    for _, other in ipairs(peaks) do
                        if other ~= peak and other ~= pivot and a[pivot.index] > a[other.index]
                            and math.abs(peak.position + other.position - 2 * pivot.position) <= 1 then peak.label = "sideband" .. rank; break end
                    end
                end
                if peak.label ~= "other" then break end
            end
        end
    end
    return peaks, largest, floor
end
local function analyze_filters(x, y, params, fs)
    local count, transformed = #x, fft.dft(fft.complex(x))
    local band, notch, analytic_spectrum = fft.zeros(count), fft.zeros(count), fft.zeros(count)
    local kept, removed = 0, 0
    local low, high = table.unpack(params.bandpass)
    local fn, wn = table.unpack(params.notch)
    local e1, e2 = table.unpack(params.envelope_band)
    for k = 0, count - 1 do
        local g = math.min(k, count - k) * fs
        if low * count <= g and g <= high * count then band[k + 1], kept = transformed[k + 1], kept + 1 end
        local multiple = (2 * g + fn * count) // (2 * fn * count)
        if multiple >= 1 and math.abs(g - multiple * fn * count) <= wn * count then removed = removed + 1
        else notch[k + 1] = transformed[k + 1] end
        if k >= 1 and k <= (count - 1) // 2 and e1 * count <= k * fs and k * fs <= e2 * count then
            analytic_spectrum[k + 1] = fft.scale(transformed[k + 1], 2)
        end
    end
    local bandpassed, notched, envelope = {}, {}, {}
    local bp, nt, analytic = fft.idft(band), fft.idft(notch), fft.idft(analytic_spectrum)
    for i = 1, count do bandpassed[i], notched[i], envelope[i] = bp[i][1], nt[i][1], fft.abs(analytic[i]) end
    local emean = sum(envelope) / count
    local centered = {}
    for i, value in ipairs(envelope) do centered[i] = value - emean end
    local modulation = {}
    for i, value in ipairs(fft.dft(fft.complex(centered))) do modulation[i] = 2 * fft.abs(value) / count end
    local ebin = maximum(modulation, 2, ((e2 - e1) * count) // (2 * fs) + 1)
    local eposition, eamplitude = spectral.interpolate(modulation, ebin)
    local instantaneous = {}
    for i = 2, count do
        local delta = math.atan(analytic[i][2], analytic[i][1]) - math.atan(analytic[i - 1][2], analytic[i - 1][1])
        if delta <= -fft.pi then delta = delta + 2 * fft.pi end
        if delta > fft.pi then delta = delta - 2 * fft.pi end
        instantaneous[#instantaneous + 1] = delta * fs / (2 * fft.pi)
    end
    local frequency_mean = sum(instantaneous) / #instantaneous
    local variance = 0.0
    for _, value in ipairs(instantaneous) do variance = variance + (value - frequency_mean) ^ 2 end
    local taps, gain = params.fir, {0.0, 0.0}
    local smoothed = fft.convolution(y, taps)
    for j, value in ipairs(taps) do gain = fft.add(gain, fft.scale(fft.rot(2 * fft.pi * params.fundamental[1] * (j - 1) / fs), value)) end
    local fir_error = 0.0
    for i = 0, count + #taps - 2 do
        local direct = 0.0
        for j = math.max(0, i - #taps + 1), math.min(count - 1, i) do direct = direct + y[j + 1] * taps[i - j + 1] end
        fir_error = math.max(fir_error, math.abs(smoothed[i + 1] - direct))
    end
    return {bandpassed = bandpassed, notched = notched, envelope = envelope, smoothed = smoothed,
        kept = kept, removed = removed, band_rms = rms(bandpassed), notch_rms = rms(notched),
        band_ratio = energy(bandpassed) / energy(x), dc_gain = sum(taps), fir_gain = db(fft.abs(gain)),
        fir_rms = rms(slice(smoothed, 1, count)), fir_error = fir_error, envelope_mean = emean, envelope_bin = ebin - 1,
        envelope_frequency = eposition * fs / count, envelope_amplitude = eamplitude, envelope_depth = eamplitude / emean,
        instantaneous_mean = frequency_mean, instantaneous_std = math.sqrt(variance / #instantaneous)}
end
local function choose_lag(values, limit)
    local best = -limit
    for lag = -limit, limit do
        local value, previous = values[lag % #values + 1], values[best % #values + 1]
        if value > previous or value == previous and (math.abs(lag) < math.abs(best) or math.abs(lag) == math.abs(best) and lag < best) then best = lag end
    end
    local local_values = {values[(best - 1) % #values + 1], values[best % #values + 1], values[(best + 1) % #values + 1]}
    local position = spectral.interpolate(local_values, 2, false)
    return best, best + position - 1
end
local function correlation(x, y, limit, fs)
    local size = fft.pow2(2 * #x - 1)
    local fx, fy = fft.radix2(fft.complex(x, size)), fft.radix2(fft.complex(y, size))
    local cross, phased = {}, {}
    for k = 1, size do cross[k] = fft.mul(fft.conj(fx[k]), fy[k]); phased[k] = fft.divide(cross[k], fft.abs(cross[k])) end
    local inverse, pinverse = fft.radix2(cross, true), fft.radix2(phased, true)
    local raw, phat = {}, {}
    for i = 1, size do raw[i], phat[i] = inverse[i][1], pinverse[i][1] end
    local lag, refined = choose_lag(raw, limit)
    local phat_lag, phat_refined = choose_lag(phat, limit)
    return {lag = lag, refined = refined, delay = 1000 * refined / fs,
        coefficient = raw[lag % size + 1] / math.sqrt(energy(x) * energy(y)),
        phat_lag = phat_lag, phat_refined = phat_refined, phat_delay = 1000 * phat_refined / fs}
end
local function analyze_pitch(a, bandpassed, params, fs)
    local length, low, high = params.main_length[1], params.pitch_range[1], params.pitch_range[2]
    local half, hps_bin, hps_value = length // 2, nil, -math.huge
    for k = 1, half do
        if low * length <= k * fs and k * fs <= high * length and 5 * k <= half then
            local value = 0.0
            for r = 1, 5 do value = value + math.log(a[r * k + 1]) end
            if value > hps_value then hps_bin, hps_value = k, value end
        end
    end
    local size = fft.pow2(2 * #bandpassed - 1)
    local transformed = fft.radix2(fft.complex(bandpassed, size))
    local power = {}
    for i, value in ipairs(transformed) do power[i] = {fft.abs(value) ^ 2, 0.0} end
    local acf = {}
    for i, value in ipairs(fft.radix2(power, true)) do acf[i] = value[1] end
    local lag_min, lag_max = (fs + high - 1) // high, fs // low
    local lag_index = maximum(acf, lag_min + 1, lag_max + 1)
    local period, strength = spectral.interpolate(acf, lag_index, false)
    local crossings = 0
    for i = 2, #bandpassed do if bandpassed[i - 1] < 0 and bandpassed[i] >= 0 then crossings = crossings + 1 end end
    return {lag_min = lag_min, lag_max = lag_max, hps_bin = hps_bin, hps_frequency = hps_bin * fs / length,
        acf_lag = lag_index - 1, period = period, frequency = fs / period, strength = strength / acf[1],
        crossings = crossings, crossing_frequency = crossings * fs / #bandpassed}
end
local function run()
    local fs, raw_x, raw_y, params = signal_io.read()
    local count, length, name = #raw_x, params.main_length[1], params.main_window[1]
    local x, stats_x = detrend(raw_x, fs)
    local y, stats_y = detrend(raw_y, fs)
    local weighted, transformed, a = spectral.amplitude(x, name, length)
    local figures = windows.figures(windows.window(name, length), fs)
    local half, nominal, width = length // 2, params.fundamental[1], params.fundamental[2]
    local welch = spectral.welch(x, y, fs, params.welch[1], params.welch[2])
    local peaks, largest, floor = analyze_peaks(a, transformed, params, fs, welch)
    local harmonics, harmonic_energy = {}, 0.0
    for h = 1, 10 do
        local center = h * nominal * length / fs
        local index = maximum(a, 2, half, function(i) return math.abs(i - 1 - center) <= width end)
        local position, amplitude = spectral.interpolate(a, index)
        harmonics[h] = {bin = index - 1, position = position, amplitude = amplitude, refined = position * fs / length}
        if h > 1 then harmonic_energy = harmonic_energy + amplitude * amplitude end
    end
    local primary = harmonics[1].amplitude
    for _, harmonic in ipairs(harmonics) do harmonic.level_db = db(harmonic.amplitude / primary) end
    local thd = math.sqrt(harmonic_energy) / primary
    local power, total, first_power, weighted_frequency, log_power = {}, 0.0, 0.0, 0.0, 0.0
    for k = 1, half - 1 do
        local value = a[k + 1] * a[k + 1] / 2
        power[k + 1], total = value, total + value
        if math.abs(k - harmonics[1].bin) <= width then first_power = first_power + value end
        weighted_frequency, log_power = weighted_frequency + (k * fs / length) * value, log_power + math.log(value)
    end
    local total_power, p1 = total / figures.enbw_bins, first_power / figures.enbw_bins
    local thdn, centroid = math.sqrt((total_power - p1) / p1), weighted_frequency / total
    local spread, cumulative, rolloff = 0.0, 0.0, nil
    for k = 1, half - 1 do
        spread = spread + (k * fs / length - centroid) ^ 2 * power[k + 1]
        cumulative = cumulative + power[k + 1]
        if not rolloff and cumulative >= 0.85 * total then rolloff = k * fs / length end
    end
    spread = math.sqrt(spread / total)
    local flatness = db(math.exp(log_power / (half - 1)) / (total / (half - 1)), 10)
    local frame_length, hop, band_db, frame_window = table.unpack(params.spectrogram)
    local grid, frame_error = spectral.spectrogram(x, frame_length, hop, frame_window)
    local gmax = 0.0
    for _, row in ipairs(grid) do for _, value in ipairs(row) do gmax = math.max(gmax, value) end end
    local dominant, flux, kurtosis = {}, {0.0}, {}
    for t, row in ipairs(grid) do
        dominant[t] = maximum(row, 2, frame_length // 2)
        if t > 1 then
            local value = 0.0
            for k, amplitude in ipairs(row) do value = value + math.max(0.0, amplitude - grid[t - 1][k]) end
            flux[t] = value
        end
    end
    local onset_threshold = params.onset_factor[1] * spectral.median(slice(flux, 2, #flux))
    local onsets = {}
    for t = 2, #grid do
        if flux[t] > onset_threshold and flux[t] > flux[t - 1] and (t == #grid or flux[t] > flux[t + 1]) then onsets[#onsets + 1] = t end
    end
    for k = 1, frame_length // 2 + 1 do
        local second, fourth = 0.0, 0.0
        for _, row in ipairs(grid) do second, fourth = second + row[k] ^ 2, fourth + row[k] ^ 4 end
        kurtosis[k] = #grid * fourth / (second * second) - 2
    end
    local top_kurtosis = maximum(kurtosis, 2, frame_length // 2)
    local filters = analyze_filters(x, y, params, fs)
    local pitch = analyze_pitch(a, filters.bandpassed, params, fs)
    local cross = correlation(x, y, params.max_lag[1], fs)
    local z1, z2, zoom_count = table.unpack(params.zoom)
    local zoom_step, zoom = (z2 - z1) / (zoom_count - 1), {}
    for i, value in ipairs(fft.chirp_z(weighted, fs, z1, z2, zoom_count)) do zoom[i] = 2 * fft.abs(value) / figures.s1 end
    local inverse_error, time_energy, frequency_energy = 0.0, energy(weighted), 0.0
    for i, value in ipairs(fft.idft(transformed)) do inverse_error = math.max(inverse_error, fft.abs(fft.sub(value, {weighted[i], 0.0}))) end
    for _, value in ipairs(transformed) do frequency_energy = frequency_energy + fft.abs(value) ^ 2 end
    local parseval_error = math.abs(time_energy - frequency_energy / length) / time_energy
    local spot_error = 0.0
    for _, peak in ipairs(peaks) do
        local direct = {0.0, 0.0}
        for n = 0, length - 1 do direct = fft.add(direct, fft.scale(fft.rot(2 * fft.pi * ((peak.bin * n) % length) / length), weighted[n + 1])) end
        spot_error = math.max(spot_error, fft.abs(fft.sub(direct, transformed[peak.index])))
    end
    local spectrum_rows, psd_rows, filtered_rows = {}, {}, {}
    for k = 0, half do spectrum_rows[#spectrum_rows + 1] = {real(k * fs / length), real(a[k + 1])} end
    for k, value in ipairs(welch.psd) do psd_rows[#psd_rows + 1] = {real((k - 1) * fs / params.welch[1]), real(db(value, 10))} end
    for i = 1, count do
        filtered_rows[i] = {tostring(i - 1), real(filters.bandpassed[i]), real(filters.notched[i]), real(filters.smoothed[i]), real(filters.envelope[i])}
    end
    report.csv("spectrum.csv", "frequency,amplitude", spectrum_rows)
    report.csv("welch_psd.csv", "frequency,psd_db", psd_rows)
    report.csv("filtered.csv", "index,bandpass,notched,smoothed,envelope", filtered_rows)
    local peak_lines = {"length=" .. length .. " window=" .. name .. " resolution=" .. real(fs / length) .. " threshold_db=" .. real(params.peak_threshold_db[1]),
        "max_amplitude=" .. real(largest) .. " noise_floor=" .. real(floor) .. " noise_floor_db=" .. real(db(floor)), "peaks=" .. #peaks}
    for rank, peak in ipairs(peaks) do
        peak_lines[#peak_lines + 1] = rank .. " bin=" .. peak.bin .. " frequency=" .. real(peak.frequency) .. " refined=" .. real(peak.refined)
            .. " amplitude=" .. real(peak.amplitude) .. " level_db=" .. real(peak.level_db) .. " phase=" .. real(peak.phase)
            .. " bandwidth=" .. real(peak.bandwidth) .. " snr_db=" .. real(peak.snr_db) .. " coherence=" .. real(peak.coherence) .. " label=" .. peak.label
    end
    report.write("peaks.txt", peak_lines)
    local spectrogram_lines = {"frames=" .. #grid .. " bins=" .. (frame_length // 2 + 1) .. " frame_length=" .. frame_length .. " hop=" .. hop
        .. " window=" .. frame_window .. " band_db=" .. band_db .. " max_db=" .. real(db(gmax))}
    for _, line in ipairs(report.shades(grid, fs, frame_length, band_db, gmax)) do spectrogram_lines[#spectrogram_lines + 1] = line end
    spectrogram_lines[#spectrogram_lines + 1] = "track"
    for t, index in ipairs(dominant) do
        spectrogram_lines[#spectrogram_lines + 1] = "frame=" .. (t - 1) .. " time=" .. real((t - 1) * hop / fs)
            .. " frequency=" .. real((index - 1) * fs / frame_length) .. " level_db=" .. real(db(grid[t][index] / gmax))
    end
    spectrogram_lines[#spectrogram_lines + 1] = "onsets=" .. #onsets .. " threshold=" .. real(onset_threshold)
    for _, t in ipairs(onsets) do spectrogram_lines[#spectrogram_lines + 1] = "frame=" .. (t - 1) .. " time=" .. real((t - 1) * hop / fs) .. " flux=" .. real(flux[t]) end
    spectrogram_lines[#spectrogram_lines + 1] = "kurtosis bin=" .. (top_kurtosis - 1) .. " frequency=" .. real((top_kurtosis - 1) * fs / frame_length) .. " value=" .. real(kurtosis[top_kurtosis])
    report.write("spectrogram.txt", spectrogram_lines)
    local lines = {"[signal]", "sample_rate=" .. fs .. " samples=" .. count .. " duration=" .. real(count / fs)}
    local stat_names = {"mean", "slope", "rms", "min", "max", "crest", "skewness", "kurtosis"}
    for channel, stats in ipairs({stats_x, stats_y}) do
        local line = "channel=" .. channel
        for i, key in ipairs(stat_names) do line = line .. " " .. key .. "=" .. real(stats[i]) end
        lines[#lines + 1] = line
    end
    local block_length, history, loudest = params.block_length[1], {}, 1
    for block = 0, count // block_length - 1 do
        local left = slice(x, block * block_length + 1, (block + 1) * block_length)
        local right = slice(y, block * block_length + 1, (block + 1) * block_length)
        local peak = 0.0
        for _, value in ipairs(left) do peak = math.max(peak, math.abs(value)) end
        history[#history + 1] = {rms(left), rms(right), peak}
        if history[#history][1] > history[loudest][1] then loudest = #history end
    end
    lines[#lines + 1] = "[levels]"
    lines[#lines + 1] = "block_length=" .. block_length .. " blocks=" .. #history .. " loudest=" .. (loudest - 1)
    for i, row in ipairs(history) do
        lines[#lines + 1] = "block=" .. (i - 1) .. " time=" .. real((i - 1) * block_length / fs) .. " rms1=" .. real(row[1]) .. " rms2=" .. real(row[2]) .. " peak1=" .. real(row[3])
    end
    lines[#lines + 1] = "[windows]"
    for _, window_name in ipairs(windows.order) do
        local calibration = windows.figures(windows.window(window_name, length), fs)
        local _, _, aw = spectral.amplitude(x, window_name, length)
        local index = maximum(aw, 2, half, function(i) return math.abs(i - 1 - nominal * length / fs) <= width end)
        local _, refined = spectral.interpolate(aw, index)
        lines[#lines + 1] = "name=" .. window_name .. " coherent_gain=" .. real(calibration.coherent_gain) .. " enbw_bins=" .. real(calibration.enbw_bins)
            .. " enbw_hz=" .. real(calibration.enbw_hz) .. " scalloping_db=" .. real(calibration.scalloping_db) .. " fundamental_bin=" .. (index - 1)
            .. " bin_amplitude=" .. real(aw[index]) .. " refined_amplitude=" .. real(refined) .. " floor_db=" .. real(db(spectral.median(slice(aw, 2, #aw - 1))))
    end
    local power_two = fft.pow2(length) == length
    lines[#lines + 1] = "[main]"
    lines[#lines + 1] = "length=" .. length .. " window=" .. name .. " method=" .. (power_two and "radix2" or "bluestein")
        .. " transform_size=" .. (power_two and length or fft.pow2(2 * length - 1)) .. " resolution=" .. real(fs / length)
    lines[#lines + 1] = "total_power=" .. real(total_power) .. " centroid=" .. real(centroid) .. " spread=" .. real(spread) .. " rolloff=" .. real(rolloff) .. " flatness_db=" .. real(flatness)
    lines[#lines + 1] = "[bands]"
    for i = 1, #params.bands - 1 do
        local low, high, value = params.bands[i], params.bands[i + 1], 0.0
        for k = 1, half - 1 do if low * length <= k * fs and k * fs < high * length then value = value + power[k + 1] end end
        value = value / figures.enbw_bins
        lines[#lines + 1] = "range=" .. low .. "-" .. high .. " power=" .. real(value) .. " percent=" .. real(100 * value / total_power)
    end
    lines[#lines + 1] = "[third_octave]"
    for band = params.third_octave[1], params.third_octave[2] do
        local center, low, high = 1000 * 2 ^ (band / 3), 1000 * 2 ^ ((2 * band - 1) / 6), 1000 * 2 ^ ((2 * band + 1) / 6)
        local value, bins = 0.0, 0
        for k = 1, half - 1 do
            local frequency = k * fs / length
            if low <= frequency and frequency < high then value, bins = value + power[k + 1], bins + 1 end
        end
        lines[#lines + 1] = "band=" .. band .. " center=" .. real(center) .. " lower=" .. real(low) .. " upper=" .. real(high)
            .. " bins=" .. bins .. " level_db=" .. real(db(value / figures.enbw_bins, 10))
    end
    lines[#lines + 1] = "[harmonics]"
    lines[#lines + 1] = "fundamental=" .. real(nominal) .. " search=" .. width
    for h, harmonic in ipairs(harmonics) do
        lines[#lines + 1] = "h=" .. h .. " target=" .. real(h * nominal) .. " bin=" .. harmonic.bin .. " refined=" .. real(harmonic.refined)
            .. " amplitude=" .. real(harmonic.amplitude) .. " level_db=" .. real(harmonic.level_db)
    end
    lines[#lines + 1] = "thd_percent=" .. real(100 * thd) .. " thd_db=" .. real(db(thd))
    lines[#lines + 1] = "thdn_percent=" .. real(100 * thdn) .. " thdn_db=" .. real(db(thdn))
    lines[#lines + 1] = "[pitch]"
    lines[#lines + 1] = "range=" .. params.pitch_range[1] .. "-" .. params.pitch_range[2] .. " lags=" .. pitch.lag_min .. "-" .. pitch.lag_max
    lines[#lines + 1] = "hps bin=" .. pitch.hps_bin .. " order=5 frequency=" .. real(pitch.hps_frequency)
    lines[#lines + 1] = "autocorrelation lag=" .. pitch.acf_lag .. " period=" .. real(pitch.period) .. " frequency=" .. real(pitch.frequency) .. " strength=" .. real(pitch.strength)
    lines[#lines + 1] = "zero_crossing count=" .. pitch.crossings .. " frequency=" .. real(pitch.crossing_frequency)
    lines[#lines + 1] = "[zoom]"
    lines[#lines + 1] = "band=" .. z1 .. "-" .. z2 .. " points=" .. zoom_count .. " step=" .. real(zoom_step)
    for rank, index in ipairs(strongest(zoom, 3)) do
        local position, amplitude = spectral.interpolate(zoom, index)
        lines[#lines + 1] = "peak=" .. rank .. " frequency=" .. real(z1 + position * zoom_step) .. " amplitude=" .. real(amplitude)
    end
    local integrated, variance = sum(welch.psd) * fs / params.welch[1], energy(x) / count
    lines[#lines + 1] = "[welch]"
    lines[#lines + 1] = "segment_length=" .. params.welch[1] .. " segments=" .. welch.segments .. " window=" .. params.welch[2] .. " resolution=" .. real(fs / params.welch[1])
    lines[#lines + 1] = "integrated_power=" .. real(integrated) .. " variance=" .. real(variance) .. " ratio=" .. real(integrated / variance)
    for rank, index in ipairs(strongest(welch.psd, 5)) do
        lines[#lines + 1] = "peak=" .. rank .. " frequency=" .. real((index - 1) * fs / params.welch[1]) .. " psd_db=" .. real(db(welch.psd[index], 10))
            .. " coherence=" .. real(welch.coherence[index]) .. " gain=" .. real(fft.abs(welch.transfer[index])) .. " phase=" .. real(phase(welch.transfer[index]))
    end
    lines[#lines + 1] = "[filter]"
    lines[#lines + 1] = "bandpass=" .. params.bandpass[1] .. "-" .. params.bandpass[2] .. " bins_kept=" .. filters.kept .. " rms=" .. real(filters.band_rms) .. " energy_ratio=" .. real(filters.band_ratio)
    lines[#lines + 1] = "notch=" .. params.notch[1] .. " width=" .. params.notch[2] .. " bins_removed=" .. filters.removed .. " rms=" .. real(filters.notch_rms)
    lines[#lines + 1] = "fir_taps=" .. #params.fir .. " dc_gain=" .. real(filters.dc_gain) .. " gain_at_fundamental_db=" .. real(filters.fir_gain) .. " rms=" .. real(filters.fir_rms)
    lines[#lines + 1] = "[envelope]"
    lines[#lines + 1] = "band=" .. params.envelope_band[1] .. "-" .. params.envelope_band[2] .. " mean=" .. real(filters.envelope_mean) .. " bin=" .. filters.envelope_bin
        .. " frequency=" .. real(filters.envelope_frequency) .. " amplitude=" .. real(filters.envelope_amplitude) .. " depth=" .. real(filters.envelope_depth)
    lines[#lines + 1] = "instantaneous_frequency mean=" .. real(filters.instantaneous_mean) .. " std=" .. real(filters.instantaneous_std)
    lines[#lines + 1] = "[correlation]"
    lines[#lines + 1] = "max_lag=" .. params.max_lag[1] .. " lag=" .. cross.lag .. " refined_lag=" .. real(cross.refined) .. " delay_ms=" .. real(cross.delay) .. " coefficient=" .. real(cross.coefficient)
    lines[#lines + 1] = "phat_lag=" .. cross.phat_lag .. " refined_lag=" .. real(cross.phat_refined) .. " delay_ms=" .. real(cross.phat_delay)
    lines[#lines + 1] = "[checks]"
    local checks = {{"inverse_roundtrip", inverse_error}, {"parseval", parseval_error}, {"real_packing", math.max(welch.packing_error, frame_error)}, {"fir_fft_vs_direct", filters.fir_error}, {"dft_spot_check", spot_error}}
    for _, check in ipairs(checks) do
        local line = check[1] .. "=" .. (check[2] <= 1e-6 and "ok" or "failed")
        if check[1] == "real_packing" then line = line .. " transforms=" .. (2 * welch.segments + #grid)
        elseif check[1] == "dft_spot_check" then line = line .. " bins=" .. #peaks end
        lines[#lines + 1] = line
    end
    local ratio, loose, electrical_level = harmonics[2].amplitude / primary, 0, nil
    for h = 3, 10 do if harmonics[h].level_db >= -30 then loose = loose + 1 end end
    for _, peak in ipairs(peaks) do if peak.label == "mains" then electrical_level = peak.level_db; break end end
    local symptoms = {ratio >= 0.5, loose >= 3, filters.envelope_depth >= 0.2, electrical_level ~= nil and electrical_level >= -20, #onsets > 0}
    local findings = 0
    for _, yes in ipairs(symptoms) do if yes then findings = findings + 1 end end
    local function yes_no(value) return value and "yes" or "no" end
    lines[#lines + 1] = "[diagnosis]"
    lines[#lines + 1] = "misalignment=" .. yes_no(symptoms[1]) .. " ratio=" .. real(ratio)
    lines[#lines + 1] = "looseness=" .. yes_no(symptoms[2]) .. " harmonics=" .. loose
    lines[#lines + 1] = "bearing=" .. yes_no(symptoms[3]) .. " depth=" .. real(filters.envelope_depth)
    lines[#lines + 1] = "electrical=" .. yes_no(symptoms[4]) .. " level_db=" .. (electrical_level and real(electrical_level) or "none")
    lines[#lines + 1] = "transient=" .. yes_no(symptoms[5]) .. " onsets=" .. #onsets
    lines[#lines + 1] = "status=" .. (findings == 0 and "normal" or findings == 1 and "warning" or "alarm") .. " findings=" .. findings
    report.write("report.txt", lines)
end
run()
