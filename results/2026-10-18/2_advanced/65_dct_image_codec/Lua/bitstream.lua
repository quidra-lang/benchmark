local B = {}
function B.fail(kind) error({ category = "decode", kind = kind }, 0) end
local W = {}
W.__index = W
function B.writer() return setmetatable({ data = {}, buffer = 0, pending = 0, padding_bits = 0, stuffed_bytes = 0 }, W) end
function W:write(value, width)
    for shift = width - 1, 0, -1 do
        self.buffer, self.pending = 2 * self.buffer + ((value >> shift) & 1), self.pending + 1
        if self.pending == 8 then
            self.data[#self.data + 1] = self.buffer
            if self.buffer == 255 then self.data[#self.data + 1], self.stuffed_bytes = 0, self.stuffed_bytes + 1 end
            self.buffer, self.pending = 0, 0
        end
    end
end
function W:pad()
    if self.pending > 0 then
        local width = 8 - self.pending
        self.padding_bits = self.padding_bits + width
        self:write((1 << width) - 1, width)
    end
end
function W:restart(number)
    self:pad()
    self.data[#self.data + 1] = 255
    self.data[#self.data + 1] = 208 + number % 8
end
local R = {}
R.__index = R
function B.reader(data, position) return setmetatable({ data = data, position = position, buffer = 0, remaining = 0 }, R) end
function R:bit()
    if self.remaining == 0 then
        local value = self.data[self.position + 1]
        if value == 255 then
            if self.data[self.position + 2] ~= 0 then B.fail("marker") end
            self.position = self.position + 2
        else self.position = self.position + 1 end
        self.buffer, self.remaining = value, 8
    end
    self.remaining = self.remaining - 1
    return (self.buffer >> self.remaining) & 1
end
function R:read(width)
    local value = 0
    for _ = 1, width do value = 2 * value + self:bit() end
    return value
end
function R:discard() self.buffer, self.remaining = 0, 0 end
function B.find_resync(data, position)
    for offset = position, #data - 2 do
        local marker = data[offset + 2]
        if data[offset + 1] == 255 and (marker >= 208 and marker <= 215 or marker == 217) then return offset end
    end
end
return B
