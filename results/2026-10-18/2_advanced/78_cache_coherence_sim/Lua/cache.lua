local Cache = {}
Cache.__index = Cache
function Cache.new(sets, ways, replacement)
    local self = setmetatable({sets = sets, ways = ways, replacement = replacement, entries = {}, touched = {}, bits = {}, fills = {}, evictions = {}, clock = 0}, Cache)
    for row = 1, sets do
        self.entries[row], self.touched[row], self.bits[row], self.fills[row], self.evictions[row] = {}, {}, {}, 0, 0
        for way = 1, ways do self.touched[row][way] = 0 end
        for node = 1, ways - 1 do self.bits[row][node] = 0 end
    end
    return self
end
function Cache:locate(block)
    local row = block % self.sets + 1
    for way = 1, self.ways do local item = self.entries[row][way]; if item and item.block == block then return row, way end end
end
function Cache:state(block)
    local row, way = self:locate(block)
    return row and self.entries[row][way].state or 'I'
end
function Cache:change(block, state) local row, way = self:locate(block); if row then self.entries[row][way].state = state end end
function Cache:touch_way(row, way, fill)
    if self.replacement == 'LRU' or self.replacement == 'FIFO' and fill then self.clock = self.clock + 1; self.touched[row][way] = self.clock
    elseif self.replacement == 'PLRU' then
        local low, high, node = 0, self.ways, 1
        while high - low > 1 do
            local middle = (low + high) // 2
            if way - 1 < middle then self.bits[row][node], high, node = 1, middle, node * 2
            else self.bits[row][node], low, node = 0, middle, node * 2 + 1 end
        end
    end
end
function Cache:touch(block) local row, way = self:locate(block); if row then self:touch_way(row, way, false) end end
function Cache:victim(row)
    if self.replacement == 'PLRU' then
        local low, high, node = 0, self.ways, 1
        while high - low > 1 do
            local middle = (low + high) // 2
            if self.bits[row][node] == 0 then high, node = middle, node * 2 else low, node = middle, node * 2 + 1 end
        end
        return low + 1
    end
    local chosen = 1
    for way = 2, self.ways do if self.touched[row][way] < self.touched[row][chosen] then chosen = way end end
    return chosen
end
function Cache:fill(block, state)
    local row, chosen = block % self.sets + 1, nil
    for way = 1, self.ways do if self.entries[row][way] == nil then chosen = way; break end end
    if not chosen then chosen = self:victim(row) end
    local old = self.entries[row][chosen]
    if old then self.evictions[row] = self.evictions[row] + 1 end
    self.entries[row][chosen] = {block = block, state = state}; self.fills[row] = self.fills[row] + 1
    self:touch_way(row, chosen, true); return old
end
function Cache:remove(block)
    local row, way = self:locate(block)
    if row then local old = self.entries[row][way]; self.entries[row][way] = nil; return old end
end
function Cache:order(row)
    if self.replacement == 'PLRU' then return self.ways == 1 and '-' or table.concat(self.bits[row]) end
    local active = {}
    for way = 1, self.ways do if self.entries[row][way] then active[#active + 1] = way end end
    table.sort(active, function(a, b) if self.touched[row][a] ~= self.touched[row][b] then return self.touched[row][a] > self.touched[row][b] end; return a < b end)
    local positions = {}; for _, way in ipairs(active) do positions[#positions + 1] = way - 1 end
    return #positions > 0 and table.concat(positions, ' ') or '-'
end
function Cache:lines()
    local lines = {}
    for row = 1, self.sets do for way = 1, self.ways do local item = self.entries[row][way]; if item then lines[#lines + 1] = item end end end
    return lines
end
return Cache
