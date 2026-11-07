local M = {}
function M.real_text(value)
    local text = string.format("%.4f", value)
    return text == "-0.0000" and "0.0000" or text
end
function M.proportion_text(numerator, denominator)
    return numerator .. "/" .. denominator .. " " .. M.real_text(numerator / denominator)
end
function M.fraction_text(numerator, denominator)
    if denominator == 0 then return "- -" end
    local a, b = numerator, denominator
    while b ~= 0 do a, b = b, a % b end
    return M.proportion_text(numerator // a, denominator // a)
end

local Evaluation = {}
Evaluation.__index = Evaluation
function Evaluation.new(class_count, truths, predictions)
    local self = setmetatable({matrix = {}, total = #truths, correct = 0}, Evaluation)
    for label = 1, class_count do self.matrix[label] = {} for other = 1, class_count do self.matrix[label][other] = 0 end end
    for index, truth in ipairs(truths) do local predicted = predictions[index] self.matrix[truth][predicted] = self.matrix[truth][predicted] + 1 end
    local f1_sum, scored = 0.0, 0
    for label = 1, class_count do
        self.correct = self.correct + self.matrix[label][label]
        local denominator = self:predicted_count(label) + self:support(label)
        if denominator > 0 then f1_sum, scored = f1_sum + 2 * self.matrix[label][label] / denominator, scored + 1 end
    end
    self.micro_f1, self.macro_f1 = self.correct / self.total, f1_sum / scored
    return self
end
function Evaluation:support(label)
    local count = 0
    for _, value in ipairs(self.matrix[label]) do count = count + value end
    return count
end
function Evaluation:predicted_count(label)
    local count = 0
    for _, row in ipairs(self.matrix) do count = count + row[label] end
    return count
end
function Evaluation:lines(names)
    local lines = {"true\\predicted " .. table.concat(names, " ")}
    for label, name in ipairs(names) do
        local fields = {name}
        for _, count in ipairs(self.matrix[label]) do fields[#fields + 1] = tostring(count) end
        lines[#lines + 1] = table.concat(fields, " ")
    end
    for label, name in ipairs(names) do
        local hits, predicted, support = self.matrix[label][label], self:predicted_count(label), self:support(label)
        lines[#lines + 1] = "class " .. name .. " precision " .. M.fraction_text(hits, predicted) .. " recall " .. M.fraction_text(hits, support)
            .. " f1 " .. M.fraction_text(2 * hits, predicted + support) .. " support " .. support
    end
    lines[#lines + 1] = "micro_f1 " .. M.real_text(self.micro_f1) .. " macro_f1 " .. M.real_text(self.macro_f1)
    return lines
end
M.Evaluation = Evaluation
return M
