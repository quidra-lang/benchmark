local M = {symbols = '$#ACGT', bases = 'ACGT', codes = {}}
for i = 1, #M.symbols do M.codes[M.symbols:sub(i, i)] = i - 1 end
function M.counting_sort(positions, keys, key_count)
    local counts = {}
    for key = 0, key_count - 1 do counts[key] = 0 end
    for _, position in ipairs(positions) do counts[keys[position]] = counts[keys[position]] + 1 end
    local offset = 1
    for key = 0, key_count - 1 do
        local count = counts[key]
        counts[key] = offset
        offset = offset + count
    end
    local result = {}
    for _, position in ipairs(positions) do
        local key = keys[position]
        result[counts[key]] = position
        counts[key] = counts[key] + 1
    end
    return result
end
function M.build(text)
    local size, positions, codes = #text, {}, {}
    for position = 0, size - 1 do
        positions[#positions + 1] = position
        codes[position] = M.codes[text:sub(position + 1, position + 1)]
    end
    local order = M.counting_sort(positions, codes, 6)
    local ranks, count, previous = {}, 0, nil
    for _, position in ipairs(order) do
        if codes[position] ~= previous then count = count + 1; previous = codes[position] end
        ranks[position] = count - 1
    end
    local classes, width = {count}, 1
    while count < size do
        local second = {}
        for position = 0, size - 1 do second[position] = position + width < size and ranks[position + width] + 1 or 0 end
        order = M.counting_sort(positions, second, count + 1)
        order = M.counting_sort(order, ranks, count)
        local updated, previous_first, previous_second = {}, nil, nil
        count = 0
        for _, position in ipairs(order) do
            if ranks[position] ~= previous_first or second[position] ~= previous_second then
                count = count + 1
                previous_first, previous_second = ranks[position], second[position]
            end
            updated[position] = count - 1
        end
        ranks = updated
        classes[#classes + 1] = count
        width = width * 2
    end
    return order, classes
end
function M.direct_sort(text)
    local result = {}
    for position = 0, #text - 1 do result[#result + 1] = position end
    table.sort(result, function(a, b) return text:sub(a + 1) < text:sub(b + 1) end)
    return result
end
function M.adjacent_check(text, suffixes)
    local ordered, total, longest, longest_row = 0, 0, -1, 2
    for row = 2, #suffixes do
        local first, second, common = suffixes[row - 1], suffixes[row], 0
        while text:sub(first + common + 1, first + common + 1) == text:sub(second + common + 1, second + common + 1) do common = common + 1 end
        if M.codes[text:sub(first + common + 1, first + common + 1)] < M.codes[text:sub(second + common + 1, second + common + 1)] then ordered = ordered + 1 end
        total = total + common
        if common > longest then longest, longest_row = common, row end
    end
    return ordered, total, longest, longest_row
end
return M
