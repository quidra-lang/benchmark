function try_priority_order(grid, agents, distances, horizon, order, budget)
    restrictions = Prohibitions()
    paths = [Int[] for _ in agents]
    attempts = NamedTuple[]
    for agent in order
        result = low_search(
            grid,
            agents[agent],
            distances[agent],
            agents[agent].start,
            0,
            restrictions,
            horizon,
            budget
        )
        result.aborted && return (paths=nothing, attempts=attempts, failure="ll_budget", failed_agent=0)
        push!(attempts, (agent=agent, path=result.path, expansions=result.expansions))
        result.path === nothing && return (
            paths=nothing,
            attempts=attempts,
            failure="path",
            failed_agent=agent
        )
        paths[agent] = result.path
        reserve_path!(restrictions, result.path; permanent=true)
    end
    return (paths=paths, attempts=attempts, failure="", failed_agent=0)
end
