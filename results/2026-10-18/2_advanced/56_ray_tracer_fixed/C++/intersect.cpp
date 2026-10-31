#include "renderer.hpp"
std::optional<Slab> slab(Bounds bounds, Ray ray) {
    Slab out{std::numeric_limits<I>::min(), std::numeric_limits<I>::max(), 0, 0};
    for (int axis = 0; axis < 3; ++axis) {
        if (ray.direction[axis] == 0) {
            if (ray.origin[axis] < bounds.lo[axis] || ray.origin[axis] > bounds.hi[axis])
                return {};
            continue;
        }
        const I a = floor_div((bounds.lo[axis] - ray.origin[axis]) * scale, ray.direction[axis]),
                b = floor_div((bounds.hi[axis] - ray.origin[axis]) * scale, ray.direction[axis]),
                entry = std::min(a, b), exit = std::max(a, b);
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
        return {};
    return out;
}
std::optional<Candidate> intersect(const Object &object, Ray ray, I epsilon) {
    if (object.kind == ObjectKind::sphere) {
        const Vec oc = sub(ray.origin, object.first);
        const I b = dot(oc, ray.direction), tc = floor_div(-b * scale, dot(ray.direction, ray.direction));
        const Vec h = add(oc, sc(ray.direction, tc));
        const I q = floor_div(object.radius * object.radius, scale) - dot(h, h);
        if (q < 0)
            return {};
        const I width = floor_div(isqrt(q * scale) * scale, length(ray.direction)), first = tc - width,
                second = tc + width;
        if (first > epsilon)
            return Candidate{first};
        if (second > epsilon)
            return Candidate{second};
        return {};
    }
    if (object.kind == ObjectKind::plane) {
        const I denominator = dot(ray.direction, object.second);
        if (denominator == 0)
            return {};
        const I distance = floor_div(dot(sub(object.first, ray.origin), object.second) * scale, denominator);
        return distance > epsilon ? std::optional<Candidate>(Candidate{distance}) : std::nullopt;
    }
    const auto hit = slab({object.first, object.second}, ray);
    if (!hit)
        return {};
    if (hit->near > epsilon)
        return Candidate{hit->near, true, hit->near_axis};
    if (hit->far > epsilon)
        return Candidate{hit->far, false, hit->far_axis};
    return {};
}
Vec outward_normal(const Object &object, Ray ray, Vec point, const Candidate &hit) {
    if (object.kind == ObjectKind::sphere)
        return norm(sub(point, object.first));
    if (object.kind == ObjectKind::plane)
        return object.second;
    Vec out{};
    const I sign =
        hit.entering ? (ray.direction[hit.axis] > 0 ? -1 : 1) : (ray.direction[hit.axis] > 0 ? 1 : -1);
    out[hit.axis] = sign * scale;
    return out;
}
Bounds bounds(const Object &object, I pad) {
    Bounds out;
    for (int axis = 0; axis < 3; ++axis) {
        if (object.kind == ObjectKind::sphere) {
            out.lo[axis] = object.first[axis] - object.radius - pad;
            out.hi[axis] = object.first[axis] + object.radius + pad;
        } else {
            out.lo[axis] = object.first[axis] - pad;
            out.hi[axis] = object.second[axis] + pad;
        }
    }
    return out;
}
