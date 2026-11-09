local M = {}
local function split(line, separator)
    local result = {}
    for value in (line .. separator):gmatch("(.-)" .. separator) do
        result[#result + 1] = value
    end
    return result
end
local function table_rows(path)
    local features, rows = nil, {}
    for line in io.lines(path) do
        local fields = split(line, ",")
        if not features then
            features = {}
            for index = 2, #fields - 1 do
                features[#features + 1] = fields[index]
            end
        else
            local values = {}
            for index = 2, #fields - 1 do
                values[#values + 1] = tonumber(fields[index])
            end
            rows[#rows + 1] = {id = tonumber(fields[1]), values = values, label = fields[#fields]}
        end
    end
    return features, rows
end
function M.read()
    local features, train = table_rows("input/train.csv")
    local _, test = table_rows("input/test.csv")
    local classes, known = {}, {}
    for _, row in ipairs(train) do
        if not known[row.label] then
            classes[#classes + 1], known[row.label] = row.label, true
        end
    end
    table.sort(classes)
    local class_indices, feature_indices = {}, {}
    for index, name in ipairs(classes) do
        class_indices[name] = index
    end
    for index, name in ipairs(features) do
        feature_indices[name] = index
    end
    for _, rows in ipairs({train, test}) do
        for _, row in ipairs(rows) do
            row.class_index = class_indices[row.label]
        end
    end
    local columns, costs = nil, {}
    for line in io.lines("input/costs.csv") do
        local fields = split(line, ",")
        if not columns then
            columns = fields
        else
            local values = {}
            for index = 2, #fields do
                values[class_indices[columns[index]]] = tonumber(fields[index])
            end
            costs[class_indices[fields[1]]] = values
        end
    end
    local params = {subsets = {}, pairs = {}}
    for line in io.lines("input/params.txt") do
        local words = split(line, " ")
        local keyword = table.remove(words, 1)
        if keyword == "SUBSET" then
            local name = table.remove(words, 1)
            local indices = {}
            for index, feature in ipairs(words) do
                indices[index] = feature_indices[feature]
            end
            params.subsets[#params.subsets + 1] = {name = name, features = indices}
        elseif keyword == "PAIR" then
            params.pairs[#params.pairs + 1] = {feature_indices[words[1]], feature_indices[words[2]]}
        elseif keyword == "PRIOR" then
            params.prior = words[1]
        else
            local values = {}
            for index, value in ipairs(words) do
                values[index] = tonumber(value)
            end
            params[keyword] = values
        end
    end
    params.epsilon, params.gamma = params.VAR_SMOOTHING[1], params.QDA_GAMMA[1]
    params.folds, params.theta = params.CV_FOLDS[1], params.OUTLIER_THRESHOLD[1]
    params.bootstrap_count, params.seed = params.BOOTSTRAP[1], params.BOOTSTRAP[2]
    return {features = features, classes = classes, train = train, test = test, costs = costs, params = params}
end
return M
