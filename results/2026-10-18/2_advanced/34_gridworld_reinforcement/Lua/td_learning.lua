local dp = require("dynamic_programming")
local M = {}
function M.choose(generator, values, epsilon)
    if generator:draw() % 1000 < epsilon then
        return generator:draw() % 4
    end
    return dp.first_max(values)
end
function M.target(reward, terminal, value, gamma)
    return 10000 * reward + (terminal and 0 or gamma * value // 100)
end
function M.expected(values, epsilon)
    local total = 0
    for _, value in ipairs(values) do
        total = total + value
    end
    return (epsilon * total + 4 * (1000 - epsilon) * math.max(table.unpack(values))) // 4000
end
function M.update(values, action, target, alpha)
    values[action + 1] = values[action + 1] + alpha * (target - values[action + 1]) // 100
end
local Model = {}
Model.__index = Model
function M.model(states)
    local outcomes = {}
    for state = 1, states do
        outcomes[state] = {}
    end
    return setmetatable({outcomes = outcomes, pairs = {}}, Model)
end
function Model:record(state, action, reward, next_state)
    if not self.outcomes[state][action + 1] then
        self.pairs[#self.pairs + 1] = {state, action}
    end
    self.outcomes[state][action + 1] = {reward = reward, next_state = next_state}
end
function Model:plan(generator, q, gamma, alpha, steps)
    for _ = 1, steps do
        local pair = self.pairs[generator:draw() % #self.pairs + 1]
        local outcome = self.outcomes[pair[1]][pair[2] + 1]
        local value = outcome.next_state and math.max(table.unpack(q[outcome.next_state])) or 0
        M.update(q[pair[1]], pair[2], M.target(outcome.reward, not outcome.next_state, value, gamma), alpha)
    end
end
return M
