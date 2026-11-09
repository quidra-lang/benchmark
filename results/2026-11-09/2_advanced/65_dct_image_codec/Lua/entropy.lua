local E = { table_keys = { 0, 4, 1, 5 }, table_names = { "dc_luma", "ac_luma", "dc_chroma", "ac_chroma" } }
function E.key(class, id) return 4 * class + id end
function E.category(value)
    value = math.abs(value)
    local size = 0
    while value > 0 do value, size = value // 2, size + 1 end
    return size
end
function E.extra_bits(value)
    local size = E.category(value)
    return value >= 0 and value or value + (1 << size) - 1, size
end
function E.amplitude(bits, size)
    if size == 0 then return 0 end
    return bits >= (1 << (size - 1)) and bits or bits - (1 << size) + 1
end
function E.table(counts, symbols)
    local result, code, offset = { counts = counts, symbols = symbols, codes = {}, decode = {} }, 0, 1
    for length = 1, 16 do
        result.decode[length] = {}
        for _ = 1, counts[length] do
            local symbol = symbols[offset]
            result.codes[symbol], result.decode[length][code] = { length, code }, symbol
            code, offset = code + 1, offset + 1
        end
        code = code * 2
    end
    return result
end
function E.optimized(original)
    local frequencies, sizes, others = {}, {}, {}
    for symbol = 0, 256 do frequencies[symbol], sizes[symbol], others[symbol] = symbol == 256 and 1 or original[symbol] or 0, 0, -1 end
    while true do
        local available = {}
        for symbol = 0, 256 do if frequencies[symbol] > 0 then available[#available + 1] = symbol end end
        if #available < 2 then break end
        table.sort(available, function(a, b) return frequencies[a] < frequencies[b] or frequencies[a] == frequencies[b] and a > b end)
        local first, second = available[1], available[2]
        frequencies[first], frequencies[second] = frequencies[first] + frequencies[second], 0
        sizes[first] = sizes[first] + 1
        while others[first] ~= -1 do first = others[first]; sizes[first] = sizes[first] + 1 end
        others[first] = second
        sizes[second] = sizes[second] + 1
        while others[second] ~= -1 do second = others[second]; sizes[second] = sizes[second] + 1 end
    end
    local counts, maximum = {}, 0
    for i = 0, 256 do counts[i] = 0 end
    for symbol = 0, 256 do local size = sizes[symbol]; if size > 0 then counts[size] = counts[size] + 1; maximum = math.max(maximum, size) end end
    for length = maximum, 17, -1 do
        while counts[length] > 0 do
            local shorter = length - 2
            while counts[shorter] == 0 do shorter = shorter - 1 end
            counts[length], counts[length - 1] = counts[length] - 2, counts[length - 1] + 1
            counts[shorter + 1], counts[shorter] = counts[shorter + 1] + 2, counts[shorter] - 1
        end
    end
    local longest = 16
    while counts[longest] == 0 do longest = longest - 1 end
    counts[longest] = counts[longest] - 1
    local symbols, bits = {}, {}
    for symbol = 0, 255 do if sizes[symbol] > 0 then symbols[#symbols + 1] = symbol end end
    table.sort(symbols, function(a, b) return sizes[a] < sizes[b] or sizes[a] == sizes[b] and a < b end)
    for i = 1, 16 do bits[i] = counts[i] end
    return E.table(bits, symbols)
end
return E
