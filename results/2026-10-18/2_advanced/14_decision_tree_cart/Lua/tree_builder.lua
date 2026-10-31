local impurity = require("impurity")
local M = {}
local Split = {}
Split.__index = Split

function M.half_text(value)
    return string.format("%d.%d", value // 2, 5 * (value % 2))
end

function Split:goes_left(value)
    if self.attribute.integer then return 2 * value <= self.point end
    return value == self.point
end

function Split:condition(left)
    local attribute = self.attribute
    if attribute.integer then
        return attribute.name .. (left and " <= " or " > ") .. M.half_text(self.point)
    end
    return attribute.name .. (left and " = " or " != ") .. attribute.values[self.point]
end

function M.candidates(attribute, rows)
    local present, values = {}, {}
    for _, row in ipairs(rows) do
        local value = row.values[attribute.index]
        if not present[value] then present[value] = true; values[#values + 1] = value end
    end
    table.sort(values)
    local result = {}
    if #values < 2 then return result end
    for index, value in ipairs(values) do
        if not attribute.integer or index < #values then
            local point = attribute.integer and (value + values[index + 1]) or value
            result[#result + 1] = setmetatable({attribute = attribute, point = point}, Split)
        end
    end
    return result
end

local Builder = {}
Builder.__index = Builder

function M.new(attributes, class_count, settings)
    return setmetatable({attributes = attributes, class_count = class_count, settings = settings}, Builder)
end

function Builder:best_split(rows, attributes)
    local best
    for _, attribute in ipairs(attributes) do
        for _, split in ipairs(M.candidates(attribute, rows)) do
            local left, right = {}, {}
            for _, row in ipairs(rows) do
                local group = split:goes_left(row.values[attribute.index]) and left or right
                group[#group + 1] = row
            end
            if #left >= self.settings.min_samples_leaf and #right >= self.settings.min_samples_leaf then
                local lc = impurity.class_counts(left, self.class_count)
                local rc = impurity.class_counts(right, self.class_count)
                local value = impurity.evaluation_value(lc, rc)
                if not best or impurity.compare(value, best.value) > 0 then
                    best = {split = split, left = left, right = right, value = value}
                end
            end
        end
    end
    return best
end

function Builder:find_surrogates(rows, primary, left_size, right_size)
    local result = {}
    for _, attribute in ipairs(self.attributes) do
        if attribute ~= primary.attribute then
            local best
            for _, split in ipairs(M.candidates(attribute, rows)) do
                local agreement = 0
                for _, row in ipairs(rows) do
                    if split:goes_left(row.values[attribute.index]) == primary:goes_left(row.values[primary.attribute.index]) then
                        agreement = agreement + 1
                    end
                end
                local score = math.max(agreement, #rows - agreement)
                if not best or score > best.score then
                    best = {split = split, direction = agreement >= #rows - agreement and "left" or "right", score = score}
                end
            end
            if best and best.score > math.max(left_size, right_size) then result[#result + 1] = best end
        end
    end
    table.sort(result, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        return a.split.attribute.index < b.split.attribute.index
    end)
    while #result > self.settings.max_surrogates do table.remove(result) end
    return result
end

function Builder:grow(rows, number, depth)
    number, depth = number or 1, depth or 0
    local counts = impurity.class_counts(rows, self.class_count)
    local prediction = impurity.majority(counts)
    local node = {number = number, depth = depth, counts = counts, size = #rows,
        prediction = prediction, errors = #rows - counts[prediction], surrogates = {}}
    if node.errors == 0 or depth == self.settings.max_depth or #rows < self.settings.min_samples_split then return node end
    local best = self:best_split(rows, self.attributes)
    if not best or not impurity.improves(best.value, counts) then return node end
    node.split = best.split
    node.default = #best.left >= #best.right and "left" or "right"
    node.surrogates = self:find_surrogates(rows, best.split, #best.left, #best.right)
    node.left = self:grow(best.left, 2 * number, depth + 1)
    node.right = self:grow(best.right, 2 * number + 1, depth + 1)
    return node
end

return M
