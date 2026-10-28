local M = {}
function M.bits(value)
    local count = 0
    while value > 0 do
        count, value = count + 1, value // 2
    end
    return count
end
function M.fail(kind, position)
    error({decode_error = true, kind = kind, position = position}, 0)
end
local Writer = {}
Writer.__index = Writer
function M.writer()
    return setmetatable({data = {}, partial = 0, used = 0, bit_count = 0}, Writer)
end
function Writer:write(value, width)
    for shift = width - 1, 0, -1 do
        self.partial = self.partial * 2 + ((value >> shift) & 1)
        self.used = self.used + 1
        if self.used == 8 then
            self.data[#self.data + 1], self.partial, self.used = string.char(self.partial), 0, 0
        end
    end
    self.bit_count = self.bit_count + width
end
function Writer:finish()
    local result = table.concat(self.data)
    if self.used > 0 then
        result = result .. string.char(self.partial << (8 - self.used))
    end
    return result
end
local Reader = {}
Reader.__index = Reader
function M.reader(payload, zero_fill)
    return setmetatable({payload = payload, position = 0, limit = 8 * #payload, zero_fill = zero_fill}, Reader)
end
function Reader:read(width, output_position)
    if not self.zero_fill and self.position + width > self.limit then
        M.fail("end_of_data", output_position or 0)
    end
    local value = 0
    for index = 1, width do
        value = value * 2
        if self.position < self.limit then
            local byte = self.payload:byte(self.position // 8 + 1)
            value = value + ((byte >> (7 - self.position % 8)) & 1)
        end
        self.position = self.position + 1
    end
    return value
end
function M.bytes(values)
    local result = {}
    for index, value in ipairs(values) do
        result[index] = string.char(value)
    end
    return table.concat(result)
end
return M
