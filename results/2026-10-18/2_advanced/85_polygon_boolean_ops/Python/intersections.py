"""Exact segment predicates, proper crossings and clipping intersections."""

from rational import along, cross, divide


def on_segment(point, first, second):
    return (cross(first, second, point) == 0
            and min(first[0], second[0]) <= point[0] <= max(first[0], second[0])
            and min(first[1], second[1]) <= point[1] <= max(first[1], second[1]))


def touch(first, second, third, fourth):
    proper = (cross(first, second, third) * cross(first, second, fourth) < 0
              and cross(third, fourth, first) * cross(third, fourth, second) < 0)
    return (proper or on_segment(third, first, second)
            or on_segment(fourth, first, second)
            or on_segment(first, third, fourth)
            or on_segment(second, third, fourth))


def overlap(first, second, third, fourth):
    if cross(first, second, third) != 0 or cross(first, second, fourth) != 0:
        return False
    coordinate = 0 if first[0] != second[0] else 1
    a, b, c, d = (point[coordinate] for point in (first, second, third, fourth))
    return max(min(a, b), min(c, d)) < min(max(a, b), max(c, d))


def crossing(first, second, third, fourth):
    rx, ry = second[0] - first[0], second[1] - first[1]
    sx, sy = fourth[0] - third[0], fourth[1] - third[1]
    denominator = rx * sy - ry * sx
    if denominator == 0:
        return None
    gx, gy = third[0] - first[0], third[1] - first[1]
    first_numerator = gx * sy - gy * sx
    second_numerator = gx * ry - gy * rx
    if denominator < 0:
        denominator = -denominator
        first_numerator = -first_numerator
        second_numerator = -second_numerator
    if not (0 < first_numerator < denominator and 0 < second_numerator < denominator):
        return None
    first_position = divide(first_numerator, denominator)
    second_position = divide(second_numerator, denominator)
    return first_position, second_position, along(first, second, first_position)


def clipping_point(previous, current, previous_cross, current_cross):
    return along(previous, current, divide(previous_cross, previous_cross - current_cross))
