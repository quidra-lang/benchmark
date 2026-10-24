"""CBS plan conflicts, branch constraints and constraint-tree ordering."""


def position(path, time):
    return path[min(time, len(path) - 1)]


def conflicts(paths):
    """Order conflicts by time, then lexicographic agent pairs."""
    horizon = max(len(path) - 1 for path in paths)
    all_conflicts = []
    for time in range(1, horizon + 1):
        for first in range(len(paths)):
            for second in range(first + 1, len(paths)):
                current_a = position(paths[first], time)
                current_b = position(paths[second], time)
                if current_a == current_b:
                    all_conflicts.append({
                        "kind": "vertex", "time": time,
                        "a": first, "b": second, "cell": current_a,
                    })
                elif (current_a == position(paths[second], time - 1)
                      and current_b == position(paths[first], time - 1)):
                    all_conflicts.append({
                        "kind": "edge", "time": time,
                        "a": first, "b": second,
                        "u": position(paths[first], time - 1),
                        "v": current_a,
                    })
    return all_conflicts


def split_constraints(conflict):
    a, b, time = conflict["a"], conflict["b"], conflict["time"]
    if conflict["kind"] == "vertex":
        cell = conflict["cell"]
        return (a, "vertex", cell, time), (b, "vertex", cell, time)
    return ((a, "edge", (conflict["u"], conflict["v"]), time),
            (b, "edge", (conflict["v"], conflict["u"]), time))


def plan_cost(paths, cost_function):
    lengths = [len(path) - 1 for path in paths]
    return sum(lengths) if cost_function == "SOC" else max(lengths)


def new_node(paths, constraints, number, depth, parent, cost_function):
    conflicts_here = conflicts(paths)
    return {
        "paths": paths, "constraints": constraints,
        "number": number, "depth": depth, "parent": parent,
        "conflicts": conflicts_here,
        "cost": plan_cost(paths, cost_function),
    }


def key(node):
    return node["cost"], len(node["conflicts"]), node["number"]


def ordered_constraints(node):
    """Return all constraints sorted by agent, time, kind and coordinates."""
    result = []
    for agent, restrictions in enumerate(node["constraints"]):
        for cell, time in restrictions.states:
            result.append((agent, time, 0, cell, cell, "vertex"))
        for u, v, time in restrictions.moves:
            result.append((agent, time, 1, u, v, "edge"))
    return sorted(result, key=lambda item: (
        item[0], item[1], item[2],
        item[3][0], item[3][1], item[4][0], item[4][1],
    ))
