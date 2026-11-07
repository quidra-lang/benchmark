from collections import deque


def strong_components(adjacency):
    count = len(adjacency)
    order = [-1] * count
    low = [0] * count
    on_stack = [False] * count
    stack = []
    components = []
    counter = 0
    for root in range(count):
        if order[root] != -1:
            continue
        order[root] = low[root] = counter
        counter += 1
        stack.append(root)
        on_stack[root] = True
        work = [(root, 0)]
        while work:
            node, position = work[-1]
            if position < len(adjacency[node]):
                work[-1] = (node, position + 1)
                child = adjacency[node][position]
                if order[child] == -1:
                    order[child] = low[child] = counter
                    counter += 1
                    stack.append(child)
                    on_stack[child] = True
                    work.append((child, 0))
                elif on_stack[child]:
                    low[node] = min(low[node], order[child])
                continue
            work.pop()
            if work:
                parent = work[-1][0]
                low[parent] = min(low[parent], low[node])
            if low[node] == order[node]:
                component = []
                while True:
                    member = stack.pop()
                    on_stack[member] = False
                    component.append(member)
                    if member == node:
                        break
                components.append(component)
    return components


def reachable(adjacency, starts):
    seen = [False] * len(adjacency)
    stack = []
    for start in starts:
        if not seen[start]:
            seen[start] = True
            stack.append(start)
    while stack:
        node = stack.pop()
        for neighbor in adjacency[node]:
            if not seen[neighbor]:
                seen[neighbor] = True
                stack.append(neighbor)
    return seen


def bfs_distances(adjacency, sources):
    distance = [-1] * len(adjacency)
    queue = deque()
    for source in sources:
        if distance[source] == -1:
            distance[source] = 0
            queue.append(source)
    while queue:
        node = queue.popleft()
        for neighbor in adjacency[node]:
            if distance[neighbor] == -1:
                distance[neighbor] = distance[node] + 1
                queue.append(neighbor)
    return distance


def weak_components(neighbors):
    labels = [-1] * len(neighbors)
    count = 0
    for start in range(len(neighbors)):
        if labels[start] != -1:
            continue
        labels[start] = count
        stack = [start]
        while stack:
            node = stack.pop()
            for neighbor in neighbors[node]:
                if labels[neighbor] == -1:
                    labels[neighbor] = count
                    stack.append(neighbor)
        count += 1
    return labels
