import Foundation

func baseColor(_ material: Material, _ point: Vector3) -> Color {
    if let checker = material.checker { let cell = floorDivide(point.x, checker.size) + floorDivide(point.y, checker.size) + floorDivide(point.z, checker.size); if cell % 2 != 0 { return checker.alternate } }
    return material.color
}
func phong(_ material: Material, _ normal: Vector3, _ light: Vector3, _ view: Vector3, _ ndl: Int, _ intensity: Int, _ factor: Int) -> (diffuse: Int, specular: Int) {
    let effective = multiply(intensity, factor), diffuse = multiply(multiply(material.diffuse, ndl), effective), reflectedLight = scaled(normal, 2 * ndl) - light, rv = dot(reflectedLight, view)
    var specular = 0
    if rv > 0 { var power = scale; for _ in 0..<material.exponent { power = multiply(power, rv) }; specular = multiply(multiply(material.specular, power), effective) }
    return (diffuse, specular)
}
func reflected(_ direction: Vector3, _ normal: Vector3) -> Vector3 { normalized(direction - scaled(normal, 2 * dot(direction, normal))) }
struct Refraction { let reflection: Int; let transmission: Int; let direction: Vector3?; let internalReflection: Bool }
func refraction(_ material: Material, _ direction: Vector3, _ normal: Vector3, _ front: Bool) -> Refraction {
    if material.transmission == 0 { return Refraction(reflection: material.reflection, transmission: 0, direction: nil, internalReflection: false) }
    let eta = front ? floorDivide(scale * scale, material.ior) : material.ior, cosine = -dot(direction, normal), discriminant = scale * scale - floorDivide(multiply(eta, eta) * (scale * scale - cosine * cosine), scale)
    if discriminant < 0 { return Refraction(reflection: material.reflection + material.transmission, transmission: 0, direction: nil, internalReflection: true) }
    let transmitted = normalized(scaled(direction, eta) + scaled(normal, multiply(eta, cosine) - integerSquareRoot(discriminant)))
    let r0 = floorDivide((material.ior - scale) * scale, material.ior + scale), reflectance = multiply(r0, r0), x = scale - min(cosine, scale)
    var power = scale
    for _ in 0..<5 { power = multiply(power, x) }
    let fresnel = reflectance + multiply(scale - reflectance, power), transfer = multiply(material.transmission, fresnel)
    return Refraction(reflection: material.reflection + transfer, transmission: material.transmission - transfer, direction: transmitted, internalReflection: false)
}
func mix(_ values: [(color: Color, weight: Int)]) -> Color {
    let components = (0..<3).map { axis in values.reduce(0) { $0 + floorDivide($1.color[axis] * $1.weight, scale) } }
    return Color(components[0], components[1], components[2])
}
