local M = {S = 4096}
function M.floor_div(a, b) return a // b end
function M.mul(a, b) return (a * b) // 4096 end
function M.isqrt(value)
    local low, high = 0, 1
    while high * high <= value do high = high * 2 end
    while low + 1 < high do
        local middle = (low + high) // 2
        if middle * middle <= value then low = middle else high = middle end
    end
    return low
end
return M
