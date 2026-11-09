local M = {}
local function at(values, sample)
    return sample < 0 and 0 or values[sample + 1]
end
function M.run(samples)
    local c, s, low, band, derivative, squared, integrated = {}, {}, {}, {}, {}, {}, {}
    local window = 0
    for n = 0, #samples - 1 do
        c[n + 1] = 2 * at(c, n - 1) - at(c, n - 2) + at(samples, n) - 2 * at(samples, n - 6) + at(samples, n - 12)
        low[n + 1] = c[n + 1] // 32
        s[n + 1] = at(s, n - 1) + low[n + 1] - at(low, n - 32)
        band[n + 1] = at(low, n - 16) - s[n + 1] // 32
        derivative[n + 1] = (2 * band[n + 1] + at(band, n - 1) - at(band, n - 3) - 2 * at(band, n - 4)) // 8
        squared[n + 1] = derivative[n + 1] * derivative[n + 1]
        window = window + squared[n + 1] - at(squared, n - 30)
        integrated[n + 1] = window // 30
    end
    return {lowpass = low, bandpass = band, derivative = derivative, squared = squared, integrated = integrated}
end
return M
