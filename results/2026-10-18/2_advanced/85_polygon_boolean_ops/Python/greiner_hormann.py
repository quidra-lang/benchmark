"""Crossing insertion, classification and Greiner-Hormann traversal."""

from intersections import crossing
from rings import edges, interior


class Node:
    def __init__(self, point, side, crossing_record=None):
        self.point = point
        self.side = side
        self.crossing = crossing_record
        self.entering = False
        self.next = self.previous = self.other = None


class Crossing:
    def __init__(self, point):
        self.point = point
        self.first = Node(point, 0, self)
        self.second = Node(point, 1, self)
        self.first.other = self.second
        self.second.other = self.first


class Graph:
    def __init__(self, first, second):
        self.rings = first, second
        slots = [[[[] for point in ring] for ring in sequence] for sequence in self.rings]
        for first_ring, ring in enumerate(first):
            for first_edge, (a, b) in enumerate(edges(ring)):
                for second_ring, other in enumerate(second):
                    for second_edge, (c, d) in enumerate(edges(other)):
                        found = crossing(a, b, c, d)
                        if found is None:
                            continue
                        first_position, second_position, point = found
                        record = Crossing(point)
                        slots[0][first_ring][first_edge].append((first_position, record.first))
                        slots[1][second_ring][second_edge].append((second_position, record.second))
        self.nodes = [[], []]
        self.initial_inside = [[], []]
        for side, sequence in enumerate(self.rings):
            for ring_index, ring in enumerate(sequence):
                nodes = []
                for edge_index, point in enumerate(ring):
                    nodes.append(Node(point, side))
                    inserted = sorted(slots[side][ring_index][edge_index], key=lambda item: item[0])
                    nodes.extend(node for position, node in inserted)
                for index, node in enumerate(nodes):
                    node.previous = nodes[index - 1]
                    node.next = nodes[(index + 1) % len(nodes)]
                state = interior(self.rings[1 - side], ring[0])
                self.initial_inside[side].append(state)
                for node in nodes:
                    if node.crossing is not None:
                        node.entering = not state
                        state = not state
                self.nodes[side].append(nodes)
        self.crossings = [node.crossing for nodes in self.nodes[0] for node in nodes
                          if node.crossing is not None]
        self.n_a = sum(self.initial_inside[0])
        self.n_b = sum(self.initial_inside[1])

    def traverse(self, invert_first, invert_second):
        inverted = invert_first, invert_second
        visited = set()
        result = []
        for start in self.crossings:
            if start in visited:
                continue
            points = []
            current = start.first
            while True:
                visited.add(current.crossing)
                points.append(current.point)
                forward = current.entering != inverted[current.side]
                stopped = current.next if forward else current.previous
                while stopped.crossing is None:
                    points.append(stopped.point)
                    stopped = stopped.next if forward else stopped.previous
                if stopped.crossing is start:
                    break
                current = stopped.other
            result.append(points)
        for side, sequence in enumerate(self.rings):
            for index, ring in enumerate(sequence):
                if any(node.crossing is not None for node in self.nodes[side][index]):
                    continue
                if self.initial_inside[side][index] != inverted[side]:
                    result.append(list(ring))
        return result
