local M = {pi = math.pi}
function M.determinant(cov)
    return cov[1] * cov[3] - cov[2] * cov[2]
end
function M.mahalanobis(point, mean, cov)
    local dx, dy = point[1] - mean[1], point[2] - mean[2]
    local a, b, c = table.unpack(cov)
    return (c * dx * dx - 2 * b * dx * dy + a * dy * dy) / M.determinant(cov)
end
function M.log_density(point, weight, mean, cov)
    return math.log(weight) - math.log(2 * math.pi) - math.log(M.determinant(cov)) / 2
        - M.mahalanobis(point, mean, cov) / 2
end
function M.eigen(cov)
    local a, b, c = table.unpack(cov)
    local h = (a + c) / 2
    local g = math.sqrt(((a - c) / 2) * ((a - c) / 2) + b * b)
    local leading, trailing = h + g, h - g
    local ux, uy
    if b == 0 then
        ux, uy = 1, 0
        if a < c then ux, uy = 0, 1 end
    else
        local vx, vy = leading - c, b
        if a < c then vx, vy = b, leading - a end
        local length = math.sqrt(vx * vx + vy * vy)
        ux, uy = vx / length, vy / length
        if vx < 0 then ux, uy = -ux, -uy end
    end
    return {leading = leading, trailing = trailing, direction = {ux, uy},
        angle = math.atan(uy, ux) * 180 / math.pi,
        axes = {math.sqrt(leading), math.sqrt(trailing)},
        area = math.pi * math.sqrt(leading * trailing), correlation = b / math.sqrt(a * c)}
end
function M.bhattacharyya(mean_a, cov_a, mean_b, cov_b)
    local mean_cov = {}
    for j = 1, 3 do mean_cov[j] = (cov_a[j] + cov_b[j]) / 2 end
    local d = M.mahalanobis(mean_b, mean_a, mean_cov) / 8
        + math.log(M.determinant(mean_cov) / math.sqrt(M.determinant(cov_a) * M.determinant(cov_b))) / 2
    return d, math.exp(-d)
end
return M
