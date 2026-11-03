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

function Minstd:shuffle(values)
    for index = #values, 2, -1 do
        local other = self:below(index) + 1
        values[index], values[other] = values[other], values[index]
    end
    return values
end

return Minstd
