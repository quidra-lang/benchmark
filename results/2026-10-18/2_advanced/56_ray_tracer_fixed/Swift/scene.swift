import Foundation

struct Color {
    let r: Int
    let g: Int
    let b: Int
    init(_ r: Int = 0, _ g: Int = 0, _ b: Int = 0) { self.r = r; self.g = g; self.b = b }
    subscript(_ axis: Int) -> Int { axis == 0 ? r : axis == 1 ? g : b }
    var text: String { "\(r) \(g) \(b)" }
}
struct Checker { let alternate: Color; let size: Int }
final class Material {
    let name: String
    let color: Color
    let diffuse: Int
    let specular: Int
    let exponent: Int
    let reflection: Int
    let transmission: Int
    let ior: Int
    var checker: Checker?
    init(_ name: String, _ values: [Int]) { self.name = name; color = Color(values[0], values[1], values[2]); diffuse = values[3]; specular = values[4]; exponent = values[5]; reflection = values[6]; transmission = values[7]; ior = values[8] }
}
struct Bounds { let low: Vector3; let high: Vector3; var text: String { low.text + " " + high.text } }
enum ObjectGeometry { case sphere(Vector3, Int), plane(Vector3, Vector3), box(Bounds) }
final class SceneObject {
    let number: Int
    let label: String
    let material: Material
    let geometry: ObjectGeometry
    var bounds: Bounds?
    var leafDepth: Int?
    var kind: String { switch geometry { case .sphere: return "sphere"; case .plane: return "plane"; case .box: return "box" } }
    init(_ number: Int, _ label: String, _ material: Material, _ geometry: ObjectGeometry) { self.number = number; self.label = label; self.material = material; self.geometry = geometry }
}
enum LightGeometry { case point(Vector3), spot(Vector3, Vector3, Int, Int), sun(Vector3), area(Vector3, Vector3, Vector3, Int) }
struct Light {
    let number: Int
    let intensity: Int
    let geometry: LightGeometry
    var kind: String { switch geometry { case .point: return "point"; case .spot: return "spot"; case .sun: return "sun"; case .area: return "area" } }
    var samples: Int { if case .area(_, _, _, let count) = geometry { return count * count }; return 1 }
}
struct Fog { let color: Color; let start: Int; let end: Int }
final class Scene {
    var materials: [String: Material] = [:]
    var objects: [SceneObject] = []
    var lights: [Light] = []
    var eye = Vector3()
    var forward = Vector3()
    var right = Vector3()
    var up = Vector3()
    var halfWidth = 0
    var halfHeight = 0
    var background = Color()
    var ambient = 0
    var fog: Fog?
    init() throws {
        let lines = try String(contentsOfFile: "input/scene.txt", encoding: .ascii).split(separator: "\n").map(String.init)
        for line in lines where !line.hasPrefix("#") {
            let words = line.components(separatedBy: " "), kind = words[0]
            if kind == "material" { materials[words[1]] = Material(words[1], words.dropFirst(2).map { Int($0)! }); continue }
            if kind == "checker" { let v = words.dropFirst(2).map { Int($0)! }; materials[words[1]]!.checker = Checker(alternate: Color(v[0], v[1], v[2]), size: v[3]); continue }
            if ["sphere", "plane", "box"].contains(kind) {
                let v = words.dropFirst(3).map { Int($0)! }, position = Vector3(v[0], v[1], v[2]), geometry: ObjectGeometry
                if kind == "sphere" { geometry = .sphere(position, v[3]) }
                else if kind == "plane" { geometry = .plane(position, normalized(Vector3(v[3], v[4], v[5]))) }
                else { geometry = .box(Bounds(low: position, high: Vector3(v[3], v[4], v[5]))) }
                objects.append(SceneObject(objects.count + 1, words[1], materials[words[2]]!, geometry)); continue
            }
            let v = words.dropFirst().map { Int($0)! }
            func vector(_ offset: Int = 0) -> Vector3 { Vector3(v[offset], v[offset + 1], v[offset + 2]) }
            switch kind {
            case "eye": eye = vector()
            case "forward": forward = vector()
            case "right": right = vector()
            case "up": up = vector()
            case "view": halfWidth = v[0]; halfHeight = v[1]
            case "background": background = Color(v[0], v[1], v[2])
            case "ambient": ambient = v[0]
            case "fog": fog = Fog(color: Color(v[0], v[1], v[2]), start: v[3], end: v[4])
            case "point": lights.append(Light(number: lights.count + 1, intensity: v[3], geometry: .point(vector())))
            case "spot": lights.append(Light(number: lights.count + 1, intensity: v[8], geometry: .spot(vector(), normalized(vector(3)), v[6], v[7])))
            case "sun": lights.append(Light(number: lights.count + 1, intensity: v[3], geometry: .sun(normalized(-vector()))))
            default: lights.append(Light(number: lights.count + 1, intensity: v[10], geometry: .area(vector(), vector(3), vector(6), v[9])))
            }
        }
    }
}
