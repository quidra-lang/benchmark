local bits = require('bitstream')
local encoding = {methods = {[0] = 'PLAIN', 'DICTIONARY', 'RLE', 'DELTA_BINARY_PACKED', 'DELTA_LENGTH_BYTE_ARRAY'},
    candidates = {INT = {0, 1, 3}, DATE = {0, 1, 3}, STRING = {0, 1, 4}, BOOL = {0, 2}}}
local append = bits.append
local function width(value) local count = 0; while value > 0 do value = value >> 1; count = count + 1 end; return count end
function encoding.delta_encode(values)
    local output = {}; append(output, bits.uleb(128)); append(output, bits.uleb(4)); append(output, bits.uleb(#values)); append(output, bits.zigzag(values[1] or 0))
    local deltas = {}; for index = 2, #values do deltas[#deltas + 1] = values[index] - values[index - 1] end
    for start = 1, #deltas, 128 do
        local finish, minimum = math.min(start + 127, #deltas), deltas[start]
        for index = start, finish do minimum = math.min(minimum, deltas[index]) end
        append(output, bits.zigzag(minimum))
        local miniblocks, widths = {}, {}
        for miniblock = 0, 3 do
            local values, maximum = {}, 0
            for index = start + 32 * miniblock, math.min(start + 32 * miniblock + 31, finish) do
                local difference = deltas[index] - minimum; values[#values + 1], maximum = difference, math.max(maximum, difference)
            end
            miniblocks[#miniblocks + 1], widths[#widths + 1] = values, width(maximum)
        end
        append(output, widths)
        for index, miniblock in ipairs(miniblocks) do
            if #miniblock > 0 then for position = #miniblock + 1, 32 do miniblock[position] = 0 end; append(output, bits.pack(miniblock, widths[index])) end
        end
    end
    return output
end
function encoding.delta_decode(reader)
    local block_size = reader:uleb()
    local miniblock_count = reader:uleb()
    local count = reader:uleb()
    local first = reader:zigzag()
    local values = {}; if count > 0 then values[1] = first end
    while #values < count do
        local minimum, widths = reader:zigzag(), {}
        for index = 1, miniblock_count do widths[index] = reader:byte() end
        local size = block_size // miniblock_count
        for _, w in ipairs(widths) do
            if #values == count then break end
            local differences = bits.unpack(reader, w, size)
            for index = 1, math.min(size, count - #values) do values[#values + 1] = values[#values] + minimum + differences[index] end
        end
    end
    return values
end
function encoding.encode_values(kind, method, values, dictionary)
    local output = {}
    if method == 0 then
        if kind == 'INT' or kind == 'DATE' then for _, value in ipairs(values) do append(output, bits.integer(value)) end
        elseif kind == 'STRING' then for _, value in ipairs(values) do append(output, bits.integer(#value)); append(output, bits.bytes(value)) end
        else
            local integers = {}; for index, value in ipairs(values) do integers[index] = value and 1 or 0 end
            for index = #integers + 1, (#integers + 7) // 8 * 8 do integers[index] = 0 end
            output = bits.pack(integers, 1)
        end
    elseif method == 1 then
        local ranks, indices = {}, {}
        for index, value in ipairs(dictionary) do ranks[value] = index - 1 end
        for index, value in ipairs(values) do indices[index] = ranks[value] end
        local w = width(#dictionary - 1); output[1] = w; append(output, bits.hybrid_encode(indices, w))
    elseif method == 2 then
        local integers = {}; for index, value in ipairs(values) do integers[index] = value and 1 or 0 end
        local data = bits.hybrid_encode(integers, 1); output = bits.integer(#data); append(output, data)
    elseif method == 3 then output = encoding.delta_encode(values)
    else
        local lengths = {}; for index, value in ipairs(values) do lengths[index] = #value end
        output = encoding.delta_encode(lengths); for _, value in ipairs(values) do append(output, bits.bytes(value)) end
    end
    return output
end
function encoding.decode_values(reader, kind, method, count, dictionary)
    local values = {}
    if method == 0 then
        if kind == 'INT' or kind == 'DATE' then for index = 1, count do values[index] = reader:integer(true) end
        elseif kind == 'STRING' then for index = 1, count do local length = reader:integer(); values[index] = bits.text(reader:read(length)) end
        else local integers = bits.unpack(reader, 1, (count + 7) // 8 * 8); for index = 1, count do values[index] = integers[index] ~= 0 end end
    elseif method == 1 then
        local w = reader:byte(); local indices = bits.hybrid_decode(reader, w, count)
        for index, rank in ipairs(indices) do values[index] = dictionary[rank + 1] end
    elseif method == 2 then
        local size = reader:integer(); local integers = bits.hybrid_decode(bits.Reader.new(reader:read(size)), 1, count)
        for index, value in ipairs(integers) do values[index] = value ~= 0 end
    elseif method == 3 then values = encoding.delta_decode(reader)
    else
        local lengths = encoding.delta_decode(reader)
        for index, length in ipairs(lengths) do values[index] = bits.text(reader:read(length)) end
    end
    return values
end
function encoding.encode_statistics(kind, bounds)
    if not bounds then return {0} end
    local output = {1}
    for _, value in ipairs(bounds) do
        if kind == 'INT' or kind == 'DATE' then append(output, bits.zigzag(value))
        elseif kind == 'STRING' then append(output, bits.uleb(#value)); append(output, bits.bytes(value))
        else output[#output + 1] = value and 1 or 0 end
    end
    return output
end
function encoding.decode_statistics(reader, kind)
    if reader:byte() == 0 then return nil end
    local values = {}
    for index = 1, 2 do
        if kind == 'INT' or kind == 'DATE' then values[index] = reader:zigzag()
        elseif kind == 'STRING' then local length = reader:uleb(); values[index] = bits.text(reader:read(length))
        else values[index] = reader:byte() ~= 0 end
    end
    return values
end
return encoding
