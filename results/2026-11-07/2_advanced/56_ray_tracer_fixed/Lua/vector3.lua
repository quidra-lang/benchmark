local fixed = require("fixed_point")
local M = {}
function M.add(a, b) return {a[1] + b[1], a[2] + b[2], a[3] + b[3]} end
function M.sub(a, b) return {a[1] - b[1], a[2] - b[2], a[3] - b[3]} end
function M.neg(a) return {-a[1], -a[2], -a[3]} end
function M.dot(a, b) return (a[1] * b[1] + a[2] * b[2] + a[3] * b[3]) // 4096 end
function M.scale(a, k) return {(a[1] * k) // 4096, (a[2] * k) // 4096, (a[3] * k) // 4096} end
function M.length(a) return fixed.isqrt(a[1] * a[1] + a[2] * a[2] + a[3] * a[3]) end
function M.norm(a)
    local length = M.length(a)
    return {(a[1] * 4096) // length, (a[2] * 4096) // length, (a[3] * 4096) // length}
end
return M
