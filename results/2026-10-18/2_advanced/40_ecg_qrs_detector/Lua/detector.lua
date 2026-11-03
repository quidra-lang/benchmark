local M = {}
function M.find_peaks(signals)
    local result, integrated, band, derivative = {}, signals.integrated, signals.bandpass, signals.derivative
    for n = 0, #integrated - 1 do
        local value, valid = integrated[n + 1], integrated[n + 1] > 0
        for j = math.max(0, n - 20), n - 1 do
            if integrated[j + 1] >= value then
                valid = false
            end
        end
        for j = n + 1, math.min(#integrated - 1, n + 20) do
            if integrated[j + 1] > value then
                valid = false
            end
        end
        if valid then
            local r, slope = math.max(0, n - 30), 0
            for j = r + 1, n do
                if math.abs(band[j + 1]) > math.abs(band[r + 1]) then
                    r = j
                end
            end
            for j = math.max(0, n - 29), n do
                slope = math.max(slope, math.abs(derivative[j + 1]))
            end
            result[#result + 1] = {time = n, r = r, peak_i = value, peak_f = math.abs(band[r + 1]), slope = slope}
        end
    end
    return result
end
function M.initial_levels(signals)
    local total_i, total_f, maximum_i, maximum_f = 0, 0, 0, 0
    for index = 1, 400 do
        local integrated, band = signals.integrated[index], math.abs(signals.bandpass[index])
        total_i, total_f = total_i + integrated, total_f + band
        maximum_i, maximum_f = math.max(maximum_i, integrated), math.max(maximum_f, band)
    end
    return {spki = maximum_i // 3, npki = total_i // 800, spkf = maximum_f // 3, npkf = total_f // 800}
end
function M.width(band, r)
    local peak, first, last = math.abs(band[r + 1]), nil, nil
    for sample = math.max(0, r - 25), math.min(#band - 1, r + 25) do
        if 4 * math.abs(band[sample + 1]) >= peak then
            first, last = first or sample, sample
        end
    end
    return 5 * (last - first + 1)
end
return M
