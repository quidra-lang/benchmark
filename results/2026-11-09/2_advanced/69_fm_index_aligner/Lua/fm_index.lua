local symbols = require('suffix_array').symbols
local M = {}
M.__index = M
local function copy(values)
    local result = {}
    for key, value in pairs(values) do result[key] = value end
    return result
end
function M.new(text, suffixes, interval, sample_interval)
    local self = setmetatable({size = #text, interval = interval, C = {}, checkpoints = {}, samples = {}, sample_count = 0}, M)
    local bwt, frequencies, counts = {}, {}, {}
    for i = 1, #symbols do local c = symbols:sub(i, i); frequencies[c], counts[c] = 0, 0 end
    for i = 1, #text do local c = text:sub(i, i); frequencies[c] = frequencies[c] + 1 end
    local offset = 0
    for i = 1, #symbols do local c = symbols:sub(i, i); self.C[c] = offset; offset = offset + frequencies[c] end
    self.checkpoints[1] = copy(counts)
    for index, position in ipairs(suffixes) do
        local c = position > 0 and text:sub(position, position) or text:sub(-1)
        bwt[index] = c
        counts[c] = counts[c] + 1
        if index % interval == 0 then self.checkpoints[#self.checkpoints + 1] = copy(counts) end
        if sample_interval and position % sample_interval == 0 then self.samples[index - 1] = position; self.sample_count = self.sample_count + 1 end
    end
    self.bwt = table.concat(bwt)
    return self
end
function M:occurrence(symbol, position)
    local checkpoint = position // self.interval
    local start = checkpoint * self.interval
    local count = self.checkpoints[checkpoint + 1][symbol]
    for i = start + 1, position do if self.bwt:sub(i, i) == symbol then count = count + 1 end end
    return count
end
function M:lf(row)
    local symbol = self.bwt:sub(row + 1, row + 1)
    return self.C[symbol] + self:occurrence(symbol, row)
end
function M:extend(lower, upper, base)
    if base == 'N' then return 0, 0 end
    return self.C[base] + self:occurrence(base, lower), self.C[base] + self:occurrence(base, upper)
end
function M:locate(row)
    local steps = 0
    while self.samples[row] == nil do row = self:lf(row); steps = steps + 1 end
    return self.samples[row] + steps, steps
end
function M:inverse()
    local result, row = {}, 0
    result[self.size] = '$'
    for position = self.size - 1, 1, -1 do result[position] = self.bwt:sub(row + 1, row + 1); row = self:lf(row) end
    return table.concat(result)
end
function M:backward_search(sequence)
    local lower, upper = 0, self.size
    for i = #sequence, 1, -1 do
        lower, upper = self:extend(lower, upper, sequence:sub(i, i))
        if lower >= upper then break end
    end
    return lower, upper
end
return M
