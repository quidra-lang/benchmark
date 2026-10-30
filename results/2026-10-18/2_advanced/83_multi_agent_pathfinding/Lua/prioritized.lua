local Low = require("low_level")
local Prioritized = {}

function Prioritized.try_order(grid, agents, distances, horizon, order, budget)
    local restrictions, paths, attempts = Low.restrictions(), {}, {}
    for _, index in ipairs(order) do
        local agent = agents[index]
        local path, expansions, aborted = Low.search(grid, agent, distances[index], agent.start,
            0, restrictions, horizon, budget, false)
        if aborted then return nil, attempts, "ll_budget" end
        attempts[#attempts + 1] = {agent = index, path = path, expansions = expansions}
        if not path then return nil, attempts, index end
        paths[index] = path
        Low.reserve(restrictions, path, 0, true)
    end
    return paths, attempts, nil
end

return Prioritized
