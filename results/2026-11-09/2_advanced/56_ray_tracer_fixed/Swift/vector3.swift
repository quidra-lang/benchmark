import Foundation

struct Vector3 {
    let x: Int
    let y: Int
    let z: Int
    init(_ x: Int = 0, _ y: Int = 0, _ z: Int = 0) { self.x = x; self.y = y; self.z = z }
    subscript(_ axis: Int) -> Int { axis == 0 ? x : axis == 1 ? y : z }
    var text: String { "\(x) \(y) \(z)" }
    static func + (a: Vector3, b: Vector3) -> Vector3 { Vector3(a.x + b.x, a.y + b.y, a.z + b.z) }
    static func - (a: Vector3, b: Vector3) -> Vector3 { Vector3(a.x - b.x, a.y - b.y, a.z - b.z) }
    static prefix func - (a: Vector3) -> Vector3 { Vector3(-a.x, -a.y, -a.z) }
}
func dot(_ a: Vector3, _ b: Vector3) -> Int { floorDivide(a.x * b.x + a.y * b.y + a.z * b.z, scale) }
func scaled(_ v: Vector3, _ amount: Int) -> Vector3 { Vector3(floorDivide(v.x * amount, scale), floorDivide(v.y * amount, scale), floorDivide(v.z * amount, scale)) }
func length(_ v: Vector3) -> Int { integerSquareRoot(v.x * v.x + v.y * v.y + v.z * v.z) }
func normalized(_ v: Vector3) -> Vector3 { let magnitude = length(v); return Vector3(floorDivide(v.x * scale, magnitude), floorDivide(v.y * scale, magnitude), floorDivide(v.z * scale, magnitude)) }
