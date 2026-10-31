import Foundation

struct SlabInterval { let near: Int; let nearAxis: Int; let far: Int; let farAxis: Int }
struct Intersection { let distance: Int; let entering: Bool?; let axis: Int? }
func slab(_ bounds: Bounds, _ origin: Vector3, _ direction: Vector3) -> SlabInterval? {
    var near: Int?, far: Int?, nearAxis = 0, farAxis = 0
    for axis in 0..<3 {
        if direction[axis] == 0 { if origin[axis] < bounds.low[axis] || origin[axis] > bounds.high[axis] { return nil }; continue }
        let a = floorDivide((bounds.low[axis] - origin[axis]) * scale, direction[axis]), b = floorDivide((bounds.high[axis] - origin[axis]) * scale, direction[axis]), entry = min(a, b), exit = max(a, b)
        if near == nil || entry > near! { near = entry; nearAxis = axis }
        if far == nil || exit < far! { far = exit; farAxis = axis }
    }
    if near! > far! { return nil }
    return SlabInterval(near: near!, nearAxis: nearAxis, far: far!, farAxis: farAxis)
}
func candidate(_ object: SceneObject, _ origin: Vector3, _ direction: Vector3, _ epsilon: Int) -> Intersection? {
    switch object.geometry {
    case .sphere(let center, let radius):
        let offset = origin - center, b = dot(offset, direction), middle = floorDivide(-b * scale, dot(direction, direction)), h = offset + scaled(direction, middle), q = floorDivide(radius * radius, scale) - dot(h, h)
        if q < 0 { return nil }
        let width = floorDivide(integerSquareRoot(q * scale) * scale, length(direction)), first = middle - width, second = middle + width, distance = first > epsilon ? first : second
        return distance > epsilon ? Intersection(distance: distance, entering: nil, axis: nil) : nil
    case .plane(let point, let normal):
        let denominator = dot(direction, normal)
        if denominator == 0 { return nil }
        let distance = floorDivide(dot(point - origin, normal) * scale, denominator)
        return distance > epsilon ? Intersection(distance: distance, entering: nil, axis: nil) : nil
    case .box(let bounds):
        guard let interval = slab(bounds, origin, direction) else { return nil }
        if interval.near > epsilon { return Intersection(distance: interval.near, entering: true, axis: interval.nearAxis) }
        if interval.far > epsilon { return Intersection(distance: interval.far, entering: false, axis: interval.farAxis) }
        return nil
    }
}
func outwardNormal(_ object: SceneObject, _ point: Vector3, _ direction: Vector3, _ intersection: Intersection) -> Vector3 {
    switch object.geometry {
    case .sphere(let center, _): return normalized(point - center)
    case .plane(_, let normal): return normal
    case .box:
        let axis = intersection.axis!, sign = (direction[axis] > 0 ? 1 : -1) * (intersection.entering! ? -1 : 1)
        return Vector3(axis == 0 ? sign * scale : 0, axis == 1 ? sign * scale : 0, axis == 2 ? sign * scale : 0)
    }
}
func boundingBox(_ object: SceneObject, _ margin: Int) -> Bounds? {
    switch object.geometry {
    case .plane: return nil
    case .sphere(let center, let radius): let pad = Vector3(radius + margin, radius + margin, radius + margin); return Bounds(low: center - pad, high: center + pad)
    case .box(let bounds): let pad = Vector3(margin, margin, margin); return Bounds(low: bounds.low - pad, high: bounds.high + pad)
    }
}
