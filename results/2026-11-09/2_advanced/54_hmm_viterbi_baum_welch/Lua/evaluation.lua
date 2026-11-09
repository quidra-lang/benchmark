local M = {}
function M.fraction(numerator, denominator)
    if denominator == 0 then return "-" end
    if denominator < 0 then numerator, denominator = -numerator, -denominator end
    local a, b = math.abs(numerator), denominator
    while b ~= 0 do a, b = b, a % b end
    return (numerator // a) .. "/" .. (denominator // a)
end
function M.matrix(count)
    local result = {}
    for i = 1, count do
        result[i] = {}
        for j = 1, count do result[i][j] = 0 end
    end
    return result
end
function M.accumulate(matrix, truth, prediction)
    for t, actual in ipairs(truth) do matrix[actual][prediction[t]] = matrix[actual][prediction[t]] + 1 end
end
function M.correct(truth, prediction)
    local count = 0
    for t, actual in ipairs(truth) do if actual == prediction[t] then count = count + 1 end end
    return count
end
function M.matrix_lines(states, matrix)
    local width = 1
    for _, row in ipairs(matrix) do for _, value in ipairs(row) do width = math.max(width, #tostring(value)) end end
    local header, result = " ", {}
    for _, state in ipairs(states) do header = header .. " " .. string.format("%" .. width .. "s", state) end
    result[1] = header
    for i, row in ipairs(matrix) do
        local line = states[i]
        for _, value in ipairs(row) do line = line .. " " .. string.format("%" .. width .. "d", value) end
        result[#result + 1] = line
    end
    return result
end
function M.metrics(states, matrix)
    local rows, columns, total, correct = {}, {}, 0, 0
    for i = 1, #states do rows[i], columns[i] = 0, 0 end
    for i = 1, #states do
        correct = correct + matrix[i][i]
        for j = 1, #states do rows[i], columns[j], total = rows[i] + matrix[i][j], columns[j] + matrix[i][j], total + matrix[i][j] end
    end
    local expected = 0
    for i = 1, #states do expected = expected + rows[i] * columns[i] end
    local result = {"ACCURACY " .. M.fraction(correct, total), "KAPPA " .. M.fraction(total * correct - expected, total * total - expected)}
    for i, state in ipairs(states) do
        result[#result + 1] = "STATE " .. state .. " precision " .. M.fraction(matrix[i][i], columns[i])
            .. " recall " .. M.fraction(matrix[i][i], rows[i]) .. " f1 " .. M.fraction(2 * matrix[i][i], columns[i] + rows[i])
    end
    return result
end
function M.runs(path)
    local result = {}
    if #path == 0 then return result end
    local start, state = 1, path[1]
    for t = 2, #path do
        if path[t] ~= state then result[#result + 1] = {state, start, t - 1}; state, start = path[t], t end
    end
    result[#result + 1] = {state, start, #path}
    return result
end
function M.region_counts(predicted, truth)
    local function matched(left, right)
        local count = 0
        for _, a in ipairs(left) do
            for _, b in ipairs(right) do if a[1] <= b[2] and b[1] <= a[2] then count = count + 1; break end end
        end
        return count
    end
    return {#predicted, #truth, matched(predicted, truth), matched(truth, predicted)}
end
function M.boundaries(path)
    local result = {}
    for t = 2, #path do if path[t] ~= path[t - 1] then result[#result + 1] = t end end
    return result
end
function M.boundary_counts(predicted, truth, tolerance)
    local a, b = M.boundaries(predicted), M.boundaries(truth)
    local function matched(left, right)
        local count = 0
        for _, p in ipairs(left) do
            for _, q in ipairs(right) do if math.abs(p - q) <= tolerance then count = count + 1; break end end
        end
        return count
    end
    return {#a, #b, matched(a, b), matched(b, a)}
end
return M
