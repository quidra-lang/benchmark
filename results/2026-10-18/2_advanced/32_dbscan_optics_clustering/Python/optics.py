import math

from grid_index import squared_distance


INF = math.inf


def core_distances(points, neighborhoods, min_pts):
    distances = []
    for index, neighbors in enumerate(neighborhoods):
        if len(neighbors) < min_pts:
            distances.append(INF)
        else:
            values = sorted(squared_distance(points[index], points[other]) for other in neighbors)
            distances.append(values[min_pts - 1])
    return distances


def optics_ordering(points, neighborhoods, core):
    count = len(points)
    reach = [INF] * count
    predecessor = [None] * count
    processed = [False] * count
    ordering = []
    for start in range(count):
        if processed[start]:
            continue
        seeds = {start}
        while seeds:
            current = min(seeds, key=lambda index: (reach[index], points[index].id))
            seeds.remove(current)
            processed[current] = True
            ordering.append(current)
            if core[current] == INF:
                continue
            for other in neighborhoods[current]:
                if processed[other]:
                    continue
                distance = max(core[current], squared_distance(points[current], points[other]))
                if distance < reach[other]:
                    reach[other] = distance
                    predecessor[other] = current
                    seeds.add(other)
    return ordering, reach, predecessor
