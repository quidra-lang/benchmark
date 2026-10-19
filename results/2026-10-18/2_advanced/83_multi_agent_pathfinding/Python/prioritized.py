"""Try a single PP priority order and install reservations in order."""

from low_level import BudgetExceeded, Prohibitions, reserve_path, search


def try_order(grid, agents, distances, horizon, order, budget):
    prohibitions = Prohibitions()
    paths = {}
    attempts = []
    for agent_id in order:
        try:
            path, expanded = search(
                grid, agents[agent_id], distances[agent_id],
                agents[agent_id]["start"], 0, prohibitions,
                horizon, budget,
            )
        except BudgetExceeded:
            return None, attempts, "ll_budget"
        attempts.append({"agent": agent_id, "path": path, "expansions": expanded})
        if path is None:
            return None, attempts, agent_id
        paths[agent_id] = path
        reserve_path(prohibitions, path, permanent=True)
    return [paths[i] for i in range(len(agents))], attempts, None
