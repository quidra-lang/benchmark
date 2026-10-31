local M = {pi = 3.141592653589793}
function M.add(a, b) return {a[1] + b[1], a[2] + b[2]} end
function M.sub(a, b) return {a[1] - b[1], a[2] - b[2]} end
function M.mul(a, b) return {a[1] * b[1] - a[2] * b[2], a[1] * b[2] + a[2] * b[1]} end
function M.scale(a, value) return {a[1] * value, a[2] * value} end
function M.divide(a, value) return {a[1] / value, a[2] / value} end
function M.conj(a) return {a[1], -a[2]} end
function M.abs(a) return math.sqrt(a[1] * a[1] + a[2] * a[2]) end
function M.rot(angle) return {math.cos(angle), -math.sin(angle)} end
function M.pow2(value)
    local result = 1
    while result < value do result = result * 2 end
    return result
end
function M.zeros(count)
    local result = {}
    for i = 1, count do result[i] = {0.0, 0.0} end
    return result
end
function M.complex(values, length)
    local result = M.zeros(length or #values)
    for i, value in ipairs(values) do result[i] = {value, 0.0} end
    return result
end
function M.radix2(data, inverse)
    local count, values, bits = #data, {}, 0
    for i, value in ipairs(data) do values[i] = {value[1], value[2]} end
    local power = count
    while power > 1 do bits, power = bits + 1, power // 2 end
    for index = 1, count - 1 do
        local reverse, rest = 0, index
        for _ = 1, bits do reverse, rest = reverse * 2 + rest % 2, rest // 2 end
        if index < reverse then values[index + 1], values[reverse + 1] = values[reverse + 1], values[index + 1] end
    end
    local twiddle = {}
    for k = 0, count // 2 - 1 do
        local value = M.rot(2 * M.pi * k / count)
        twiddle[k + 1] = inverse and M.conj(value) or value
    end
    local size = 2
    while size <= count do
        local stride, half = count // size, size // 2
        for start = 0, count - 1, size do
            for j = 0, half - 1 do
                local t, u = M.mul(twiddle[j * stride + 1], values[start + j + half + 1]), values[start + j + 1]
                values[start + j + 1], values[start + j + half + 1] = M.add(u, t), M.sub(u, t)
            end
        end
        size = size * 2
    end
    if inverse then for i, value in ipairs(values) do values[i] = M.divide(value, count) end end
    return values
end
function M.bluestein(values)
    local count = #values
    local size = M.pow2(2 * count - 1)
    local chirp, a, b = {}, M.zeros(size), M.zeros(size)
    for k = 0, count - 1 do
        chirp[k + 1] = M.rot(M.pi * ((k * k) % (2 * count)) / count)
        a[k + 1] = M.mul(values[k + 1], chirp[k + 1])
        b[k + 1] = M.conj(chirp[k + 1])
        if k > 0 then b[size - k + 1] = b[k + 1] end
    end
    local af, bf = M.radix2(a), M.radix2(b)
    for i = 1, size do af[i] = M.mul(af[i], bf[i]) end
    local convolution = M.radix2(af, true)
    local result = {}
    for k = 1, count do result[k] = M.mul(chirp[k], convolution[k]) end
    return result
end
function M.dft(values)
    if M.pow2(#values) == #values then return M.radix2(values) end
    return M.bluestein(values)
end
function M.idft(values)
    if M.pow2(#values) == #values then return M.radix2(values, true) end
    local conjugates, result = {}, {}
    for i, value in ipairs(values) do conjugates[i] = M.conj(value) end
    for i, value in ipairs(M.bluestein(conjugates)) do result[i] = M.divide(M.conj(value), #values) end
    return result
end
function M.packed_real(values)
    local count, z = #values, {}
    local half = count // 2
    for j = 0, half - 1 do z[j + 1] = {values[2 * j + 1], values[2 * j + 2]} end
    z = M.radix2(z)
    local result = {}
    for k = 0, half do
        local a, b = z[k % half + 1], M.conj(z[(half - k) % half + 1])
        local even = M.scale(M.add(a, b), 0.5)
        local difference = M.sub(a, b)
        local odd = {difference[2] / 2, -difference[1] / 2}
        result[k + 1] = M.add(even, M.mul(M.rot(2 * M.pi * k / count), odd))
    end
    return result
end
function M.convolution(a, b)
    local count = #a + #b - 1
    local size = M.pow2(count)
    local af, bf = M.radix2(M.complex(a, size)), M.radix2(M.complex(b, size))
    for k = 1, size do af[k] = M.mul(af[k], bf[k]) end
    local inverse, result = M.radix2(af, true), {}
    for i = 1, count do result[i] = inverse[i][1] end
    return result
end
function M.chirp_z(values, fs, low, high, points)
    local count, step = #values, (high - low) / (points - 1)
    local size = M.pow2(count + points - 1)
    local a, b = M.zeros(size), M.zeros(size)
    for n = 0, count - 1 do
        a[n + 1] = M.mul(M.scale(M.rot(2 * M.pi * low * n / fs), values[n + 1]), M.rot(M.pi * step * n * n / fs))
    end
    for offset = -(count - 1), points - 1 do b[offset % size + 1] = M.conj(M.rot(M.pi * step * offset * offset / fs)) end
    local af, bf = M.radix2(a), M.radix2(b)
    for k = 1, size do af[k] = M.mul(af[k], bf[k]) end
    local g, result = M.radix2(af, true), {}
    for j = 0, points - 1 do result[j + 1] = M.mul(M.rot(M.pi * step * j * j / fs), g[j + 1]) end
    return result
end
return M
