local M = {}
function M.build(data)
    local result = {users = {}, items = {}, common = {}, difference = {}}
    for _, u in ipairs(data.users) do
        result.users[u] = {}
    end
    for _, i in ipairs(data.items) do
        result.items[i], result.common[i], result.difference[i] = {}, {}, {}
    end
    local shrinkage = data.params.shrinkage
    for first = 1, #data.users - 1 do
        local u = data.users[first]
        for second = first + 1, #data.users do
            local v = data.users[second]
            local n, sx, sy, sxx, syy, sxy = 0, 0, 0, 0, 0, 0
            for _, row in ipairs(data.user_ratings[u]) do
                local other = data.values[v][row.item]
                if other then
                    local value = row.rating
                    n, sx, sy = n + 1, sx + value, sy + other
                    sxx, syy, sxy = sxx + value * value, syy + other * other, sxy + value * other
                end
            end
            if n >= 2 then
                local numerator, dx, dy = n * sxy - sx * sy, n * sxx - sx * sx, n * syy - sy * sy
                if dx ~= 0 and dy ~= 0 then
                    local scaled = numerator * n
                    local a = scaled * scaled
                    local b = dx * dy * (n + shrinkage) * (n + shrinkage)
                    local sign = numerator < 0 and -1 or numerator > 0 and 1 or 0
                    local record = {value = sign * math.sqrt(a / b), common = n}
                    result.users[u][v], result.users[v][u] = record, record
                end
            end
        end
    end
    for first = 1, #data.items - 1 do
        local i = data.items[first]
        for second = first + 1, #data.items do
            local j = data.items[second]
            local n, difference, numerator, ni, nj = 0, 0, 0.0, 0.0, 0.0
            for _, row in ipairs(data.item_ratings[i]) do
                local other = data.values[row.user][j]
                if other then
                    n = n + 1
                    difference = difference + row.rating - other
                    local di, dj = row.rating - data.user_means[row.user], other - data.user_means[row.user]
                    numerator, ni, nj = numerator + di * dj, ni + di * di, nj + dj * dj
                end
            end
            if n >= 1 then
                result.common[i][j], result.common[j][i] = n, n
                result.difference[i][j], result.difference[j][i] = difference, -difference
            end
            if n >= 2 and ni ~= 0.0 and nj ~= 0.0 then
                local record = {value = numerator / math.sqrt(ni * nj) * n / (n + shrinkage), common = n}
                result.items[i][j], result.items[j][i] = record, record
            end
        end
    end
    return result
end
function M.select(candidates, count)
    table.sort(candidates, function(a, b)
        if a.similarity ~= b.similarity then
            return a.similarity > b.similarity
        end
        return a.id < b.id
    end)
    local result = {}
    for index = 1, math.min(count, #candidates) do
        result[index] = candidates[index]
    end
    return result
end
return M
