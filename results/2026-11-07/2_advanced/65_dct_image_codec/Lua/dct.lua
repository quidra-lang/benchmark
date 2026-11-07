local Color = require("color")
local D = { zigzag_order = {} }
for u = 0, 7 do for v = 0, 7 do D.zigzag_order[#D.zigzag_order + 1] = { u + 1, v + 1 } end end
table.sort(D.zigzag_order, function(a, b)
    local sa, sb = a[1] + a[2], b[1] + b[2]
    if sa ~= sb then return sa < sb end
    return sa % 2 == 1 and a[1] < b[1] or sa % 2 == 0 and a[1] > b[1]
end)
local function zeros() local result = {}; for i = 1, 8 do result[i] = {}; for j = 1, 8 do result[i][j] = 0 end end; return result end
local function rounded(value, shift) return (value + (1 << (shift - 1))) // (1 << shift) end
function D.forward(block, transform)
    local intermediate, result = zeros(), zeros()
    for u = 1, 8 do
        for x = 1, 8 do
            local total = 0
            for y = 1, 8 do total = total + transform[u][y] * (block[y][x] - 128) end
            intermediate[u][x] = rounded(total, 11)
        end
    end
    for u = 1, 8 do
        for v = 1, 8 do
            local total = 0
            for x = 1, 8 do total = total + intermediate[u][x] * transform[v][x] end
            result[u][v] = rounded(total, 15)
        end
    end
    return result
end
function D.inverse(coefficients, transform)
    local intermediate, result = zeros(), zeros()
    for y = 1, 8 do
        for v = 1, 8 do
            local total = 0
            for u = 1, 8 do total = total + transform[u][y] * coefficients[u][v] end
            intermediate[y][v] = rounded(total, 11)
        end
    end
    for y = 1, 8 do
        for x = 1, 8 do
            local total = 0
            for v = 1, 8 do total = total + intermediate[y][v] * transform[v][x] end
            result[y][x] = Color.clamp(rounded(total, 15) + 128)
        end
    end
    return result
end
function D.quantization(basic, quality)
    local scale = quality < 50 and 5000 // quality or 200 - 2 * quality
    local result = {}
    for identifier, matrix in ipairs(basic) do
        local table_values = zeros()
        for u, row in ipairs(matrix) do for v, value in ipairs(row) do table_values[u][v] = math.min(math.max((value * scale + 50) // 100, 1), 255) end end
        result[identifier - 1] = table_values
    end
    return result
end
function D.quantize(values, divisors)
    local result = zeros()
    for u, row in ipairs(values) do
        for v, value in ipairs(row) do local divisor = divisors[u][v]; local magnitude = (math.abs(value) + divisor // 2) // divisor; result[u][v] = value >= 0 and magnitude or -magnitude end
    end
    return result
end
function D.zigzag(values)
    local result = {}
    for i, position in ipairs(D.zigzag_order) do result[i] = values[position[1]][position[2]] end
    return result
end
function D.unzigzag(sequence)
    local result = zeros()
    for i, position in ipairs(D.zigzag_order) do result[position[1]][position[2]] = sequence[i] end
    return result
end
function D.dequantize(sequence, divisors, keep)
    local result = zeros()
    for i, position in ipairs(D.zigzag_order) do if i <= (keep or 64) then result[position[1]][position[2]] = sequence[i] * divisors[position[1]][position[2]] end end
    return result
end
return D
