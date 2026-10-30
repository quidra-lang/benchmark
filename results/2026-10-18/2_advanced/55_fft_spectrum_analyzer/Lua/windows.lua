local fft = require("fft")
local M = {order = {"rectangular", "hann", "hamming", "blackman", "flattop"}}
local coefficients = {rectangular = {1.0}, hann = {0.5, 0.5}, hamming = {0.54, 0.46},
    blackman = {0.42, 0.5, 0.08}, flattop = {0.21557895, 0.41663158, 0.277263158, 0.083578947, 0.006947368}}
function M.window(name, length)
    local result = {}
    for n = 0, length - 1 do
        local total = 0.0
        for j, weight in ipairs(coefficients[name]) do
            local sign = j % 2 == 1 and 1 or -1
            total = total + sign * weight * math.cos(2 * fft.pi * (j - 1) * n / length)
        end
        result[n + 1] = total
    end
    return result
end
function M.figures(values, fs)
    local s1, s2, scalloping = 0.0, 0.0, {0.0, 0.0}
    for i, value in ipairs(values) do
        s1, s2 = s1 + value, s2 + value * value
        scalloping = fft.add(scalloping, fft.scale(fft.rot(fft.pi * (i - 1) / #values), value))
    end
    local enbw = #values * s2 / (s1 * s1)
    return {s1 = s1, s2 = s2, coherent_gain = s1 / #values, enbw_bins = enbw,
        enbw_hz = enbw * fs / #values, scalloping_db = -20 * math.log(fft.abs(scalloping) / s1, 10)}
end
return M
