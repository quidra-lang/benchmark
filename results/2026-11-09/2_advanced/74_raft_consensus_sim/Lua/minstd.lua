local M = {}
M.__index = M
function M.new(seed) return setmetatable({state = seed, draws = 0}, M) end
function M:draw()
    self.state = (48271 * self.state) % 2147483647
    self.draws = self.draws + 1
    return self.state
end
function M:between(minimum, maximum) return minimum + self:draw() % (maximum - minimum + 1) end
return M
