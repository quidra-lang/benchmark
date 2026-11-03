local Minstd = {}
Minstd.__index = Minstd
function Minstd.new(seed)
    return setmetatable({state = seed}, Minstd)
end
function Minstd:draw()
    self.state = 48271 * self.state % 2147483647
    return self.state
end
function Minstd:below(limit)
    return self:draw() % limit
end
function Minstd:chance(probability)
    return self:draw() % probability[2] < probability[1]
end
function Minstd:shuffle(items)
    for size = #items, 2, -1 do
        local index = self:below(size) + 1
        items[size], items[index] = items[index], items[size]
    end
end
return Minstd
