local M = {}
function M.discounted(rewards, gamma)
    local value = 0
    for index = #rewards, 1, -1 do
        value = 10000 * rewards[index] + gamma * value // 100
    end
    return value
end
local Averages = {}
Averages.__index = Averages
function M.new(states)
    local self = setmetatable({sums = {}, counts = {}}, Averages)
    for state = 1, states do
        self.sums[state], self.counts[state] = {0, 0, 0, 0}, {0, 0, 0, 0}
    end
    return self
end
function Averages:update(q, history, gamma)
    local seen, first = {}, {}
    for i, row in ipairs(history) do
        local key = row.state .. "," .. row.action
        first[i], seen[key] = not seen[key], true
    end
    local value = 0
    for i = #history, 1, -1 do
        local row = history[i]
        value = 10000 * row.reward + gamma * value // 100
        if first[i] then
            local state, action = row.state, row.action + 1
            self.sums[state][action] = self.sums[state][action] + value
            self.counts[state][action] = self.counts[state][action] + 1
            q[state][action] = self.sums[state][action] // self.counts[state][action]
        end
    end
end
return M
