"""Exact integer mesh geometry, rational centroids and solid angles."""

import math
from fractions import Fraction


PI = 3.141592653589793


def subtract(a, b):
    return tuple(x - y for x, y in zip(a, b))


def cross(a, b):
    return (a[1] * b[2] - a[2] * b[1],
            a[2] * b[0] - a[0] * b[2],
            a[0] * b[1] - a[1] * b[0])


def dot(a, b):
    return sum(a[i] * b[i] for i in range(3))


def normal(face, points):
    a, b, c = (points[i] for i in face["vertices"])
    return cross(subtract(b, a), subtract(c, a))


def determinant(face, points):
    a, b, c = (points[i] for i in face["vertices"])
    return dot(a, cross(b, c))


def area(faces, points):
    total = 0.0
    for face in faces:
        n = normal(face, points)
        total += math.sqrt(dot(n, n))
    return total / 2


def triangle_angle(face, points):
    a, b, c = (points[i] for i in face["vertices"])
    products = (
        dot(subtract(b, a), subtract(c, a)),
        dot(subtract(c, b), subtract(a, b)),
        dot(subtract(a, c), subtract(b, c)),
    )
    smallest = min(products)
    return "obtuse" if smallest < 0 else "right" if smallest == 0 else "acute"


def edge_length_squared(edge, points):
    difference = subtract(points[edge[0]], points[edge[1]])
    return dot(difference, difference)


def winding_number(face_indices, faces, points, sample):
    total = 0.0
    for index in face_indices:
        a, b, c = [
            subtract(points[v], sample)
            for v in faces[index - 1]["vertices"]
        ]
        la = math.sqrt(dot(a, a))
        lb = math.sqrt(dot(b, b))
        lc = math.sqrt(dot(c, c))
        numerator = dot(a, cross(b, c))
        denominator = (
            la * lb * lc + dot(a, b) * lc
            + dot(b, c) * la + dot(c, a) * lb
        )
        total += 2 * math.atan2(numerator, denominator)
    return int(round(total / (4 * PI)))


def volume6(face_indices, faces, points):
    return sum(determinant(faces[index - 1], points) for index in face_indices)


def centroid(face_indices, faces, points, six_volume):
    coordinates = []
    for axis in range(3):
        numerator = 0
        for index in face_indices:
            face = faces[index - 1]
            signed = determinant(face, points)
            numerator += signed * sum(points[v][axis] for v in face["vertices"])
        coordinates.append(Fraction(numerator, 4 * six_volume))
    return tuple(coordinates)


def format_fraction(fraction):
    value = Fraction(fraction)
    if value.denominator == 1:
        return str(value.numerator)
    return f"{value.numerator}/{value.denominator}"


def format_real(value):
    result = f"{value:.3f}"
    return result[1:] if result.startswith("-") and float(result) == 0 else result


def bbox(vertices, points):
    locations = [points[i] for i in vertices]
    return (tuple(min(point[axis] for point in locations) for axis in range(3))
            + tuple(max(point[axis] for point in locations) for axis in range(3)))
