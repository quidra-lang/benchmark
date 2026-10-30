local fft = require("fft")
local windows = require("windows")
local M = {}
function M.median(values)
    local ordered = {table.unpack(values)}
    table.sort(ordered)
    local middle = #ordered // 2
    if #ordered % 2 == 1 then return ordered[middle + 1] end
    return (ordered[middle] + ordered[middle + 1]) / 2
end
function M.local_maximum(values, index)
    return index > 1 and index < #values and values[index] > values[index - 1] and values[index] > values[index + 1]
end
function M.interpolate(values, index, logarithmic)
    if logarithmic == nil then logarithmic = true end
    if not M.local_maximum(values, index) then return index - 1.0, values[index] end
    local a, b, c = values[index - 1], values[index], values[index + 1]
    if logarithmic then a, b, c = math.log(a), math.log(b), math.log(c) end
    local delta = (a - c) / (2 * (a - 2 * b + c))
    local fitted = b - (a - c) * delta / 4
    return index - 1 + delta, logarithmic and math.exp(fitted) or fitted
end
function M.amplitude(signal, name, length)
    local weights, weighted, s1 = windows.window(name, length), {}, 0.0
    for i, weight in ipairs(weights) do weighted[i], s1 = signal[i] * weight, s1 + weight end
    local transformed, amplitudes = fft.dft(fft.complex(weighted)), {}
    for k = 0, length // 2 do
        local factor = (k == 0 or 2 * k == length) and 1 or 2
        amplitudes[k + 1] = factor * fft.abs(transformed[k + 1]) / s1
    end
    return weighted, transformed, amplitudes
end
local function packed_and_error(samples)
    local packed, reference, error = fft.packed_real(samples), fft.radix2(fft.complex(samples)), 0.0
    for k, value in ipairs(packed) do error = math.max(error, fft.abs(fft.sub(value, reference[k]))) end
    return packed, error
end
function M.welch(x, y, fs, length, name)
    local weights, energy = windows.window(name, length), 0.0
    for _, value in ipairs(weights) do energy = energy + value * value end
    local segments = (#x - length) // (length // 2) + 1
    local pxx, pyy, pxy, packing_error = {}, {}, fft.zeros(length // 2 + 1), 0.0
    for k = 1, #pxy do pxx[k], pyy[k] = 0.0, 0.0 end
    for block = 0, segments - 1 do
        local a, b = {}, {}
        for i, weight in ipairs(weights) do a[i], b[i] = x[block * (length // 2) + i] * weight, y[block * (length // 2) + i] * weight end
        local af, ae = packed_and_error(a)
        local bf, be = packed_and_error(b)
        packing_error = math.max(packing_error, ae, be)
        for k = 1, #pxy do
            pxx[k], pyy[k] = pxx[k] + fft.abs(af[k]) ^ 2, pyy[k] + fft.abs(bf[k]) ^ 2
            pxy[k] = fft.add(pxy[k], fft.mul(fft.conj(af[k]), bf[k]))
        end
    end
    local psd, coherence, transfer = {}, {}, {}
    for k = 0, length // 2 do
        local factor = (k == 0 or k == length // 2) and 1 or 2
        psd[k + 1] = factor * pxx[k + 1] / (segments * fs * energy)
        coherence[k + 1] = fft.abs(pxy[k + 1]) ^ 2 / (pxx[k + 1] * pyy[k + 1])
        transfer[k + 1] = fft.divide(pxy[k + 1], pxx[k + 1])
    end
    return {segments = segments, psd = psd, coherence = coherence, transfer = transfer, packing_error = packing_error}
end
function M.spectrogram(signal, length, hop, name)
    local weights, grid, maximum_error = windows.window(name, length), {}, 0.0
    for frame = 0, (#signal - length) // hop do
        local samples = {}
        for i, weight in ipairs(weights) do samples[i] = signal[frame * hop + i] * weight end
        local transformed, error = packed_and_error(samples)
        local row = {}
        for k, value in ipairs(transformed) do row[k] = fft.abs(value) end
        grid[#grid + 1], maximum_error = row, math.max(maximum_error, error)
    end
    return grid, maximum_error
end
return M
