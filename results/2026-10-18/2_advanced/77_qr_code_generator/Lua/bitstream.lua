local bitstream = {}
bitstream.alphanumeric = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:'
bitstream.alphanumeric_values = {}
for index = 1, #bitstream.alphanumeric do bitstream.alphanumeric_values[bitstream.alphanumeric:sub(index, index)] = index - 1 end
function bitstream.binary(value, width)
    local bits = {}
    for shift = width - 1, 0, -1 do bits[#bits + 1] = tostring((value >> shift) & 1) end
    return table.concat(bits)
end
local Writer = {}
Writer.__index = Writer
function Writer.new() return setmetatable({parts = {}, length = 0}, Writer) end
function Writer:write(value, width) self.parts[#self.parts + 1] = bitstream.binary(value, width); self.length = self.length + width end
function Writer:value() return table.concat(self.parts) end
local Reader = {}
Reader.__index = Reader
function Reader.new(bits) return setmetatable({bits = bits, position = 1}, Reader) end
function Reader:remaining() return #self.bits - self.position + 1 end
function Reader:read(width)
    local value = tonumber(self.bits:sub(self.position, self.position + width - 1), 2)
    self.position = self.position + width; return value
end
function bitstream.from_codewords(words)
    local pieces = {}; for _, word in ipairs(words) do pieces[#pieces + 1] = bitstream.binary(word, 8) end
    return table.concat(pieces)
end
function bitstream.to_codewords(bits)
    local words = {}; for index = 1, #bits, 8 do words[#words + 1] = tonumber(bits:sub(index, index + 7), 2) end
    return words
end
function bitstream.hexadecimal(words)
    local pieces = {}; for _, word in ipairs(words) do pieces[#pieces + 1] = string.format('%02x', word) end
    return table.concat(pieces)
end
bitstream.Writer, bitstream.Reader = Writer, Reader
return bitstream
