from math import sqrt


def norm(values, nodes):
    squares = 0.0
    for node in nodes:
        squares += values[node] * values[node]
    return sqrt(squares)


def hits(count, nodes, links, iterations):
    sources = [[] for _ in range(count)]
    targets = [[] for _ in range(count)]
    for source, target in sorted(links):
        sources[target].append(source)
        targets[source].append(target)
    authority = [0.0] * count
    hub = [0.0] * count
    for node in nodes:
        authority[node] = 1.0
        hub[node] = 1.0
    for _ in range(iterations):
        incoming = [0.0] * count
        for node in nodes:
            for source in sources[node]:
                incoming[node] += hub[source]
        outgoing = [0.0] * count
        for node in nodes:
            for target in targets[node]:
                outgoing[node] += incoming[target]
        authority_norm = norm(incoming, nodes)
        hub_norm = norm(outgoing, nodes)
        for node in nodes:
            authority[node] = incoming[node] / authority_norm
            hub[node] = outgoing[node] / hub_norm
    return authority, hub
