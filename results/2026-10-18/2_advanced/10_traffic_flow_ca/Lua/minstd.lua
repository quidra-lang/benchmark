local M = {}
function M.new(seed)
    return {state = seed, draw = function(self) self.state = 48271 * self.state % 2147483647; return self.state end}
end
function M.select(weights, value)
    local total = 0
    for _, weight in ipairs(weights) do total = total + weight end
    local q = value % total
    for i, weight in ipairs(weights) do if q < weight then return i end; q = q - weight end
end
return M
