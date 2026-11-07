local bitstream = {}
function bitstream.append(target, source) for _, value in ipairs(source) do target[#target + 1] = value end end
function bitstream.bytes(text) local values = {}; for index = 1, #text do values[index] = text:byte(index) end; return values end
function bitstream.text(values) local pieces = {}; for index, value in ipairs(values) do pieces[index] = string.char(value) end; return table.concat(pieces) end
local Reader = {}
Reader.__index = Reader
function Reader.new(data, position) return setmetatable({data = data, position = position or 0}, Reader) end
function Reader:read(count)
    local result = {}; for index = self.position + 1, self.position + count do result[#result + 1] = self.data[index] end
    self.position = self.position + count; return result
end
function Reader:byte() self.position = self.position + 1; return self.data[self.position] end
function Reader:uleb()
    local value, shift = 0, 0
    while true do local byte = self:byte(); value = value | ((byte & 127) << shift); if byte < 128 then return value end; shift = shift + 7 end
end
function Reader:zigzag() local value = self:uleb(); if value % 2 == 0 then return value // 2 end; return -((value + 1) // 2) end
function Reader:integer(signed)
    local value = 0; for shift = 0, 24, 8 do value = value | (self:byte() << shift) end
    if signed and value >= (1 << 31) then value = value - (1 << 32) end
    return value
end
function bitstream.uleb(value)
    local result = {}
    while value >= 128 do result[#result + 1] = value % 128 + 128; value = value // 128 end
    result[#result + 1] = value; return result
end
function bitstream.zigzag(value) return bitstream.uleb(value >= 0 and 2 * value or -2 * value - 1) end
function bitstream.integer(value, count)
    if value < 0 then value = value + (1 << 32) end
    local result = {}; for index = 0, (count or 4) - 1 do result[#result + 1] = (value >> (8 * index)) & 255 end
    return result
end
function bitstream.pack(values, width)
    local result, buffer, occupied = {}, 0, 0
    for _, value in ipairs(values) do
        buffer, occupied = buffer | (value << occupied), occupied + width
        while occupied >= 8 do result[#result + 1] = buffer & 255; buffer, occupied = buffer >> 8, occupied - 8 end
    end
    return result
end
function bitstream.unpack(reader, width, count)
    local values, buffer, occupied, mask = {}, 0, 0, (1 << width) - 1
    for _ = 1, count do
        while occupied < width do buffer, occupied = buffer | (reader:byte() << occupied), occupied + 8 end
        values[#values + 1], buffer, occupied = buffer & mask, buffer >> width, occupied - width
    end
    return values
end
function bitstream.adler32(data)
    local first, second = 1, 0
    for _, byte in ipairs(data) do first = (first + byte) % 65521; second = (second + first) % 65521 end
    return second * 65536 + first
end
function bitstream.hybrid_encode(values, width)
    local runs, result, index = {}, {}, 1
    for position = #values, 1, -1 do runs[position] = 1; if position < #values and values[position] == values[position + 1] then runs[position] = runs[position] + runs[position + 1] end end
    while index <= #values do
        if runs[index] >= 8 then
            bitstream.append(result, bitstream.uleb(2 * runs[index])); bitstream.append(result, bitstream.integer(values[index], (width + 7) // 8)); index = index + runs[index]
        else
            local finish, groups = index, 0
            repeat finish, groups = finish + 8, groups + 1 until finish > #values or groups == 63 or runs[finish] >= 8
            bitstream.append(result, bitstream.uleb(2 * groups + 1))
            local block = {}; for position = index, finish - 1 do block[#block + 1] = values[position] or 0 end
            bitstream.append(result, bitstream.pack(block, width)); index = finish
        end
    end
    return result
end
function bitstream.hybrid_decode(reader, width, count)
    local result = {}
    while #result < count do
        local header = reader:uleb()
        if header % 2 == 0 then
            local value = 0; for index, byte in ipairs(reader:read((width + 7) // 8)) do value = value | (byte << (8 * (index - 1))) end
            for _ = 1, header // 2 do result[#result + 1] = value end
        else bitstream.append(result, bitstream.unpack(reader, width, (header - 1) // 2 * 8)) end
    end
    local values = {}; for index = 1, count do values[index] = result[index] end; return values
end
bitstream.Reader = Reader
return bitstream
