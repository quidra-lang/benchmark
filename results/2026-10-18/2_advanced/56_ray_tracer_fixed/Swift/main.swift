import Foundation

struct RenderSettings {
    let width: Int
    let height: Int
    let contrast: Int
    let maximumDepth: Int
    let far: Int
    let epsilon: Int
    let margin: Int
}
func inputLines(_ filename: String) throws -> [String] { try String(contentsOfFile: "input/" + filename, encoding: .ascii).split(separator: "\n").map(String.init) }
func readSettings() throws -> RenderSettings {
    let values = Dictionary(uniqueKeysWithValues: try inputLines("render.txt").map { line in let words = line.components(separatedBy: " "); return (words[0], words.dropFirst().map { Int($0)! }) })
    return RenderSettings(width: values["size"]![0], height: values["size"]![1], contrast: values["contrast"]![0], maximumDepth: values["depth"]![0], far: values["far"]![0], epsilon: values["epsilon"]![0], margin: values["pad"]![0])
}
func integerText(_ values: [Int]) -> String { values.map(String.init).joined(separator: " ") }
func writeLines(_ filename: String, _ lines: [String]) throws {
    try FileManager.default.createDirectory(atPath: "output", withIntermediateDirectories: true)
    let text = lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"
    try text.write(toFile: "output/" + filename, atomically: false, encoding: .ascii)
}
enum RayKind: Int, CaseIterable { case primary, reflection, refraction, shadow; var text: String { ["primary", "reflection", "refraction", "shadow"][rawValue] } }
final class BVHNode {
    let bounds: Bounds
    let depth: Int
    var visits = 0
    var objects: [SceneObject]?
    var left: BVHNode?
    var right: BVHNode?
    init(_ bounds: Bounds, _ depth: Int) { self.bounds = bounds; self.depth = depth }
}
func unionBox(_ objects: [SceneObject]) -> Bounds {
    let low = (0..<3).map { axis in objects.map { $0.bounds!.low[axis] }.min()! }, high = (0..<3).map { axis in objects.map { $0.bounds!.high[axis] }.max()! }
    return Bounds(low: Vector3(low[0], low[1], low[2]), high: Vector3(high[0], high[1], high[2]))
}
func surfaceCost(_ objects: [SceneObject]) -> Int { let bounds = unionBox(objects), d = bounds.high - bounds.low; return (d.x * d.y + d.y * d.z + d.z * d.x) * objects.count }
struct NearestHit { let object: SceneObject; let intersection: Intersection }
struct Lighting { let lit: Int; let diffuse: Int; let specular: Int }
struct HitInfo {
    let object: SceneObject
    let distance: Int
    let point: Vector3
    let normal: Vector3
    let front: Bool
    let base: Color
    var lighting: [Lighting] = []
    var illumination: Int { lighting.filter { $0.lit > 0 }.count }
}
struct TraceResult { let color: Color; let hit: HitInfo? }
final class Pixel {
    let x: Int
    let y: Int
    var rays = 0
    var depth = 0
    var samples = 1
    var label = "."
    var center = Color()
    var color = Color()
    var hit: HitInfo?
    init(_ x: Int, _ y: Int) { self.x = x; self.y = y }
}
final class TraceLog { var lines: [String] = [] }
struct TestCounts { var nodes = 0; var objects = 0 }
struct ObjectCounts { var primary = 0; var secondary = 0; var shadow = 0 }
struct LightCounts { var pixels = 0; var shadowRays = 0; var blocked = 0; var attenuated = 0; var backfacing = 0; var outside = 0 }
struct LightSample { let direction: Vector3; let distance: Int; let intensity: Int }
final class Renderer {
    let scene: Scene
    let settings: RenderSettings
    let planes: [SceneObject]
    var root: BVHNode?
    var nodes: [BVHNode] = []
    var rays = Array(repeating: 0, count: 4)
    var misses = Array(repeating: 0, count: 3)
    var depthCounts: [Int]
    var tests = Array(repeating: TestCounts(), count: 4)
    var objectCounts: [ObjectCounts]
    var lightCounts: [LightCounts]
    var internalReflections = 0
    var clamped = 0
    var supersampled = 0
    var pixels: [Pixel] = []
    init(_ scene: Scene, _ settings: RenderSettings) {
        self.scene = scene; self.settings = settings; planes = scene.objects.filter { $0.kind == "plane" }
        depthCounts = Array(repeating: 0, count: settings.maximumDepth + 1); objectCounts = Array(repeating: ObjectCounts(), count: scene.objects.count); lightCounts = Array(repeating: LightCounts(), count: scene.lights.count)
        for object in scene.objects { object.bounds = boundingBox(object, settings.margin) }
        let bounded = scene.objects.filter { $0.bounds != nil }
        if !bounded.isEmpty { root = buildBVH(bounded, 0) }
    }
    func buildBVH(_ objects: [SceneObject], _ depth: Int) -> BVHNode {
        let node = BVHNode(unionBox(objects), depth)
        nodes.append(node)
        if objects.count <= 2 { node.objects = objects.sorted { $0.number < $1.number }; for object in objects { object.leafDepth = depth }; return node }
        var bestCost: Int?, groups: ([SceneObject], [SceneObject])?
        for axis in 0..<3 {
            let ordered = objects.sorted {
                let a = floorDivide($0.bounds!.low[axis] + $0.bounds!.high[axis], 2), b = floorDivide($1.bounds!.low[axis] + $1.bounds!.high[axis], 2)
                return a == b ? $0.number < $1.number : a < b
            }
            for split in 1..<ordered.count {
                let left = Array(ordered.prefix(split)), right = Array(ordered.dropFirst(split)), cost = surfaceCost(left) + surfaceCost(right)
                if bestCost == nil || cost < bestCost! { bestCost = cost; groups = (left, right) }
            }
        }
        node.left = buildBVH(groups!.0, depth + 1); node.right = buildBVH(groups!.1, depth + 1)
        return node
    }
    func testNode(_ node: BVHNode, _ origin: Vector3, _ direction: Vector3, _ kind: RayKind, _ counted: Bool) -> Int? {
        if counted { tests[kind.rawValue].nodes += 1; node.visits += 1 }
        guard let interval = slab(node.bounds, origin, direction), interval.far > settings.epsilon else { return nil }
        return interval.near
    }
    func testObject(_ object: SceneObject, _ origin: Vector3, _ direction: Vector3, _ kind: RayKind, _ counted: Bool) -> Intersection? {
        if counted { tests[kind.rawValue].objects += 1 }
        return candidate(object, origin, direction, settings.epsilon)
    }
    func nearest(_ origin: Vector3, _ direction: Vector3, _ kind: RayKind = .primary, _ counted: Bool = false) -> NearestHit? {
        var best: NearestHit?
        func consider(_ object: SceneObject) {
            guard let intersection = testObject(object, origin, direction, kind, counted), intersection.distance <= settings.far else { return }
            if best == nil || intersection.distance < best!.intersection.distance || (intersection.distance == best!.intersection.distance && object.number < best!.object.number) { best = NearestHit(object: object, intersection: intersection) }
        }
        func visit(_ node: BVHNode) {
            guard let entry = testNode(node, origin, direction, kind, counted), entry <= settings.far else { return }
            if let best, entry > best.intersection.distance { return }
            if let objects = node.objects { for object in objects { consider(object) } } else { visit(node.left!); visit(node.right!) }
        }
        for plane in planes { consider(plane) }
        if let root { visit(root) }
        return best
    }
    func occluders(_ origin: Vector3, _ direction: Vector3, _ distance: Int, _ counted: Bool = false) -> [SceneObject] {
        var found: [SceneObject] = []
        func consider(_ object: SceneObject) {
            if let intersection = testObject(object, origin, direction, .shadow, counted), intersection.distance < distance { found.append(object); if counted { objectCounts[object.number - 1].shadow += 1 } }
        }
        func visit(_ node: BVHNode) {
            guard let entry = testNode(node, origin, direction, .shadow, counted), entry < distance else { return }
            if let objects = node.objects { for object in objects { consider(object) } } else { visit(node.left!); visit(node.right!) }
        }
        for plane in planes { consider(plane) }
        if let root { visit(root) }
        return found.sorted { $0.number < $1.number }
    }
    func cameraDirection(_ qx: Int, _ qy: Int) -> Vector3 {
        let u = floorDivide((qx - 2 * settings.width) * scene.halfWidth, 2 * settings.width), v = floorDivide((2 * settings.height - qy) * scene.halfHeight, 2 * settings.height)
        return normalized(scene.forward + scaled(scene.right, u) + scaled(scene.up, v))
    }
    func intersectionInfo(_ hit: NearestHit, _ origin: Vector3, _ direction: Vector3) -> HitInfo {
        let point = origin + scaled(direction, hit.intersection.distance), outward = outwardNormal(hit.object, point, direction, hit.intersection), front = dot(outward, direction) <= 0
        return HitInfo(object: hit.object, distance: hit.intersection.distance, point: point, normal: front ? outward : -outward, front: front, base: baseColor(hit.object.material, point))
    }
    func lightSamples(_ light: Light, _ point: Vector3) -> [LightSample] {
        var positions: [Vector3] = []
        switch light.geometry {
        case .sun(let direction): return [LightSample(direction: direction, distance: settings.far, intensity: light.intensity)]
        case .point(let position), .spot(let position, _, _, _): positions = [position]
        case .area(let position, let u, let v, let count):
            for j in 0..<count {
                for i in 0..<count {
                    let components = (0..<3).map { position[$0] + floorDivide((2 * i + 1) * u[$0], 2 * count) + floorDivide((2 * j + 1) * v[$0], 2 * count) }
                    positions.append(Vector3(components[0], components[1], components[2]))
                }
            }
        }
        let intensity = floorDivide(light.intensity, light.samples)
        return positions.map { let relative = $0 - point; return LightSample(direction: normalized(relative), distance: length(relative), intensity: intensity) }
    }
    func coneFactor(_ light: Light, _ direction: Vector3) -> Int {
        guard case .spot(_, let axis, let outer, let inner) = light.geometry else { return scale }
        let cosine = -dot(direction, axis)
        if cosine <= outer { return 0 }; if cosine >= inner { return scale }
        return floorDivide((cosine - outer) * scale, inner - outer)
    }
    func contribution(_ light: Light, _ sample: LightSample, _ info: HitInfo, _ view: Vector3, _ pixel: Pixel?) -> Lighting {
        let ndl = dot(info.normal, sample.direction), index = light.number - 1
        if ndl <= 0 { if pixel != nil { lightCounts[index].backfacing += 1 }; return Lighting(lit: 0, diffuse: 0, specular: 0) }
        var factor = coneFactor(light, sample.direction)
        if factor == 0 { if pixel != nil { lightCounts[index].outside += 1 }; return Lighting(lit: 0, diffuse: 0, specular: 0) }
        if let pixel { rays[RayKind.shadow.rawValue] += 1; pixel.rays += 1; lightCounts[index].shadowRays += 1 }
        let blockers = occluders(info.point, sample.direction, sample.distance, pixel != nil)
        for object in blockers { factor = multiply(factor, object.material.transmission) }
        if factor == 0 { if pixel != nil { lightCounts[index].blocked += 1 }; return Lighting(lit: 0, diffuse: 0, specular: 0) }
        if !blockers.isEmpty && pixel != nil { lightCounts[index].attenuated += 1 }
        let components = phong(info.object.material, info.normal, sample.direction, view, ndl, sample.intensity, factor)
        return Lighting(lit: 1, diffuse: components.diffuse, specular: components.specular)
    }
    func localColor(_ info: inout HitInfo, _ direction: Vector3, _ pixel: Pixel?) -> Color {
        var lighting: [Lighting] = []
        for light in scene.lights {
            var lit = 0, diffuse = 0, specular = 0
            for sample in lightSamples(light, info.point) { let result = contribution(light, sample, info, -direction, pixel); lit += result.lit; diffuse += result.diffuse; specular += result.specular }
            lighting.append(Lighting(lit: lit, diffuse: diffuse, specular: specular))
        }
        let diffuse = lighting.reduce(0) { $0 + $1.diffuse }, specular = lighting.reduce(0) { $0 + $1.specular }, raw = (0..<3).map { floorDivide(info.base[$0] * (scene.ambient + diffuse), scale) + floorDivide(255 * specular, scale) }
        if pixel != nil { clamped += raw.filter { $0 > 255 }.count }
        info.lighting = lighting
        return Color(min(raw[0], 255), min(raw[1], 255), min(raw[2], 255))
    }
    func applyFog(_ color: Color, _ distance: Int) -> Color {
        guard let fog = scene.fog else { return color }
        let factor = distance <= fog.start ? 0 : distance >= fog.end ? scale : floorDivide((distance - fog.start) * scale, fog.end - fog.start)
        return mix([(color, scale - factor), (fog.color, factor)])
    }
    func trace(_ origin: Vector3, _ direction: Vector3, kind: RayKind = .primary, depth: Int = 0, pixel: Pixel? = nil, record: TraceLog? = nil) -> TraceResult {
        if let pixel { rays[kind.rawValue] += 1; depthCounts[depth] += 1; pixel.rays += 1; pixel.depth = max(pixel.depth, depth) }
        record?.lines.append("ray \(kind.text) \(depth) origin \(origin.text) direction \(direction.text)")
        guard let hit = nearest(origin, direction, kind, pixel != nil) else {
            if pixel != nil { misses[kind.rawValue] += 1 }
            record?.lines += ["miss", "color " + scene.background.text]
            return TraceResult(color: scene.background, hit: nil)
        }
        var info = intersectionInfo(hit, origin, direction)
        if pixel != nil { if kind == .primary { objectCounts[info.object.number - 1].primary += 1 } else { objectCounts[info.object.number - 1].secondary += 1 } }
        let local = localColor(&info, direction, pixel)
        record?.lines.append("hit \(info.object.label) t \(info.distance) point \(info.point.text) normal \(info.normal.text) base \(info.base.text)")
        for (i, light) in scene.lights.enumerated() { let value = info.lighting[i]; record?.lines.append("light \(light.number) lit \(value.lit) of \(light.samples) diffuse \(value.diffuse) specular \(value.specular)") }
        record?.lines.append("local " + local.text)
        let material = info.object.material
        var color = local
        if depth < settings.maximumDepth && (material.reflection > 0 || material.transmission > 0) {
            let optical = refraction(material, direction, info.normal, info.front), localWeight = scale - material.reflection - material.transmission
            if optical.internalReflection { if pixel != nil { internalReflections += 1 }; record?.lines.append("total_internal_reflection") }
            record?.lines.append("weights \(localWeight) \(optical.reflection) \(optical.transmission)")
            var reflectedColor = Color(), refractedColor = Color()
            if optical.reflection > 0 { reflectedColor = trace(info.point, reflected(direction, info.normal), kind: .reflection, depth: depth + 1, pixel: pixel, record: record).color }
            if optical.transmission > 0 { refractedColor = trace(info.point, optical.direction!, kind: .refraction, depth: depth + 1, pixel: pixel, record: record).color }
            color = mix([(local, localWeight), (reflectedColor, optical.reflection), (refractedColor, optical.transmission)])
        }
        color = applyFog(color, info.distance); record?.lines.append("color " + color.text)
        return TraceResult(color: color, hit: info)
    }
}

extension Renderer {
    func render() {
        for y in 0..<settings.height {
            for x in 0..<settings.width {
                let pixel = Pixel(x, y), result = trace(scene.eye, cameraDirection(4 * x + 2, 4 * y + 2), pixel: pixel)
                pixel.center = result.color; pixel.color = result.color; pixel.hit = result.hit
                if let hit = result.hit { pixel.label = hit.object.label; for i in hit.lighting.indices where hit.lighting[i].lit > 0 { lightCounts[i].pixels += 1 } }
                pixels.append(pixel)
            }
        }
        for pixel in pixels {
            let neighbors = [(pixel.x, pixel.y - 1), (pixel.x, pixel.y + 1), (pixel.x - 1, pixel.y), (pixel.x + 1, pixel.y)].filter { x, y in x >= 0 && x < settings.width && y >= 0 && y < settings.height }.map { x, y in pixels[y * settings.width + x] }
            let boundary = neighbors.contains { other in other.label != pixel.label || (0..<3).map { abs(other.center[$0] - pixel.center[$0]) }.max()! > settings.contrast }
            if !boundary { continue }
            supersampled += 1; pixel.samples = 4
            var colors: [Color] = []
            for (dx, dy) in [(1, 1), (3, 1), (1, 3), (3, 3)] { colors.append(trace(scene.eye, cameraDirection(4 * pixel.x + dx, 4 * pixel.y + dy), pixel: pixel).color) }
            let average = (0..<3).map { axis in colors.reduce(0) { $0 + $1[axis] } / 4 }
            pixel.color = Color(average[0], average[1], average[2])
        }
    }
    func distanceRange() -> (minimum: Int, maximum: Int)? { let values = pixels.compactMap { $0.hit?.distance }; return values.isEmpty ? nil : (values.min()!, values.max()!) }
    func meanColor(_ region: [Pixel]) -> Color { let values = (0..<3).map { axis in region.reduce(0) { $0 + $1.color[axis] } / region.count }; return Color(values[0], values[1], values[2]) }
    func writeNetpbm(_ name: String, _ magic: String, _ values: [String]) throws {
        let rows = (0..<settings.height).map { y in values[(y * settings.width)..<((y + 1) * settings.width)].joined(separator: " ") }
        try writeLines(name, [magic, "\(settings.width) \(settings.height)", "255"] + rows)
    }
    func writeMap(_ name: String, _ values: [String]) throws { try writeLines(name, (0..<settings.height).map { y in values[(y * settings.width)..<((y + 1) * settings.width)].joined() }) }
    func writeImages() throws {
        let range = distanceRange(), maximumCost = pixels.map { $0.rays }.max()!
        var depths: [String] = [], normals: [String] = [], albedos: [String] = [], illumination: [String] = []
        for pixel in pixels {
            guard let hit = pixel.hit else { depths.append("0"); normals.append(Color().text); albedos.append(Color().text); illumination.append("."); continue }
            let limits = range!, depth = limits.maximum == limits.minimum ? 255 : 255 - floorDivide(235 * (hit.distance - limits.minimum), limits.maximum - limits.minimum)
            let components = (0..<3).map { max(0, min(255, floorDivide((hit.normal[$0] + scale) * 255, 2 * scale))) }
            depths.append(String(depth)); normals.append(Color(components[0], components[1], components[2]).text); albedos.append(hit.base.text); illumination.append(String(hit.illumination))
        }
        try writeNetpbm("image.ppm", "P3", pixels.map { $0.color.text })
        try writeNetpbm("depth.pgm", "P2", depths)
        try writeNetpbm("normal.ppm", "P3", normals)
        try writeNetpbm("albedo.ppm", "P3", albedos)
        try writeNetpbm("cost.pgm", "P2", pixels.map { String(255 * $0.rays / maximumCost) })
        try writeMap("object_map.txt", pixels.map { $0.label })
        try writeMap("light_map.txt", illumination)
        try writeMap("ray_depth.txt", pixels.map { String($0.depth) })
    }
    func statistics() -> [String] {
        var lines = ["image \(settings.width) \(settings.height)", "supersampled \(supersampled)", "rays " + RayKind.allCases.map { "\($0.text) \(rays[$0.rawValue])" }.joined(separator: " ") + " total \(rays.reduce(0, +))", "misses " + RayKind.allCases.prefix(3).map { "\($0.text) \(misses[$0.rawValue])" }.joined(separator: " "), "depth " + integerText(depthCounts)]
        for kind in RayKind.allCases { let counts = tests[kind.rawValue]; lines.append("tests \(kind.text) nodes \(counts.nodes) objects \(counts.objects)") }
        lines += ["total_internal_reflection \(internalReflections)", "clamped \(clamped)", "distance " + (distanceRange().map { "\($0.minimum) \($0.maximum)" } ?? "none"), "max_pixel_rays \(pixels.map { $0.rays }.max()!)", "mean " + meanColor(pixels).text]
        var histogram = Array(repeating: 0, count: 8)
        for pixel in pixels { let color = pixel.color, brightness = (299 * color.r + 587 * color.g + 114 * color.b) / 1000; histogram[brightness / 32] += 1 }
        lines.append("histogram " + integerText(histogram))
        for node in nodes { let role = node.objects.map { "leaf " + $0.map { $0.label }.joined() } ?? "inner"; lines.append("node \(node.depth) \(role) box \(node.bounds.text) visits \(node.visits)") }
        for object in scene.objects {
            let region = pixels.filter { $0.label == object.label }, counts = objectCounts[object.number - 1], box: String, color: String
            if region.isEmpty { box = "none"; color = "none" }
            else { box = integerText([region.map { $0.x }.min()!, region.map { $0.y }.min()!, region.map { $0.x }.max()!, region.map { $0.y }.max()!]); color = meanColor(region).text }
            lines.append("object \(object.label) \(object.kind) primary \(counts.primary) secondary \(counts.secondary) shadow \(counts.shadow) pixels \(region.count) box \(box) color \(color)")
        }
        for light in scene.lights {
            let counts = lightCounts[light.number - 1]
            lines.append("light \(light.number) \(light.kind) samples \(light.samples) pixels \(counts.pixels) shadow_rays \(counts.shadowRays) blocked \(counts.blocked) attenuated \(counts.attenuated) backfacing \(counts.backfacing) outside \(counts.outside)")
        }
        return lines
    }
    func pixelQuery(_ x: Int, _ y: Int) -> [String] {
        let pixel = pixels[y * settings.width + x]
        return ["label \(pixel.label) distance \(pixel.hit.map { String($0.distance) } ?? "none") color \(pixel.color.text) samples \(pixel.samples) rays \(pixel.rays)"]
    }
    func objectQuery(_ label: String) -> [String] {
        let object = scene.objects.first { $0.label == label }!, prefix = "\(object.kind) material \(object.material.name)"
        return [prefix + (object.bounds.map { " bounds \($0.text) leaf \(object.leafDepth!)" } ?? " bounds none leaf none")]
    }
    func visibleQuery(_ point: Vector3) -> [String] {
        let relative = point - scene.eye, direction = normalized(relative), blockers = occluders(scene.eye, direction, length(relative) - settings.epsilon), visible = blockers.isEmpty ? "yes" : "no"
        guard let hit = nearest(scene.eye, direction) else { return [visible + " first none"] }
        return ["\(visible) first \(hit.object.label) t \(hit.intersection.distance)"]
    }
    func shadowQuery(_ point: Vector3) -> [String] {
        scene.lights.map { light in
            var total = 0, numbers = Set<Int>()
            for sample in lightSamples(light, point) {
                var factor = coneFactor(light, sample.direction)
                for object in occluders(point, sample.direction, sample.distance) { numbers.insert(object.number); factor = multiply(factor, object.material.transmission) }
                total += factor
            }
            let labels = scene.objects.filter { numbers.contains($0.number) }.map { $0.label }.joined()
            return "light \(light.number) factor \(total) occluders \(labels.isEmpty ? "none" : labels)"
        }
    }
    func regionQuery(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int) -> [String] {
        let region = (y0...y1).flatMap { y in (x0...x1).map { pixels[y * settings.width + $0] } }
        var lines = ["pixels \(region.count) mean \(meanColor(region).text)"]
        for label in scene.objects.map({ $0.label }) + ["."] { let count = region.filter { $0.label == label }.count; if count > 0 { lines.append("label \(label) \(count)") } }
        return lines
    }
    func queries(_ queries: [String]) -> [String] {
        var lines: [String] = []
        for (number, line) in queries.enumerated() {
            lines.append("query \(number + 1) \(line)")
            let words = line.components(separatedBy: " "), kind = words[0]
            if kind == "object" { lines += objectQuery(words[1]); continue }
            let values = words.dropFirst().map { Int($0)! }
            switch kind {
            case "pixel": lines += pixelQuery(values[0], values[1])
            case "trace": let log = TraceLog(); _ = trace(scene.eye, cameraDirection(4 * values[0] + 2, 4 * values[1] + 2), record: log); lines += log.lines
            case "ray": let log = TraceLog(); _ = trace(Vector3(values[0], values[1], values[2]), normalized(Vector3(values[3], values[4], values[5])), record: log); lines += log.lines
            case "visible": lines += visibleQuery(Vector3(values[0], values[1], values[2]))
            case "shadow": lines += shadowQuery(Vector3(values[0], values[1], values[2]))
            default: lines += regionQuery(values[0], values[1], values[2], values[3])
            }
        }
        return lines
    }
}

let scene = try Scene(), settings = try readSettings()
let renderer = Renderer(scene, settings)
renderer.render()
try renderer.writeImages()
try writeLines("stats.txt", renderer.statistics())
try writeLines("queries.txt", renderer.queries(inputLines("queries.txt")))
