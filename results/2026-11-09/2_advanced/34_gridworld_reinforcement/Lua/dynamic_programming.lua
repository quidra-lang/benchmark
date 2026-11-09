local M = {}
function M.first_max(values)
    local action = 0
    for i = 2, 4 do
        if values[i] > values[action + 1] then
            action = i - 1
        end
    end
    return action
end
function M.bellman(environment, values, gamma, state, action)
    local total = 0
    for _, transition in ipairs(environment.transitions[state][action + 1]) do
        local next_state = environment.world.state_index[transition.cell + 1]
        local future = next_state and gamma * values[next_state] // 100 or 0
        total = total + transition.numerator * (10000 * environment:reward(transition.cell) + future)
    end
    return total // environment.slip_total
end
function M.actions(environment, values, gamma, state)
    local result = {}
    for action = 0, 3 do
        result[action + 1] = M.bellman(environment, values, gamma, state, action)
    end
    return result
end
function M.policy(environment, values, gamma)
    local policy = {}
    for state = 1, #values do
        policy[state] = M.first_max(M.actions(environment, values, gamma, state))
    end
    return policy
end
local function zeros(count)
    local values = {}
    for i = 1, count do
        values[i] = 0
    end
    return values
end
function M.value_iteration(environment, gamma, theta)
    local values, changes = zeros(#environment.world.states), {}
    while true do
        local updated, delta = {}, 0
        for state = 1, #values do
            updated[state] = math.max(table.unpack(M.actions(environment, values, gamma, state)))
            delta = math.max(delta, math.abs(updated[state] - values[state]))
        end
        changes[#changes + 1], values = delta, updated
        if delta <= theta then
            return values, changes
        end
    end
end
function M.in_place(environment, gamma, theta)
    local values, sweeps = zeros(#environment.world.states), 0
    while true do
        local delta = 0
        sweeps = sweeps + 1
        for state = 1, #values do
            local value = math.max(table.unpack(M.actions(environment, values, gamma, state)))
            delta, values[state] = math.max(delta, math.abs(value - values[state])), value
        end
        if delta <= theta then
            return values, sweeps
        end
    end
end
function M.evaluate(environment, policy, initial, gamma, theta)
    local values, sweeps = {}, 0
    for i, value in ipairs(initial) do
        values[i] = value
    end
    while true do
        local delta = 0
        sweeps = sweeps + 1
        for state, action in ipairs(policy) do
            local value = M.bellman(environment, values, gamma, state, action)
            delta, values[state] = math.max(delta, math.abs(value - values[state])), value
        end
        if delta <= theta then
            return values, sweeps
        end
    end
end
function M.policy_iteration(environment, gamma, theta)
    local policy, values, rounds = zeros(#environment.world.states), zeros(#environment.world.states), {}
    while true do
        local sweeps
        values, sweeps = M.evaluate(environment, policy, values, gamma, theta)
        local improved, changes = M.policy(environment, values, gamma), 0
        for state, action in ipairs(improved) do
            if action ~= policy[state] then
                changes = changes + 1
            end
        end
        rounds[#rounds + 1] = {sweeps = sweeps, changes = changes, value = values[environment.world.start_state]}
        policy = improved
        if changes == 0 then
            return policy, values, rounds
        end
    end
end
return M
