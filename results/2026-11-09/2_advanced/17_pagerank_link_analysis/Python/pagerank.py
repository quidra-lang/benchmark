class PageRankResult:
    def __init__(self, values, changes, tolerance):
        self.values = values
        self.changes = changes
        self.converged_at = None
        for step, change in enumerate(changes, 1):
            if change < tolerance:
                self.converged_at = step
                break


def power_iteration(in_edges, teleport, damping, iterations, tolerance):
    count = len(in_edges)
    out_weight = [0] * count
    for edges in in_edges:
        for source, weight in edges:
            out_weight[source] += weight
    dangling = [node for node in range(count) if out_weight[node] == 0]
    in_teleport = [False] * count
    for node in teleport:
        in_teleport[node] = True
    size = len(teleport)
    values = [1 / size if in_teleport[node] else 0.0 for node in range(count)]
    changes = []
    for _ in range(iterations):
        dangling_mass = 0.0
        for node in dangling:
            dangling_mass += values[node]
        teleport_value = ((1 - damping) + damping * dangling_mass) / size
        updated = []
        for node in range(count):
            inflow = 0.0
            for source, weight in in_edges[node]:
                inflow += values[source] * weight / out_weight[source]
            if in_teleport[node]:
                updated.append(damping * inflow + teleport_value)
            else:
                updated.append(damping * inflow)
        change = 0.0
        for node in range(count):
            change += abs(updated[node] - values[node])
        changes.append(change)
        values = updated
    return PageRankResult(values, changes, tolerance)
