import heapq
from math import inf, sqrt

from predicates import d2, dot


class DisjointSets:
    def __init__(self, size):
        self.parent = list(range(size + 1))
        self.size = [1] * (size + 1)
        self.count = size

    def find(self, site):
        while self.parent[site] != site:
            self.parent[site] = self.parent[self.parent[site]]
            site = self.parent[site]
        return site

    def union(self, first, second):
        first = self.find(first)
        second = self.find(second)
        if first == second:
            return False
        if self.size[first] < self.size[second]:
            first, second = second, first
        self.parent[second] = first
        self.size[first] += self.size[second]
        self.count -= 1
        return True


def nearest_neighbors(points, neighbors):
    nearest = [None] * len(points)
    for site in range(1, len(points)):
        nearest[site] = min(
            neighbors[site], key=lambda other: (d2(points[site], points[other]), other)
        )
    return nearest


def nearest_components(nearest):
    sets = DisjointSets(len(nearest) - 1)
    for site in range(1, len(nearest)):
        sets.union(site, nearest[site])
    groups = {}
    for site in range(1, len(nearest)):
        groups.setdefault(sets.find(site), []).append(site)
    return sorted(groups.values(), key=lambda group: group[0])


def kruskal(points, edges):
    sets = DisjointSets(len(points) - 1)
    ordered = sorted(edges, key=lambda edge: (d2(points[edge[0]], points[edge[1]]), *edge))
    adopted = []
    for first, second in ordered:
        if sets.union(first, second):
            adopted.append((first, second))
            if sets.count == 1:
                break
    return adopted


def is_gabriel(points, edge, directed):
    first, second = edge
    for direction in ((first, second), (second, first)):
        opposite = directed.get(direction)
        if opposite is not None and dot(points[opposite], points[first], points[second]) <= 0:
            return False
    return True


def is_relative_neighbor(points, edge):
    first, second = edge
    length2 = d2(points[first], points[second])
    for point in points[1:]:
        if d2(points[first], point) < length2 and d2(points[second], point) < length2:
            return False
    return True


def greedy_route(points, neighbors, start, target):
    route = [start]
    length = 0.0
    current = start
    while current != target:
        following = min(
            neighbors[current], key=lambda site: (d2(points[site], points[target]), site)
        )
        length += sqrt(d2(points[current], points[following]))
        route.append(following)
        current = following
    return route, length


def dijkstra(points, neighbors, start):
    distances = [inf] * len(points)
    previous = [None] * len(points)
    distances[start] = 0.0
    pending = [(0.0, start)]
    while pending:
        distance, site = heapq.heappop(pending)
        if distance != distances[site]:
            continue
        for other in neighbors[site]:
            candidate = distance + sqrt(d2(points[site], points[other]))
            if candidate < distances[other]:
                distances[other] = candidate
                previous[other] = site
                heapq.heappush(pending, (candidate, other))
    return distances, previous
