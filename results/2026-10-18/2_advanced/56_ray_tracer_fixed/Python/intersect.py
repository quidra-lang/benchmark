"""Integer slab and primitive intersections, outward normals and bounds."""

from fixed_point import S, isqrt
from vector3 import add, dot, length, norm, sc, sub


def slab(lo, hi, origin, direction):
    near = far = None
    near_axis = far_axis = None
    for axis in range(3):
        component = direction[axis]
        if component == 0:
            if origin[axis] < lo[axis] or origin[axis] > hi[axis]:
                return None
            continue
        a = (lo[axis] - origin[axis]) * S // component
        b = (hi[axis] - origin[axis]) * S // component
        entry, leave = min(a, b), max(a, b)
        if near is None or entry > near:
            near, near_axis = entry, axis
        if far is None or leave < far:
            far, far_axis = leave, axis
    if near > far:
        return None
    return near, near_axis, far, far_axis


def candidate(obj, origin, direction, epsilon):
    kind = obj["kind"]
    if kind == "sphere":
        oc = sub(origin, obj["center"])
        b = dot(oc, direction)
        center_t = -b * S // dot(direction, direction)
        h = add(oc, sc(direction, center_t))
        q = obj["radius"] ** 2 // S - dot(h, h)
        if q < 0:
            return None
        width = isqrt(q * S) * S // length(direction)
        first, second = center_t - width, center_t + width
        distance = first if first > epsilon else second
        return (distance, None, None) if distance > epsilon else None
    if kind == "plane":
        denominator = dot(direction, obj["normal"])
        if denominator == 0:
            return None
        distance = dot(sub(obj["point"], origin), obj["normal"]) * S // denominator
        return (distance, None, None) if distance > epsilon else None
    interval = slab(obj["lo"], obj["hi"], origin, direction)
    if interval is None:
        return None
    near, near_axis, far, far_axis = interval
    if near > epsilon:
        return near, True, near_axis
    if far > epsilon:
        return far, False, far_axis
    return None


def outward_normal(obj, point, direction, intersection):
    if obj["kind"] == "sphere":
        return norm(sub(point, obj["center"]))
    if obj["kind"] == "plane":
        return obj["normal"]
    _, entering, axis = intersection
    sign = 1 if direction[axis] > 0 else -1
    if entering:
        sign = -sign
    return tuple(sign * S if a == axis else 0 for a in range(3))


def bounds(obj, margin):
    if obj["kind"] == "plane":
        return None
    if obj["kind"] == "sphere":
        radius = obj["radius"] + margin
        return (tuple(a - radius for a in obj["center"]),
                tuple(a + radius for a in obj["center"]))
    return (tuple(a - margin for a in obj["lo"]),
            tuple(a + margin for a in obj["hi"]))
