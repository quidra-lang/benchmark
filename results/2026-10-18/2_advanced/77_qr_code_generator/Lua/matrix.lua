local matrix = {DATA = 0, FUNCTION = 1, FORMAT = 2, VERSION = 3}
local function bits(value) local width = 0; while value > 0 do value = value >> 1; width = width + 1 end; return width end
local function remainder(value, divisor)
    while bits(value) >= bits(divisor) do value = value ~ (divisor << (bits(value) - bits(divisor))) end
    return value
end
function matrix.format_information(level, mask)
    local indicator = ({L = 1, M = 0, Q = 3, H = 2})[level]
    local shifted = (8 * indicator + mask) << 10
    return (shifted + remainder(shifted, 0x537)) ~ 0x5412
end
function matrix.version_information(version) local shifted = version << 12; return shifted + remainder(shifted, 0x1f25) end
function matrix.format_positions(size)
    local first, second = {}, {}
    for index = 0, 5 do first[#first + 1] = {8, index} end
    for _, position in ipairs({{8, 7}, {8, 8}, {7, 8}}) do first[#first + 1] = position end
    for index = 9, 14 do first[#first + 1] = {14 - index, 8} end
    for index = 0, 7 do second[#second + 1] = {size - 1 - index, 8} end
    for index = 8, 14 do second[#second + 1] = {8, size - 15 + index} end
    return {first, second}
end
function matrix.version_positions(size)
    local first, second = {}, {}
    for index = 0, 17 do first[#first + 1] = {size - 11 + index % 3, index // 3}; second[#second + 1] = {index // 3, size - 11 + index % 3} end
    return {first, second}
end
function matrix.write_value(symbol, positions, value)
    for index, p in ipairs(positions) do symbol[p[2] + 1][p[1] + 1] = (value >> (index - 1)) & 1 end
end
function matrix.read_value(symbol, positions)
    local value = 0; for index, p in ipairs(positions) do value = value | (symbol[p[2] + 1][p[1] + 1] << (index - 1)) end; return value
end
function matrix.function_matrix(version, alignments)
    local size, symbol, areas = 17 + 4 * version, {}, {}
    for y = 1, size do
        symbol[y], areas[y] = {}, {}
        for x = 1, size do symbol[y][x], areas[y][x] = 0, matrix.DATA end
    end
    for _, center in ipairs({{3, 3}, {size - 4, 3}, {3, size - 4}}) do
        for dy = -4, 4 do for dx = -4, 4 do
            local x, y = center[1] + dx, center[2] + dy
            if x >= 0 and x < size and y >= 0 and y < size then
                local distance = math.max(math.abs(dx), math.abs(dy))
                symbol[y + 1][x + 1], areas[y + 1][x + 1] = (distance == 0 or distance == 1 or distance == 3) and 1 or 0, matrix.FUNCTION
            end
        end end
    end
    for index = 8, size - 9 do
        local value = index % 2 == 0 and 1 or 0
        symbol[index + 1][7], symbol[7][index + 1], areas[index + 1][7], areas[7][index + 1] = value, value, matrix.FUNCTION, matrix.FUNCTION
    end
    if #alignments > 0 then
        local first, last = alignments[1], alignments[#alignments]
        for _, cy in ipairs(alignments) do for _, cx in ipairs(alignments) do
            if not (cx == first and cy == first or cx == first and cy == last or cx == last and cy == first) then
                for dy = -2, 2 do for dx = -2, 2 do symbol[cy + dy + 1][cx + dx + 1], areas[cy + dy + 1][cx + dx + 1] = math.max(math.abs(dx), math.abs(dy)) ~= 1 and 1 or 0, matrix.FUNCTION end end
            end
        end end
    end
    symbol[size - 7][9], areas[size - 7][9] = 1, matrix.FUNCTION
    for _, positions in ipairs(matrix.format_positions(size)) do for _, p in ipairs(positions) do symbol[p[2] + 1][p[1] + 1], areas[p[2] + 1][p[1] + 1] = 0, matrix.FORMAT end end
    if version >= 7 then
        for _, positions in ipairs(matrix.version_positions(size)) do
            for _, p in ipairs(positions) do areas[p[2] + 1][p[1] + 1] = matrix.VERSION end
            matrix.write_value(symbol, positions, matrix.version_information(version))
        end
    end
    return symbol, areas
end
function matrix.reading_order(areas)
    local size, columns, positions = #areas, {}, {}
    for right = size - 1, 8, -2 do columns[#columns + 1] = right end
    for _, right in ipairs({5, 3, 1}) do columns[#columns + 1] = right end
    for pair, right in ipairs(columns) do
        for index = 0, size - 1 do
            local y = pair % 2 == 1 and size - 1 - index or index
            for x = right, right - 1, -1 do if areas[y + 1][x + 1] == matrix.DATA then positions[#positions + 1] = {x, y} end end
        end
    end
    return positions
end
return matrix
