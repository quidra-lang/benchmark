import Foundation

let polygonKinds = ["equilateral_triangle", "right_triangle", "triangle", "square", "rectangle", "parallelogram", "trapezoid", "quadrilateral"]
func cross(_ a: Pixel, _ b: Pixel) -> Int { a.x * b.y - a.y * b.x }
func dot(_ a: Pixel, _ b: Pixel) -> Int { a.x * b.x + a.y * b.y }
func chebyshev(_ a: Pixel, _ b: Pixel) -> Int { max(abs(a.x - b.x), abs(a.y - b.y)) }
func angleDifference(_ a: Int, _ b: Int) -> Int { min(abs(a - b), 180 - abs(a - b)) }
func nearestInteger(_ numerator: Int, _ denominator: Int) -> Int {
    let n = denominator < 0 ? -numerator : numerator, d = abs(denominator)
    return floorDivide(2 * n + d, 2 * d)
}

func bresenham(_ start: Pixel, _ end: Pixel) -> [Pixel] {
    var x = start.x, y = start.y
    let dx = abs(end.x - x), dy = -abs(end.y - y), sx = x < end.x ? 1 : -1, sy = y < end.y ? 1 : -1
    var error = dx + dy, points: [Pixel] = []
    while true {
        points.append(Pixel(x: x, y: y))
        if x == end.x && y == end.y { break }
        let doubled = 2 * error
        if doubled >= dy { error += dy; x += sx }
        if doubled <= dx { error += dx; y += sy }
    }
    return points
}

struct Measurement { var pixels = 0; var mean = 0; var contrast = 0 }

final class Circle {
    let number: Int
    let center: Pixel
    let radius: Int
    let votes: Int
    let outline: [Pixel]
    let gap: Int
    let arcs: Int
    var measurement = Measurement()
    var enclosing = "none"
    init(_ number: Int, _ candidate: CircleCandidate, _ outline: [Pixel], _ gap: Int, _ arcs: Int) {
        self.number = number; center = candidate.center; radius = candidate.radius; votes = candidate.votes; self.outline = outline; self.gap = gap; self.arcs = arcs
    }
}

func sortCircleOffsets(_ offsets: [Pixel]) -> [Pixel] {
    func half(_ p: Pixel) -> Int { p.y > 0 || (p.y == 0 && p.x > 0) ? 0 : 1 }
    return offsets.sorted {
        if half($0) != half($1) { return half($0) < half($1) }
        let sign = cross($0, $1)
        return sign == 0 ? [$0.x, $0.y].lexicographicallyPrecedes([$1.x, $1.y]) : sign > 0
    }
}

func circleGaps(_ center: Pixel, _ outline: [Pixel], _ edges: Set<Pixel>) -> (gap: Int, arcs: Int) {
    let hits = sortCircleOffsets(outline).map { edges.contains(center + $0) }, count = outline.count
    if hits.allSatisfy({ $0 }) { return (0, 1) }
    if !hits.contains(true) { return (count, 0) }
    let arcs = hits.indices.filter { hits[$0] && !hits[($0 + count - 1) % count] }.count
    var maximum = 0, run = 0
    for hit in hits + hits { if hit { run = 0 } else { run += 1; maximum = max(maximum, run) } }
    return (min(maximum, count), arcs)
}

func onCircumference(_ point: Pixel, _ circle: Circle) -> Bool {
    let offset = point - circle.center, squared = dot(offset, offset)
    return (circle.radius - 1) * (circle.radius - 1) <= squared && squared <= (circle.radius + 1) * (circle.radius + 1)
}

func selectCircles(_ votes: CircleVotes, _ peaks: CirclePeaks, _ edges: Set<Pixel>, _ count: Int) -> (circles: [Circle], circumference: Set<Pixel>, remaining: Set<Pixel>) {
    let circles = peaks.peaks.prefix(count).enumerated().map { index, peak -> Circle in
        let outline = votes.outlines[peak.radius]!, gaps = circleGaps(peak.center, votes.outlines[peak.radius]!, edges)
        return Circle(index + 1, peak, outline, gaps.gap, gaps.arcs)
    }
    let circumference = Set(edges.filter { point in circles.contains { onCircumference(point, $0) } })
    return (circles, circumference, edges.subtracting(circumference))
}

struct Segment {
    let number: Int
    let line: Int
    let start: Pixel
    let end: Pixel
    let length: Int
    let pixels: Int
    let angle: Int
}
struct DetectedLine { let number: Int; let angle: Int; let rho: Int; let votes: Int; let segments: [Int] }

func segmentGroups(_ pixels: [Pixel], _ trig: TrigValue, _ gap: Int) -> [[Pixel]] {
    func position(_ p: Pixel) -> Int { p.y * trig.cosine - p.x * trig.sine }
    let ordered = pixels.sorted { [position($0), $0.x, $0.y].lexicographicallyPrecedes([position($1), $1.x, $1.y]) }
    var grouped: [[Pixel]] = [], current: [Pixel] = [], previous: Int?
    for point in ordered {
        let value = position(point)
        if let previous, value - previous > gap * 16384 { grouped.append(current); current = [] }
        current.append(point); previous = value
    }
    if !current.isEmpty { grouped.append(current) }
    return grouped
}

func extractSegments(_ peaks: [LinePeak], _ edges: Set<Pixel>, _ trig: [TrigValue], _ params: Parameters) -> (lines: [DetectedLine], segments: [Segment], used: Set<Pixel>) {
    var used = Set<Pixel>(), lines: [DetectedLine] = [], segments: [Segment] = []
    for peak in peaks {
        if lines.count >= params.houghMaxLines { break }
        let angle = peak.cell.angle, radial = peak.cell.rho
        let available = edges.filter { !used.contains($0) && abs(rho($0, angle, trig, params.houghRhoStep) - radial) <= params.segmentTolerance }
        let groups = segmentGroups(Array(available), trig[angle], params.segmentMaxGap).filter { chebyshev($0[0], $0.last!) + 1 >= params.segmentMinLength }
        if groups.isEmpty { continue }
        let line = lines.count + 1
        var numbers: [Int] = []
        for group in groups {
            let number = segments.count + 1
            segments.append(Segment(number: number, line: line, start: group[0], end: group.last!, length: chebyshev(group[0], group.last!) + 1, pixels: group.count, angle: angle))
            numbers.append(number); used.formUnion(group)
        }
        lines.append(DetectedLine(number: line, angle: angle, rho: radial, votes: peak.votes, segments: numbers))
    }
    return (lines, segments, used)
}

struct SegmentPair: Hashable {
    let first: Int
    let second: Int
    init(_ first: Int, _ second: Int) { self.first = min(first, second); self.second = max(first, second) }
}
struct Junction {
    let point: Pixel
    let ends: [Int: Int]
}

func chooseJunctionEnd(_ segment: Segment, _ point: Pixel) -> (end: Int, distance: Int) {
    let start = chebyshev(segment.start, point), end = chebyshev(segment.end, point)
    return start <= end ? (0, start) : (1, end)
}

func buildJunctions(_ segments: [Segment], _ angle: Int, _ maximumDistance: Int) -> [SegmentPair: Junction] {
    var joins: [SegmentPair: Junction] = [:]
    for (index, a) in segments.enumerated() {
        for b in segments.dropFirst(index + 1) {
            if angleDifference(a.angle, b.angle) < angle { continue }
            let da = a.end - a.start, db = b.end - b.start, denominator = cross(da, db)
            if denominator == 0 { continue }
            let lambda = cross(b.start - a.start, db)
            let point = Pixel(x: nearestInteger(a.start.x * denominator + lambda * da.x, denominator), y: nearestInteger(a.start.y * denominator + lambda * da.y, denominator))
            let endA = chooseJunctionEnd(a, point), endB = chooseJunctionEnd(b, point)
            if max(endA.distance, endB.distance) > maximumDistance { continue }
            joins[SegmentPair(a.number, b.number)] = Junction(point: point, ends: [a.number: endA.end, b.number: endB.end])
        }
    }
    return joins
}

final class Polygon {
    let number: Int
    let segments: [Int]
    let vertices: [Pixel]
    var angles: [Int] = []
    var lengths: [Int] = []
    var supports: [Int] = []
    var sigma = 0
    var kind = ""
    var vertexCorners: [Int?]
    var measurement = Measurement()
    var enclosing = "none"
    init(_ number: Int, _ segments: [Int], _ vertices: [Pixel]) { self.number = number; self.segments = segments; self.vertices = vertices; vertexCorners = Array(repeating: nil, count: vertices.count) }
}

func polygonCycles(_ segments: [Segment], _ junctions: [SegmentPair: Junction]) -> [Polygon] {
    var graph: [Int: Set<Int>] = [:]
    for pair in junctions.keys { graph[pair.first, default: []].insert(pair.second); graph[pair.second, default: []].insert(pair.first) }
    var polygons: [Polygon] = []
    for count in [3, 4] {
        var found: [(sequence: [Int], vertices: [Pixel])] = []
        for first in graph.keys.sorted() {
            func extend(_ sequence: [Int]) {
                if sequence.count == count {
                    if sequence[1] >= sequence.last! || junctions[SegmentPair(sequence.last!, first)] == nil { return }
                    var vertices: [Pixel] = []
                    for (i, current) in sequence.enumerated() {
                        let previous = sequence[(i + count - 1) % count], following = sequence[(i + 1) % count]
                        let entry = junctions[SegmentPair(previous, current)]!, exit = junctions[SegmentPair(current, following)]!
                        if entry.ends[current]! == exit.ends[current]! { return }
                        vertices.append(entry.point)
                    }
                    let turns = (0..<count).map { cross(vertices[($0 + 1) % count] - vertices[$0], vertices[($0 + 2) % count] - vertices[($0 + 1) % count]) }
                    if turns.allSatisfy({ $0 > 0 }) || turns.allSatisfy({ $0 < 0 }) { found.append((sequence, vertices)) }
                    return
                }
                for candidate in graph[sequence.last!]!.sorted() where candidate > first && !sequence.contains(candidate) { extend(sequence + [candidate]) }
            }
            extend([first])
        }
        found.sort { $0.sequence.lexicographicallyPrecedes($1.sequence) }
        for entry in found { polygons.append(Polygon(polygons.count + 1, entry.sequence, entry.vertices)) }
    }
    return polygons
}

func sideSupport(_ start: Pixel, _ end: Pixel, _ edges: Set<Pixel>) -> Int {
    let points = bresenham(start, end)
    let support = points.filter { point in (-1...1).contains { dx in (-1...1).contains { dy in edges.contains(Pixel(x: point.x + dx, y: point.y + dy)) } } }.count
    return 100 * support / points.count
}

func polygonProperties(_ polygon: Polygon, _ segments: [Segment], _ edges: Set<Pixel>, _ params: Parameters) {
    let vertices = polygon.vertices, count = polygon.vertices.count, theta = polygon.segments.map { segments[$0 - 1].angle }
    for i in 0..<count {
        let previous = vertices[(i + count - 1) % count], point = vertices[i], following = vertices[(i + 1) % count]
        let phi = angleDifference(theta[(i + count - 1) % count], theta[i])
        polygon.angles.append(dot(previous - point, following - point) < 0 ? 180 - phi : phi)
        let side = following - point
        polygon.lengths.append(dot(side, side)); polygon.supports.append(sideSupport(point, following, edges)); polygon.sigma += cross(point, following)
    }
    let tolerance = params.angleTolerance
    if count == 3 {
        polygon.kind = polygon.angles.allSatisfy({ abs($0 - 60) <= tolerance }) ? "equilateral_triangle" : polygon.angles.contains(where: { abs($0 - 90) <= tolerance }) ? "right_triangle" : "triangle"
    } else {
        let first = angleDifference(theta[0], theta[2]) <= tolerance, second = angleDifference(theta[1], theta[3]) <= tolerance
        if !first && !second { polygon.kind = "quadrilateral" }
        else if first != second { polygon.kind = "trapezoid" }
        else if polygon.angles.contains(where: { abs($0 - 90) > tolerance }) { polygon.kind = "parallelogram" }
        else { polygon.kind = 100 * (polygon.lengths.max()! - polygon.lengths.min()!) <= params.squareTolerance * polygon.lengths.max()! ? "square" : "rectangle" }
    }
}

enum Shape {
    case polygon(Polygon), circle(Circle)
    var name: String { switch self { case .polygon(let p): return "polygon \(p.number)"; case .circle(let c): return "circle \(c.number)" } }
    var measurement: Measurement { switch self { case .polygon(let p): return p.measurement; case .circle(let c): return c.measurement } }
    var representatives: [Pixel] {
        switch self {
        case .polygon(let polygon): return polygon.vertices
        case .circle(let circle):
            let c = circle.center, r = circle.radius
            return [Pixel(x: c.x + r, y: c.y), Pixel(x: c.x, y: c.y + r), Pixel(x: c.x - r, y: c.y), Pixel(x: c.x, y: c.y - r)]
        }
    }
    func setMeasurement(_ value: Measurement) { switch self { case .polygon(let p): p.measurement = value; case .circle(let c): c.measurement = value } }
    func setEnclosing(_ name: String) { switch self { case .polygon(let p): p.enclosing = name; case .circle(let c): c.enclosing = name } }
    func contains(_ point: Pixel) -> Bool {
        switch self {
        case .circle(let circle): let offset = point - circle.center; return dot(offset, offset) <= circle.radius * circle.radius
        case .polygon(let polygon):
            for (index, vertex) in polygon.vertices.enumerated() {
                let value = cross(polygon.vertices[(index + 1) % polygon.vertices.count] - vertex, point - vertex)
                if value != 0 && ((value > 0) != (polygon.sigma > 0)) { return false }
            }
            return true
        }
    }
}

func measureShapes(_ shapes: [Shape], _ original: Image, _ margin: Int) {
    let height = original.count, width = original[0].count
    for shape in shapes {
        let representatives = shape.representatives
        let x0 = max(0, representatives.map { $0.x }.min()! - margin), x1 = min(width - 1, representatives.map { $0.x }.max()! + margin)
        let y0 = max(0, representatives.map { $0.y }.min()! - margin), y1 = min(height - 1, representatives.map { $0.y }.max()! + margin)
        var innerCount = 0, outerCount = 0, innerTotal = 0, outerTotal = 0
        if x0 <= x1 && y0 <= y1 {
            for y in y0...y1 {
                for x in x0...x1 {
                    if shape.contains(Pixel(x: x, y: y)) { innerCount += 1; innerTotal += original[y][x] } else { outerCount += 1; outerTotal += original[y][x] }
                }
            }
        }
        let mean = innerCount > 0 ? innerTotal / innerCount : 0, outerMean = outerCount > 0 ? outerTotal / outerCount : 0
        shape.setMeasurement(Measurement(pixels: innerCount, mean: mean, contrast: mean - outerMean))
    }
    for (index, child) in shapes.enumerated() {
        var best: Int?
        for (other, parent) in shapes.enumerated() where other != index && parent.measurement.pixels > child.measurement.pixels {
            if child.representatives.allSatisfy({ parent.contains($0) }) && (best == nil || parent.measurement.pixels < shapes[best!].measurement.pixels) { best = other }
        }
        child.setEnclosing(best.map { shapes[$0].name } ?? "none")
    }
}

enum CornerMatch {
    case none, vertex(polygon: Int, index: Int), segment(number: Int, end: Int)
    var text: String {
        switch self {
        case .none: return "none"
        case .vertex(let polygon, let index): return "polygon \(polygon) vertex \(index)"
        case .segment(let number, let end): return "segment \(number) \(end == 0 ? "start" : "end")"
        }
    }
    var kind: String { switch self { case .none: return "none"; case .vertex: return "vertex"; case .segment: return "segment" } }
}
final class Corner {
    let number: Int
    let point: Pixel
    let response: Int
    var match = CornerMatch.none
    init(_ number: Int, _ candidate: CornerCandidate) { self.number = number; point = candidate.point; response = candidate.response }
}

func matchCorners(_ corners: [Corner], _ polygons: [Polygon], _ segments: [Segment], _ maximumDistance: Int) -> Int {
    for corner in corners {
        var best: (key: [Int], match: CornerMatch)?
        for polygon in polygons {
            for (index, vertex) in polygon.vertices.enumerated() {
                let distance = chebyshev(corner.point, vertex), key = [chebyshev(corner.point, vertex), polygon.number, index + 1]
                if distance <= maximumDistance && (best == nil || key.lexicographicallyPrecedes(best!.key)) { best = (key, .vertex(polygon: polygon.number, index: index + 1)) }
            }
        }
        if let best { corner.match = best.match; continue }
        for segment in segments {
            for (end, point) in [segment.start, segment.end].enumerated() {
                let distance = chebyshev(corner.point, point), key = [chebyshev(corner.point, point), segment.number, end]
                if distance <= maximumDistance && (best == nil || key.lexicographicallyPrecedes(best!.key)) { best = (key, .segment(number: segment.number, end: end)) }
            }
        }
        corner.match = best?.match ?? .none
    }
    var matches = 0
    for polygon in polygons {
        for (index, vertex) in polygon.vertices.enumerated() {
            var best: (distance: Int, number: Int)?
            for corner in corners {
                let distance = chebyshev(vertex, corner.point)
                if distance <= maximumDistance && (best == nil || distance < best!.distance || (distance == best!.distance && corner.number < best!.number)) { best = (distance, corner.number) }
            }
            if let best { polygon.vertexCorners[index] = best.number; matches += 1 }
        }
    }
    return matches
}

final class EdgeComponent {
    let number: Int
    let pixels: [Pixel]
    let bounds: [Int]
    let ends: Int
    let strength: Int
    let direction: Int
    var shape = "none"
    var explained = 0
    init(_ number: Int, _ pixels: [Pixel], _ edges: Set<Pixel>, _ magnitude: Image, _ directions: Image) {
        self.number = number; self.pixels = pixels
        bounds = [pixels.map { $0.x }.min()!, pixels.map { $0.y }.min()!, pixels.map { $0.x }.max()!, pixels.map { $0.y }.max()!]
        ends = pixels.filter { point in neighborOffsets.filter { edges.contains(point + $0) }.count == 1 }.count
        strength = pixels.reduce(0) { $0 + magnitude[$1.y][$1.x] } / pixels.count
        let counts = Dictionary(grouping: pixels.map { directions[$0.y][$0.x] }, by: { $0 }).mapValues { $0.count }
        direction = counts.keys.min { counts[$0]! == counts[$1]! ? $0 < $1 : counts[$0]! > counts[$1]! }!
    }
}

func shapeExplanations(_ shape: Shape, _ edges: Set<Pixel>) -> Set<Pixel> {
    switch shape {
    case .circle(let circle): return Set(edges.filter { onCircumference($0, circle) })
    case .polygon(let polygon):
        var explained = Set<Pixel>()
        for (index, start) in polygon.vertices.enumerated() {
            for point in bresenham(start, polygon.vertices[(index + 1) % polygon.vertices.count]) {
                for dx in -1...1 {
                    for dy in -1...1 { let next = Pixel(x: point.x + dx, y: point.y + dy); if edges.contains(next) { explained.insert(next) } }
                }
            }
        }
        return explained
    }
}

func matchComponents(_ components: [EdgeComponent], _ shapes: [Shape], _ edges: Set<Pixel>) {
    let explanations = shapes.map { shapeExplanations($0, edges) }
    for component in components {
        let pixels = Set(component.pixels)
        for (index, explanation) in explanations.enumerated() {
            let count = pixels.intersection(explanation).count
            if count > component.explained { component.shape = shapes[index].name; component.explained = count }
        }
    }
}

func overlayImage(_ original: Image, _ segments: [Segment], _ circles: [Circle], _ corners: [Corner], _ divisor: Int) -> Image {
    var image = original.map { $0.map { $0 / divisor } }
    let height = image.count, width = image[0].count
    func mark(_ point: Pixel) { if point.x >= 0 && point.x < width && point.y >= 0 && point.y < height { image[point.y][point.x] = 255 } }
    for segment in segments { for point in bresenham(segment.start, segment.end) { mark(point) } }
    for circle in circles { for offset in circle.outline { mark(circle.center + offset) } }
    for corner in corners { for offset in -2...2 { mark(Pixel(x: corner.point.x + offset, y: corner.point.y)); mark(Pixel(x: corner.point.x, y: corner.point.y + offset)) } }
    return image
}

func voteImage(_ votes: [LineCell: Int], _ width: Int, _ height: Int, _ trig: [TrigValue], _ step: Int) -> (image: Image, maximum: Int) {
    let corners = [Pixel(x: 0, y: 0), Pixel(x: width - 1, y: 0), Pixel(x: 0, y: height - 1), Pixel(x: width - 1, y: height - 1)]
    let limits = (0..<180).flatMap { angle in corners.map { rho($0, angle, trig, step) } }, maximum = votes.values.max() ?? 0
    let image = (limits.min()!...limits.max()!).map { radial in (0..<180).map { angle in maximum > 0 ? 255 * (votes[LineCell(angle: angle, rho: radial)] ?? 0) / maximum : 0 } }
    return (image, maximum)
}

func linesListing(_ lines: [DetectedLine], _ segments: [Segment]) -> [String] {
    var output = ["lines \(lines.count)"]
    for line in lines {
        output.append("line \(line.number) theta \(line.angle) rho \(line.rho) votes \(line.votes) segments \(line.segments.count)")
        for number in line.segments { let segment = segments[number - 1]; output.append("segment \(number) start \(segment.start.text) end \(segment.end.text) length \(segment.length) pixels \(segment.pixels)") }
    }
    return output
}

func circlesListing(_ circles: [Circle]) -> [String] {
    ["circles \(circles.count)"] + circles.map { circle in
        let measure = circle.measurement
        return "circle \(circle.number) center \(circle.center.text) radius \(circle.radius) votes \(circle.votes) points \(circle.outline.count) gap \(circle.gap) arcs \(circle.arcs) pixels \(measure.pixels) mean \(measure.mean) contrast \(measure.contrast) inside \(circle.enclosing)"
    }
}

func polygonsListing(_ polygons: [Polygon]) -> [String] {
    var lines = ["polygons \(polygons.count)"]
    for polygon in polygons {
        let amount = abs(polygon.sigma), measure = polygon.measurement
        let area = "\(amount / 2).\(amount % 2 == 0 ? "0" : "5")"
        lines.append("polygon \(polygon.number) \(polygon.kind) segments " + polygon.segments.map(String.init).joined(separator: " ") + " area \(area) pixels \(measure.pixels) mean \(measure.mean) contrast \(measure.contrast) inside \(polygon.enclosing)")
        for (index, vertex) in polygon.vertices.enumerated() { lines.append("vertex \(index + 1) \(vertex.text) angle \(polygon.angles[index]) corner \(polygon.vertexCorners[index].map(String.init) ?? "none")") }
        for (index, number) in polygon.segments.enumerated() { lines.append("side \(index + 1) segment \(number) length2 \(polygon.lengths[index]) support \(polygon.supports[index])") }
    }
    return lines
}

func cornersListing(_ corners: [Corner]) -> [String] { ["corners \(corners.count)"] + corners.map { "corner \($0.number) \($0.point.text) response \($0.response) match \($0.match.text)" } }
func componentsListing(_ components: [EdgeComponent]) -> [String] {
    ["components \(components.count)"] + components.map { "component \($0.number) pixels \($0.pixels.count) box " + $0.bounds.map(String.init).joined(separator: " ") + " ends \($0.ends) strength \($0.strength) direction \($0.direction) shape \($0.shape) explained \($0.explained)" }
}

let image = try readPGM()
let trig = try readTrig(), params = try readParameters()
let height = image.count, width = image[0].count
let smoothed = smoothing(image, params), gradients = gradient(smoothed)
let direction = directions(gradients), nms = suppress(gradients.magnitude, direction)
let detectedEdges = hysteresis(nms, params.cannyLow, params.cannyHigh), edges = detectedEdges.pixels
let components = edgeComponents(edges).enumerated().map { EdgeComponent($0.offset + 1, $0.element, edges, gradients.magnitude, direction) }
let circleCells = circleVotes(edges, width, height, params)
let circularPeaks = circlePeaks(circleCells, width, height, params.circleMinPercent)
let selected = selectCircles(circleCells, circularPeaks, edges, params.circleMaxCount), circles = selected.circles
let votes = lineVotes(selected.remaining, trig, params.houghRhoStep), peaks = linePeaks(votes, params.houghThreshold)
let extracted = extractSegments(peaks, selected.remaining, trig, params), lines = extracted.lines, segments = extracted.segments
let junctions = buildJunctions(segments, params.junctionMinAngle, params.junctionDistance), polygons = polygonCycles(segments, junctions)
for polygon in polygons { polygonProperties(polygon, segments, edges, params) }
let shapes = polygons.map { Shape.polygon($0) } + circles.map { Shape.circle($0) }
measureShapes(shapes, image, params.contrastMargin)
let detectedCorners = harrisCorners(gradients.x, gradients.y, params.harrisWindow, params.harrisThreshold, params.harrisMaxCount)
let corners = detectedCorners.chosen.enumerated().map { Corner($0.offset + 1, $0.element) }
let verticesWithCorner = matchCorners(corners, polygons, segments, params.cornerMatchDistance)
matchComponents(components, shapes, edges)
let overlay = overlayImage(image, segments, circles, corners, params.overlayDivisor)
let houghImage = voteImage(votes, width, height, trig, params.houghRhoStep)
let edgeImage = (0..<height).map { y in (0..<width).map { edges.contains(Pixel(x: $0, y: y)) ? 255 : 0 } }
try writePGM("edges.pgm", edgeImage)
try writePGM("hough.pgm", houghImage.image)
try writePGM("overlay.pgm", overlay)
try writeLines("lines.txt", linesListing(lines, segments))
try writeLines("circles.txt", circlesListing(circles))
try writeLines("polygons.txt", polygonsListing(polygons))
try writeLines("corners.txt", cornersListing(corners))
try writeLines("components.txt", componentsListing(components))
var report = ["image \(width) \(height)", "gradient_nonzero \(gradients.magnitude.flatMap { $0 }.filter { $0 > 0 }.count)", "gradient_max \(gradients.magnitude.flatMap { $0 }.max()!)",
              "nms_kept \(nms.flatMap { $0 }.filter { $0 > 0 }.count)", "strong \(detectedEdges.strongPixels.count)", "weak \(detectedEdges.weakPixels.count)", "edges \(edges.count)",
              "weak_kept \(detectedEdges.weakPixels.intersection(edges).count)", "weak_dropped \(detectedEdges.weakPixels.subtracting(edges).count)", "edge_components \(components.count)"]
for angle in [0, 45, 90, 135] { report.append("direction_\(angle) \(edges.filter { direction[$0.y][$0.x] == angle }.count)") }
report += ["circle_candidates \(circularPeaks.candidates)", "circle_peaks \(circularPeaks.peaks.count)", "circles \(circles.count)", "circle_edge_pixels \(selected.circumference.count)",
           "line_edge_pixels \(selected.remaining.count)", "hough_max_votes \(houghImage.maximum)", "hough_peaks \(peaks.count)", "lines \(lines.count)", "segments \(segments.count)",
           "claimed_pixels \(extracted.used.count)", "junctions \(junctions.count)", "polygons \(polygons.count)"]
for kind in polygonKinds { report.append("\(kind) \(polygons.filter { $0.kind == kind }.count)") }
report += ["corner_candidates \(detectedCorners.candidates)", "corners \(corners.count)", "corners_on_vertices \(corners.filter { $0.match.kind == "vertex" }.count)",
           "corners_on_segments \(corners.filter { $0.match.kind == "segment" }.count)", "corners_unmatched \(corners.filter { $0.match.kind == "none" }.count)", "vertices_with_corner \(verticesWithCorner)"]
try writeLines("report.txt", report)
