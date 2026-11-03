"""Ring containment, canonical ordering, result assembly and measurements."""

from math import sqrt

from intersections import on_segment
from rational import cross, point_key, real


def edges(ring):
    for index, point in enumerate(ring):
        yield point, ring[(index + 1) % len(ring)]


def inside(ring, point):
    parity = False
    for first, second in edges(ring):
        if (first[1] > point[1]) != (second[1] > point[1]):
            low, high = (first, second) if first[1] < second[1] else (second, first)
            if cross(low, high, point) > 0:
                parity = not parity
    return parity


def interior(ring_sequence, point):
    parity = False
    for ring in ring_sequence:
        if inside(ring, point):
            parity = not parity
    return parity


def boundary(ring, point):
    return any(on_segment(point, first, second) for first, second in edges(ring))


def rotate(ring):
    index = min(range(len(ring)), key=lambda position: point_key(ring[position]))
    return ring[index:] + ring[:index]


def counterclockwise(ring):
    return cross(ring[-1], ring[0], ring[1]) > 0


def reverse(ring):
    return ring[:1] + ring[:0:-1]


def normalize(ring, outer):
    result = rotate(ring)
    return result if counterclockwise(result) == outer else reverse(result)


def assemble(result_rings):
    rotated = [rotate(ring) for ring in result_rings]
    depths = [sum(inside(other, ring[0]) for other_index, other in enumerate(rotated)
                  if other_index != index) for index, ring in enumerate(rotated)]
    oriented = [ring if counterclockwise(ring) == (depth % 2 == 0) else reverse(ring)
                for ring, depth in zip(rotated, depths)]
    outer_indices = [index for index, depth in enumerate(depths) if depth % 2 == 0]
    outer_indices.sort(key=lambda index: point_key(oriented[index][0]))
    result = []
    for index in outer_indices:
        outer = oriented[index]
        holes = [ring for ring, depth in zip(oriented, depths)
                 if depth == depths[index] + 1 and inside(outer, ring[0])]
        holes.sort(key=lambda ring: point_key(ring[0]))
        result.append([outer, *holes])
    return result


def area(ring):
    total = 0.0
    for first, second in edges(ring):
        x1, y1 = real(first[0]), real(first[1])
        x2, y2 = real(second[0]), real(second[1])
        total += x1 * y2 - x2 * y1
    return total / 2.0


def perimeter(ring):
    total = 0.0
    for first, second in edges(ring):
        x1, y1 = real(first[0]), real(first[1])
        x2, y2 = real(second[0]), real(second[1])
        dx, dy = x2 - x1, y2 - y1
        total += sqrt(dx * dx + dy * dy)
    return total
