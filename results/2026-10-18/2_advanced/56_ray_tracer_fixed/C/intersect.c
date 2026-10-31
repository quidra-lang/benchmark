#include "renderer.h"
Slab slab(Bounds bounds, Ray ray) {
    Slab out = {.near = INT64_MIN, .far = INT64_MAX, .valid = true};
    for (int axis = 0; axis < 3; ++axis) {
        if (!ray.direction.data[axis]) {
            if (ray.origin.data[axis] < bounds.lo.data[axis] || ray.origin.data[axis] > bounds.hi.data[axis])
                return (Slab){0};
            continue;
        }
        I a = floor_div((bounds.lo.data[axis] - ray.origin.data[axis]) * SCALE, ray.direction.data[axis]),
          b = floor_div((bounds.hi.data[axis] - ray.origin.data[axis]) * SCALE, ray.direction.data[axis]),
          entry = a < b ? a : b, exit = a > b ? a : b;
        if (entry > out.near) {
            out.near = entry;
            out.near_axis = axis;
        }
        if (exit < out.far) {
            out.far = exit;
            out.far_axis = axis;
        }
    }
    if (out.near > out.far)
        out.valid = false;
    return out;
}
Candidate intersect(Object object, Ray ray, I epsilon) {
    if (object.kind == SPHERE) {
        Vec oc = sub(ray.origin, object.first);
        I b = dot(oc, ray.direction), tc = floor_div(-b * SCALE, dot(ray.direction, ray.direction));
        Vec h = add(oc, sc(ray.direction, tc));
        I q = floor_div(object.radius * object.radius, SCALE) - dot(h, h);
        if (q < 0)
            return (Candidate){0};
        I width = floor_div(isqrt(q * SCALE) * SCALE, length(ray.direction)), first = tc - width,
          second = tc + width;
        if (first > epsilon)
            return (Candidate){.distance = first, .valid = true};
        if (second > epsilon)
            return (Candidate){.distance = second, .valid = true};
        return (Candidate){0};
    }
    if (object.kind == PLANE) {
        I denominator = dot(ray.direction, object.second);
        if (!denominator)
            return (Candidate){0};
        I distance = floor_div(dot(sub(object.first, ray.origin), object.second) * SCALE, denominator);
        return (Candidate){.distance = distance, .valid = distance > epsilon};
    }
    Slab hit = slab((Bounds){object.first, object.second}, ray);
    if (!hit.valid)
        return (Candidate){0};
    if (hit.near > epsilon)
        return (Candidate){.distance = hit.near, .entering = true, .axis = hit.near_axis, .valid = true};
    if (hit.far > epsilon)
        return (Candidate){.distance = hit.far, .axis = hit.far_axis, .valid = true};
    return (Candidate){0};
}
Vec outward_normal(Object object, Ray ray, Vec point, Candidate hit) {
    if (object.kind == SPHERE)
        return norm(sub(point, object.first));
    if (object.kind == PLANE)
        return object.second;
    Vec out = {0};
    I sign = hit.entering ? (ray.direction.data[hit.axis] > 0 ? -1 : 1)
                          : (ray.direction.data[hit.axis] > 0 ? 1 : -1);
    out.data[hit.axis] = sign * SCALE;
    return out;
}
Bounds bounds(Object object, I pad) {
    Bounds out;
    for (int axis = 0; axis < 3; ++axis) {
        if (object.kind == SPHERE) {
            out.lo.data[axis] = object.first.data[axis] - object.radius - pad;
            out.hi.data[axis] = object.first.data[axis] + object.radius + pad;
        } else {
            out.lo.data[axis] = object.first.data[axis] - pad;
            out.hi.data[axis] = object.second.data[axis] + pad;
        }
    }
    return out;
}
