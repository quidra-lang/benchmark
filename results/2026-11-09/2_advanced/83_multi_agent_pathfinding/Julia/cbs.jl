path_position(path, time) = path[min(time + 1, length(path))]
function plan_conflicts(paths)
    horizon = maximum(length(path) - 1 for path in paths)
    result = NamedTuple[]
    for time in 1:horizon, a in 1:length(paths), b in a + 1:length(paths)
        current_a, current_b = path_position(paths[a], time), path_position(paths[b], time)
        if current_a == current_b
            push!(result, (kind="vertex", time=time, a=a, b=b, u=current_a, v=current_a))
        elseif current_a == path_position(paths[b], time - 1) && current_b == path_position(
            paths[a],
            time - 1
        )
            push!(
                result,
                (kind="edge", time=time, a=a, b=b, u=path_position(paths[a], time - 1), v=current_a)
            )
        end
    end
    return result
end

function split_constraints(conflict)
    first_branch = (agent=conflict.a, kind=conflict.kind, u=conflict.u, v=conflict.v, time=conflict.time)
    second_branch = (agent=conflict.b, kind=conflict.kind, u=conflict.v, v=conflict.u, time=conflict.time)
    return first_branch, second_branch
end

plan_cost(
    paths,
    cost_function
) = cost_function == "SOC" ? sum(length(path) - 1 for path in paths) : maximum(length(path) - 1 for path in paths)
function new_node(paths, constraints, number, depth, parent, cost_function)
    return (
        ; paths,
        constraints,
        number,
        depth,
        parent,
        conflicts=plan_conflicts(paths),
        cost=plan_cost(paths, cost_function)
    )
end
node_key(node) = (node.cost, length(node.conflicts), node.number)

function ordered_constraints(node, grid)
    result = NamedTuple[]
    for (agent, restrictions) in enumerate(node.constraints)
        for (cell, time) in restrictions.states
            push!(result, (agent=agent, time=time, rank=0, u=cell, v=cell, kind="vertex"))
        end
        for (u, v, time) in restrictions.moves
            push!(result, (agent=agent, time=time, rank=1, u=u, v=v, kind="edge"))
        end
    end
    return sort!(result; by=item -> (
        item.agent,
        item.time,
        item.rank,
        item.u % grid.width,
        item.u ÷ grid.width,
        item.v % grid.width,
        item.v ÷ grid.width
    ))
end
