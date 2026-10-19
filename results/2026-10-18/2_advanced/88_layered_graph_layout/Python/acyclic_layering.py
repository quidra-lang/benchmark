"""Eades–Lin–Smyth ordering, heights, and exact recursive promotion."""


def neighbors(count, edges):
    upper = [[] for _ in range(count)]
    lower = [[] for _ in range(count)]
    for first, second in edges:
        lower[first].append(second)
        upper[second].append(first)
    return upper, lower


def acyclic_order(count, edges):
    upper, lower = neighbors(count, edges)
    remaining = set(range(count))
    head, tail = [], []
    while remaining:
        indegree = {v: sum(u in remaining for u in upper[v]) for v in remaining}
        outdegree = {v: sum(w in remaining for w in lower[v]) for v in remaining}
        sinks = [v for v in remaining if outdegree[v] == 0]
        sources = [v for v in remaining if indegree[v] == 0]
        if sinks:
            chosen = min(sinks)
            tail.insert(0, chosen)
        elif sources:
            chosen = min(sources)
            head.append(chosen)
        else:
            chosen = min(remaining, key=lambda v: (indegree[v] - outdegree[v], v))
            head.append(chosen)
        remaining.remove(chosen)
    return head + tail


def initial_heights(count, upper, lower, method, width):
    heights = [None] * count
    labels = None
    if method == "coffman":
        labels = [None] * count
        for label in range(1, count + 1):
            candidates = [v for v in range(count)
                          if labels[v] is None and all(labels[u] is not None for u in upper[v])]
            chosen = min(candidates, key=lambda v: (sorted((labels[u] for u in upper[v]), reverse=True), v))
            labels[chosen] = label
        current = 0
        occupied = 0
        for _ in range(count):
            candidates = [v for v in range(count)
                          if heights[v] is None and all(heights[w] is not None for w in lower[v])]
            chosen = max(candidates, key=lambda v: labels[v])
            if occupied == width or any(heights[w] == current for w in lower[chosen]):
                current += 1
                occupied = 0
            heights[chosen] = current
            occupied += 1
    else:
        for _ in range(count):
            chosen = next(v for v in range(count)
                          if heights[v] is None and all(heights[w] is not None for w in lower[v]))
            heights[chosen] = max((heights[w] + 1 for w in lower[chosen]), default=0)
    return heights, labels


def assign_heights(count, edges, settings):
    upper, lower = neighbors(count, edges)
    heights, labels = initial_heights(count, upper, lower, settings["layering"], settings["width"])
    dummies_before = sum(heights[a] - heights[b] - 1 for a, b in edges)
    record = []
    rounds = 0

    def promote(vertex):
        difference = 0
        for predecessor in upper[vertex]:
            if heights[predecessor] == heights[vertex] + 1:
                difference += promote(predecessor)
        heights[vertex] += 1
        return difference + len(lower[vertex]) - len(upper[vertex])

    if settings["promotion"] == "on":
        while True:
            rounds += 1
            accepted = 0
            for vertex in range(count):
                if not upper[vertex]:
                    continue
                saved = heights.copy()
                difference = promote(vertex)
                if difference < 0:
                    accepted += 1
                    record.append((rounds, vertex, difference))
                else:
                    heights[:] = saved
            if accepted == 0:
                break
    return heights, labels, dummies_before, rounds, record
