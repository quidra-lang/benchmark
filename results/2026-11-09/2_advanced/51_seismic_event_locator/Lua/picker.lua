local M = {}
local function median(values)
    table.sort(values)
    local middle = #values // 2
    return #values % 2 == 1 and values[middle + 1] + 0.0 or (values[middle] + values[middle + 1]) / 2.0
end
function M.detect(station, ordinal, params)
    local samples, n = station.samples, #station.samples
    local total = 0
    for _, value in ipairs(samples) do
        total = total + value
    end
    local mean = total // n
    local centered, energy, prefix, absolute = {}, {}, {0}, {}
    local peak, clipped_samples = 0, 0
    for index, value in ipairs(samples) do
        local difference = value - mean
        centered[index], energy[index], absolute[index] = difference, difference * difference, math.abs(difference)
        prefix[index + 1] = prefix[index] + energy[index]
        peak = math.max(peak, absolute[index])
        clipped_samples = clipped_samples + (math.abs(value) >= params.clip_level and 1 or 0)
    end
    local sw, lw = params.sta_window, params.lta_window
    local picks, on, beginning, peak_ratio = {}, false, nil, 0.0
    local triggers, short = 0, 0
    local function finish(ending)
        triggers = triggers + 1
        local duration = ending - beginning
        if duration < params.min_duration then
            short = short + 1
            return
        end
        local position = beginning
        while position - 1 >= beginning - sw + 1 and energy[position] >= params.noise_level do
            position = position - 1
        end
        local amplitude, clipped = 0, false
        for j = position, math.min(position + params.amplitude_window - 1, n - 1) do
            amplitude = math.max(amplitude, math.abs(centered[j + 1]))
            if math.abs(samples[j + 1]) >= params.clip_level then
                clipped = true
            end
        end
        local sample = station.start + position
        picks[#picks + 1] = {station = ordinal, sample = sample, time = sample / 100.0, duration = duration,
            ratio = peak_ratio, amplitude = amplitude, clipped = clipped, state = "unassociated", event = 0, assigned = false}
    end
    for i = sw + lw - 1, n - 1 do
        local sta = prefix[i + 2] - prefix[i - sw + 2]
        local lta = prefix[i - sw + 2] - prefix[i - sw - lw + 2]
        if not on then
            if sta * lw * params.trigger_on[2] >= params.trigger_on[1] * lta * sw then
                on, beginning, peak_ratio = true, i, (sta * lw) / (lta * sw)
            end
        elseif sta * lw * params.trigger_off[2] < params.trigger_off[1] * lta * sw then
            finish(i)
            on = false
        else
            peak_ratio = math.max(peak_ratio, (sta * lw) / (lta * sw))
        end
    end
    if on then
        finish(n)
    end
    station.statistics = {mean = mean, noise = median(absolute), peak = peak, clipped = clipped_samples,
        triggers = triggers, short = short, picks = #picks}
    return picks
end
return M
