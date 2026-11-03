local Minstd = {}
Minstd.__index = Minstd

function Minstd.new(seed) return setmetatable({state = seed}, Minstd) end
function Minstd:draw() self.state = self.state * 48271 % 2147483647 return self.state end
function Minstd:rnd(n) return self:draw() % n end

function Minstd:roll(count, sides)
    local total = 0
    for _ = 1, count do total = total + 1 + self:rnd(sides) end
    return total
end

function Minstd:select(weights)
    local sum = 0
    for _, weight in ipairs(weights) do sum = sum + weight end
    local q, total = self:draw() % sum, 0
    for index, weight in ipairs(weights) do
        total = total + weight
        if q < total then return index end
    end
end

return Minstd
