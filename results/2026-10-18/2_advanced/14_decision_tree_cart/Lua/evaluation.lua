local M = {}
local View = {}
View.__index = View

function M.real(value, places)
    places = places or 4
    local text = string.format("%." .. places .. "f", value)
    if tonumber(text) == 0 then return string.format("%." .. places .. "f", 0) end
    return text
end

function M.ratio(a, b)
    if b == 0 then return "0/0 -" end
    return string.format("%d/%d %s", a, b, M.real(a / b))
end

function M.fraction(a, b, places)
    if b == 0 then return "- -" end
    local x, y = math.abs(a), b
    while y ~= 0 do x, y = y, x % y end
    return string.format("%d/%d %s", a // x, b // x, M.real(a / b, places))
end

function M.view(root, cut)
    return setmetatable({root = root, cut = cut or {}}, View)
end

function View:is_leaf(node)
    return not node.split or self.cut[node.number] == true
end

function View:preorder(start)
    local result, pending = {}, {start or self.root}
    while #pending > 0 do
        local node = table.remove(pending)
        result[#result + 1] = node
        if not self:is_leaf(node) then
            pending[#pending + 1] = node.right
            pending[#pending + 1] = node.left
        end
    end
    return result
end

function View:leaves(start)
    local result = {}
    for _, node in ipairs(self:preorder(start)) do
        if self:is_leaf(node) then result[#result + 1] = node end
    end
    return result
end

function View:internal_nodes()
    local result = {}
    for _, node in ipairs(self:preorder()) do
        if not self:is_leaf(node) then result[#result + 1] = node end
    end
    return result
end

function View:route(row)
    local node, path, steps = self.root, {}, {}
    while true do
        path[#path + 1] = node
        if self:is_leaf(node) then return {leaf = node, path = path, steps = steps} end
        local value = row.values[node.split.attribute.index]
        local left, method
        if value ~= false then
            left, method = node.split:goes_left(value), "primary"
        else
            for _, surrogate in ipairs(node.surrogates) do
                value = row.values[surrogate.split.attribute.index]
                if value ~= false then
                    left = surrogate.split:goes_left(value) == (surrogate.direction == "left")
                    method = "surrogate"
                    break
                end
            end
            if not method then left, method = node.default == "left", "default" end
        end
        steps[#steps + 1] = {node = node, left = left, method = method}
        node = left and node.left or node.right
    end
end

function View:predict(row)
    return self:route(row).leaf.prediction
end

function View:correct_count(rows)
    local correct = 0
    for _, row in ipairs(rows) do
        if self:predict(row) == row.label then correct = correct + 1 end
    end
    return correct
end

function M.classification(title, classes, rows, predictions)
    local matrix, correct = {}, 0
    for a = 1, #classes do
        matrix[a] = {}
        for b = 1, #classes do matrix[a][b] = 0 end
    end
    for index, row in ipairs(rows) do
        matrix[row.label][predictions[index]] = matrix[row.label][predictions[index]] + 1
        if row.label == predictions[index] then correct = correct + 1 end
    end
    local lines = {string.format("confusion %s correct %d/%d accuracy %s", title, correct, #rows, M.fraction(correct, #rows)),
        "actual\\predicted " .. table.concat(classes, " ")}
    for index, name in ipairs(classes) do lines[#lines + 1] = name .. " " .. table.concat(matrix[index], " ") end
    local total, available = 0.0, 0
    for index, name in ipairs(classes) do
        local predicted, support, hits = 0, 0, matrix[index][index]
        for other = 1, #classes do
            predicted = predicted + matrix[other][index]
            support = support + matrix[index][other]
        end
        lines[#lines + 1] = string.format("class %s precision %s recall %s f1 %s support %d", name,
            M.fraction(hits, predicted), M.fraction(hits, support), M.fraction(2 * hits, predicted + support), support)
        if predicted + support > 0 then total, available = total + 2 * hits / (predicted + support), available + 1 end
    end
    lines[#lines + 1] = "macro_f1 " .. (available > 0 and M.real(total / available) or "-")
    return lines
end

return M
