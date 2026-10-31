local masking = {}
function masking.condition(mask, x, y)
    if mask == 0 then return (y + x) % 2 == 0 elseif mask == 1 then return y % 2 == 0
    elseif mask == 2 then return x % 3 == 0 elseif mask == 3 then return (y + x) % 3 == 0
    elseif mask == 4 then return (y // 2 + x // 3) % 2 == 0
    elseif mask == 5 then return (y * x) % 2 + (y * x) % 3 == 0
    elseif mask == 6 then return ((y * x) % 2 + (y * x) % 3) % 2 == 0
    else return ((y + x) % 2 + (y * x) % 3) % 2 == 0 end
end
function masking.apply(symbol, positions, mask)
    local result = {}; for index, row in ipairs(symbol) do result[index] = {table.unpack(row)} end
    for _, p in ipairs(positions) do if masking.condition(mask, p[1], p[2]) then result[p[2] + 1][p[1] + 1] = result[p[2] + 1][p[1] + 1] ~ 1 end end
    return result
end
function masking.penalties(symbol)
    local size, lines = #symbol, {}
    for _, row in ipairs(symbol) do lines[#lines + 1] = row end
    for x = 1, size do local column = {}; for y = 1, size do column[#column + 1] = symbol[y][x] end; lines[#lines + 1] = column end
    local n1, n2, n3, dark = 0, 0, 0, 0
    for _, line in ipairs(lines) do
        local run = 1
        for index = 2, size do
            if line[index] == line[index - 1] then run = run + 1
            else if run >= 5 then n1 = n1 + run - 2 end; run = 1 end
        end
        if run >= 5 then n1 = n1 + run - 2 end
        for index = 1, size - 10 do
            local pattern = table.concat(line, '', index, index + 10)
            if pattern == '10111010000' or pattern == '00001011101' then n3 = n3 + 40 end
        end
    end
    for y = 1, size do for x = 1, size do
        local value = symbol[y][x]; dark = dark + value
        if x < size and y < size and value == symbol[y][x + 1] and value == symbol[y + 1][x] and value == symbol[y + 1][x + 1] then n2 = n2 + 3 end
    end end
    return {n1, n2, n3, 10 * (math.abs(20 * dark - 10 * size * size) // (size * size))}
end
return masking
