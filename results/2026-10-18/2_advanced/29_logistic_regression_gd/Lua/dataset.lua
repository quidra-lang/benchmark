local M = {}
local function split(text, separator)
    local result = {}
    for value in (text .. separator):gmatch("(.-)" .. separator) do
        result[#result + 1] = value
    end
    return result
end
function M.read_examples(path)
    local handle = assert(io.open(path, "rb"))
    local header = split(assert(handle:read("l")), ",")
    local names, rows = {}, {}
    for i = 2, #header - 1 do
        names[#names + 1] = header[i]
    end
    for line in handle:lines() do
        local fields, values = split(line, ","), {}
        for i = 2, #fields - 1 do
            values[#values + 1] = tonumber(fields[i])
        end
        rows[#rows + 1] = {ident = fields[1], values = values, label = tonumber(fields[#fields])}
    end
    handle:close()
    return names, rows
end
function M.read_settings(path)
    local rows = {}
    for line in io.lines(path) do
        local fields = split(line, " ")
        local values = {}
        for i = 2, #fields do
            values[#values + 1] = tonumber(fields[i])
        end
        rows[fields[1]] = values
    end
    return {
        positive = rows.POSITIVE[1], degree = rows.DEGREE[1], threshold = rows.THRESHOLD[1], lambdas = rows.LAMBDAS,
        gd_rate = rows.GD[1], gd_iterations = rows.GD[2], sgd_rate = rows.SGD[1], batch_size = rows.SGD[2], epochs = rows.SGD[3], sgd_seed = rows.SGD[4],
        softmax_rate = rows.SOFTMAX[1], softmax_iterations = rows.SOFTMAX[2], softmax_lambda = rows.SOFTMAX[3],
        bootstrap_count = rows.BOOTSTRAP[1], bootstrap_seed = rows.BOOTSTRAP[2], permutation_count = rows.PERMUTATION[1], permutation_seed = rows.PERMUTATION[2],
        map_width = rows.MAP[1], map_height = rows.MAP[2], cost_fp = rows.COST[1], cost_fn = rows.COST[2]
    }
end
function M.expansion_tuples(base_count, degree)
    local tuples = {}
    local function visit(indices, first, remaining)
        if remaining == 0 then
            tuples[#tuples + 1] = {table.unpack(indices)}
            return
        end
        for index = first, base_count do
            indices[#indices + 1] = index
            visit(indices, index, remaining - 1)
            indices[#indices] = nil
        end
    end
    for length = 1, degree do
        visit({}, 1, length)
    end
    return tuples
end
function M.expanded_names(names, tuples)
    local result = {}
    for j, indices in ipairs(tuples) do
        local pieces = {}
        for i, index in ipairs(indices) do
            pieces[i] = names[index]
        end
        result[j] = table.concat(pieces, "*")
    end
    return result
end
function M.expanded_values(tuples, values)
    local expanded = {}
    for j, indices in ipairs(tuples) do
        local product = values[indices[1]]
        for i = 2, #indices do
            product = product * values[indices[i]]
        end
        expanded[j] = product
    end
    return expanded
end
function M.compute_statistics(rows, count)
    local means, deviations = {}, {}
    for j = 1, count do
        local total = 0.0
        for _, row in ipairs(rows) do
            total = total + row[j]
        end
        local mean, squares = total / #rows, 0.0
        for _, row in ipairs(rows) do
            squares = squares + (row[j] - mean) * (row[j] - mean)
        end
        means[j], deviations[j] = mean, math.sqrt(squares / (#rows - 1))
    end
    return {means = means, deviations = deviations}
end
function M.standardize(values, statistics, count)
    local vector = {1.0}
    for j = 1, count do
        vector[j + 1] = (values[j] - statistics.means[j]) / statistics.deviations[j]
    end
    return vector
end
return M
