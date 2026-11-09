local A = {}
local function ordered(a, b) return a[1] < b[1] or a[1] == b[1] and a[2] < b[2] end
function A.minimum_matching(costs)
    if #costs == 0 or #costs[1] == 0 then return {} end
    local transposed = #costs > #costs[1]
    local matrix = costs
    if transposed then
        matrix = {}
        for j = 1, #costs[1] do matrix[j] = {}; for i = 1, #costs do matrix[j][i] = costs[i][j] end end
    end
    local rows, columns, u, v, matched, previous = #matrix, #matrix[1], {}, {}, {}, {}
    for i = 0, rows do u[i] = 0.0 end
    for j = 0, columns do v[j], matched[j], previous[j] = 0.0, 0, 0 end
    for row = 1, rows do
        matched[0] = row
        local column, distances, used = 0, {}, {}
        for j = 0, columns do distances[j] = math.huge end
        while true do
            used[column] = true
            local current_row, delta, following = matched[column], math.huge, 0
            for candidate = 1, columns do
                if not used[candidate] then
                    local reduced = matrix[current_row][candidate] - u[current_row] - v[candidate]
                    if reduced < distances[candidate] then distances[candidate], previous[candidate] = reduced, column end
                    if distances[candidate] < delta then delta, following = distances[candidate], candidate end
                end
            end
            for candidate = 0, columns do
                if used[candidate] then u[matched[candidate]], v[candidate] = u[matched[candidate]] + delta, v[candidate] - delta
                else distances[candidate] = distances[candidate] - delta end
            end
            column = following
            if matched[column] == 0 then break end
        end
        while column ~= 0 do
            local following = previous[column]
            matched[column], column = matched[following], following
        end
    end
    local result = {}
    for column = 1, columns do
        if matched[column] ~= 0 then result[#result + 1] = transposed and { column, matched[column] } or { matched[column], column } end
    end
    table.sort(result, ordered)
    return result
end
function A.optimal(rows, columns, usable)
    if rows == 0 or columns == 0 then return {} end
    local largest = nil
    for _, row in pairs(usable) do for _, value in pairs(row) do largest = largest and math.max(largest, value) or value end end
    if largest == nil then return {} end
    local penalty = (math.min(rows, columns) + 1) * (math.max(1.0, largest) + 1.0)
    local costs = {}
    for i = 1, rows do
        costs[i] = {}
        for j = 1, columns do local value = usable[i] and usable[i][j]; costs[i][j] = value ~= nil and value or penalty end
    end
    local result = {}
    for _, pair in ipairs(A.minimum_matching(costs)) do if usable[pair[1]] and usable[pair[1]][pair[2]] ~= nil then result[#result + 1] = pair end end
    return result
end
return A
