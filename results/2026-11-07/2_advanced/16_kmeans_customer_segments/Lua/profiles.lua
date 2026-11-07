local transactions = require("transactions")
local features = require("features")
local M = {}

function M.read(path)
    local rules = {}
    for _, line in ipairs(transactions.lines(path)) do
        local words, conditions = transactions.split(line, " "), {}
        for i = 2, #words, 3 do
            local feature
            for j, name in ipairs(features.names) do if name == words[i] then feature = j; break end end
            conditions[#conditions + 1] = {feature = feature, comparison = words[i + 1], threshold = tonumber(words[i + 2])}
        end
        rules[#rules + 1] = {name = words[1], conditions = conditions}
    end
    return rules
end

function M.rule_number(center, rules)
    for i, rule in ipairs(rules) do
        local holds = true
        for _, condition in ipairs(rule.conditions) do
            local value = center[condition.feature]
            if condition.comparison == ">" and not (value > condition.threshold) or condition.comparison == "<" and not (value < condition.threshold) then holds = false; break end
        end
        if holds then return i end
    end
end

function M.original(center, scaling)
    local values = {}
    for i, component in ipairs(center) do
        local value = scaling[i].mean + scaling[i].sd * component
        values[i] = features.root(i) and value * value or value
    end
    return values
end

return M
