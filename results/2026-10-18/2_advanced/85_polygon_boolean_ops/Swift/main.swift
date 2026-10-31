import Foundation
struct Polygon {
    let input: Rings, rings: Rings
}
struct Target {
    let region: Region, operands: (Rings, Rings)?
}
struct Rejection: Error {
    let reason: String;
    init(_ reason: String) {
        self.reason = reason
    }
}
func integer(_ text: String) -> Int128? {
    let digits = text.first == "-" ? String(text.dropFirst()) : text
    return !digits.isEmpty && digits.count <= 9 && digits.utf8.allSatisfy({
        (48...57).contains($0)
    }) ? Int128(text) : nil
}
func validName(_ text: String) -> Bool {
    !text.isEmpty && text.count <= 16 && text.utf8.allSatisfy {
        (97...122).contains($0) || (48...57).contains($0) || $0 == 95
    }
}
func validate(_ rings: Rings) -> String? {
    for (k, ring) in rings.enumerated() {
        let n = ring.count
        if n < 3 {
            return "too_few_vertices ring \(k + 1)"
        }
        if let p = ring.first(where: {
            $0.x < 0 || $0.y < 0 || $0.x > 1000 * $0.d || $0.y > 1000 * $0.d
        }) {
            return "out_of_range ring \(k + 1) \(p)"
        }
        var seen: Set<Point> = []
        for p in ring where !seen.insert(p).inserted {
            return "duplicate_vertex ring \(k + 1) \(p)"
        }
        for i in 0..<n where cross(ring[(i + n - 1) % n], ring[i], ring[(i + 1) % n]) == 0 {
            return "collinear ring \(k + 1) \(ring[i])"
        }
        for i in 0..<n {
            for j in (i + 1)..<n where j != i + 1 && !(i == 0 && j == n - 1) {
                if Intersections.touch(ring[i], ring[(i + 1) % n], ring[j], ring[(j + 1) % n]) {
                    return "self_intersection ring \(k + 1) \(Intersections.segment(ring[i], ring[(i + 1) % n])) \(Intersections.segment(ring[j], ring[(j + 1) % n]))"
                }
            }
        }
    }
    for i in rings.indices {
        for j in (i + 1)..<rings.count {
            for e in rings[i].indices {
                for f in rings[j].indices {
                    let a = rings[i][e], b = rings[i][(e + 1) % rings[i].count], c = rings[j][f], d = rings[j][(f + 1) % rings[j].count]
                    if Intersections.touch(a, b, c, d) {
                        return "rings_touch rings \(i + 1) \(j + 1) \(Intersections.segment(a, b)) \(Intersections.segment(c, d))"
                    }
                }
            }
        }
    }
    for k in 1..<rings.count where !RingOps.inside(rings[k][0], rings[0]) {
        return "hole_outside ring \(k + 1) \(rings[k][0])"
    }
    for i in 1..<rings.count {
        for j in (i + 1)..<rings.count {
            if RingOps.inside(rings[j][0], rings[i]) {
                return "hole_in_hole rings \(i + 1) \(j + 1) \(rings[j][0])"
            }
            if RingOps.inside(rings[i][0], rings[j]) {
                return "hole_in_hole rings \(i + 1) \(j + 1) \(rings[i][0])"
            }
        }
    }
    return nil
}
func parseBlock(_ content: [(Int, String)], _ end: Int) throws -> Rings {
    var rings: Rings = [], i = 0
    while i < content.count {
        let (line, text) = content[i], a = text.split(separator: " ").map(String.init)
        guard a.count == 2, (a[0] == "OUTER" && rings.isEmpty || a[0] == "HOLE" && !rings.isEmpty),
        !a[1].isEmpty, a[1].count <= 9, a[1].utf8.allSatisfy({
            (48...57).contains($0)
        }), let n = Int(a[1]), n > 0 else {
            throw Rejection("format line \(line)")
        }
        i += 1
        var ring: Ring = []
        for _ in 0..<n {
            if i == content.count {
                throw Rejection("format line \(end)")
            }
            let (line, text) = content[i], a = text.split(separator: " ").map(String.init)
            guard a.count == 2, let x = integer(a[0]), let y = integer(a[1]) else {
                throw Rejection("format line \(line)")
            }
            ring.append(Point(x, y))
            i += 1
        }
        rings.append(ring)
    }
    if rings.isEmpty {
        throw Rejection("format line \(end)")
    }
    return rings
}
struct Polygons {
    var used: Set<String> = [], valid: [String: Polygon] = [:], rejected: [String] = []
    var blocks = 0, validBlocks = 0
    static func read() -> Self {
        let lines = try! String(contentsOfFile: "input/polygons.txt", encoding: .ascii).components(separatedBy: "\n")
        var result = Self(), i = 0
        while i < lines.count {
            if lines[i].isEmpty || lines[i].first == "#" {
                i += 1;
                continue
            }
            let name = String(lines[i].split(separator: " ")[1]), start = i + 1
            i += 1
            var content: [(Int, String)] = []
            while lines[i] != "END" {
                if !lines[i].isEmpty && lines[i].first != "#" {
                    content.append((i + 1, lines[i]))
                };
                i += 1
            }
            let end = i + 1
            i += 1
            result.blocks += 1
            if !result.used.insert(name).inserted {
                result.rejected.append("polygon \(name) duplicate_name line \(start)");
                continue
            }
            do {
                let input = try parseBlock(content, end)
                if let reason = validate(input) {
                    throw Rejection(reason)
                }
                result.valid[name] = Polygon(input: input, rings: RingOps.canonical(input))
                result.validBlocks += 1
            } catch let error as Rejection {
                result.rejected.append("polygon \(name) \(error.reason)")
            }
            catch {
                preconditionFailure()
            }
        }
        return result
    }
    func get(_ name: String) throws -> Polygon {
        if !used.contains(name) {
            throw Rejection("unknown_polygon \(name)")
        }
        guard let polygon = valid[name] else {
            throw Rejection("invalid_polygon \(name)")
        }
        return polygon
    }
}
func target(_ text: String, _ polygons: Polygons, _ results: [Int: Target]) throws -> Target {
    if text.first == "@" {
        let n = String(text.dropFirst())
        guard !n.isEmpty, n.count <= 9, n.utf8.allSatisfy({
            (48...57).contains($0)
        }), let k = Int(n), let target = results[k] else {
            throw Rejection("bad_target \(text)")
        }
        return target
    }
    return Target(region: [try polygons.get(text).rings], operands: nil)
}
func general(_ a: Rings, _ b: Rings, _ an: String, _ bn: String) -> String? {
    for r in a {
        for p in r where b.contains(where: {
            $0.contains(p)
        }) {
            return "shared_vertex \(p)"
        }
    }
    for r in a {
        for e in r.indices {
            for q in b {
                for f in q.indices {
                    let u = r[e], v = r[(e + 1) % r.count], s = q[f], t = q[(f + 1) % q.count]
                    if Intersections.overlap(u, v, s, t) {
                        return "overlapping_edges \(Intersections.segment(u, v)) \(Intersections.segment(s, t))"
                    }
                }
            }
        }
    }
    for (p, q, pn, qn) in [(a, b, an, bn), (b, a, bn, an)] {
        for r in p {
            for v in r {
                for s in q {
                    for e in s.indices {
                        let u = s[e], w = s[(e + 1) % s.count]
                        if Intersections.on(u, w, v) {
                            return "vertex_on_edge \(pn) \(v) \(qn) \(Intersections.segment(u, w))"
                        }
                    }
                }
            }
        }
    }
    return nil
}
func convex(_ rings: Rings) -> Bool {
    rings.count == 1 && rings[0].indices.allSatisfy {
        i in let r = rings[0];
        return cross(r[(i + r.count - 1) % r.count], r[i], r[(i + 1) % r.count]) > 0
    }
}
func clip(_ a: Rings, _ window: Ring) -> Rings {
    var result: Rings = []
    for ring in a {
        var list = ring
        for j in window.indices {
            let c1 = window[j], c2 = window[(j + 1) % window.count]
            var next: Ring = []
            for i in list.indices {
                let prev = list[(i + list.count - 1) % list.count], cur = list[i]
                let pin = cross(c1, c2, prev) > 0, cin = cross(c1, c2, cur) > 0
                if pin != cin {
                    next.append(Intersections.lineIntersection(prev, cur, c1, c2))
                }
                if cin {
                    next.append(cur)
                }
            }
            list = next
        }
        let clean = list.indices.filter {
            list[$0] != list[($0 + list.count - 1) % list.count]
        }.map {
            list[$0]
        }
        if clean.count >= 3 {
            result.append(clean)
        }
    }
    return result
}
func cyclic(_ a: Ring, _ b: Ring) -> Bool {
    a.count == b.count && b.indices.contains {
        k in a.indices.allSatisfy {
            a[$0] == b[($0 + k) % b.count]
        }
    }
}
func locate(_ region: Region, _ point: Point) -> String {
    for (k, polygon) in region.enumerated() {
        for (j, ring) in polygon.enumerated() where RingOps.boundary(point, ring) {
            return j == 0 ? "boundary outer \(k + 1)" : "boundary hole \(k + 1) \(j)"
        }
    }
    for (k, polygon) in region.enumerated() where RingOps.inside(point, polygon[0]) && polygon.dropFirst().allSatisfy({
        !RingOps.inside(point, $0)
    }) {
        return "inside polygon \(k + 1)"
    }
    return "outside"
}
func operandLocation(_ point: Point, _ rings: Rings) -> String {
    rings.contains(where: {
        RingOps.boundary(point, $0)
    }) ? "boundary" : RingOps.interior(point, rings) ? "inside" : "outside"
}
func convexHull(_ ring: Ring) -> Ring {
    let sorted = ring.sorted {
        xLess($0, $1) || !xLess($1, $0) && yLess($0, $1)
    }
    func half(_ points: Ring) -> Ring {
        var result: Ring = []
        for point in points {
            while result.count >= 2 && cross(result[result.count - 2], result.last!, point) <= 0 {
                result.removeLast()
            };
            result.append(point)
        }
        return Array(result.dropLast())
    }
    return half(sorted) + half(Array(sorted.reversed()))
}
func twiceArea(_ ring: Ring) -> Int128 {
    ring.indices.reduce(0) {
        $0 + ring[$1].x * ring[($1 + 1) % ring.count].y - ring[($1 + 1) % ring.count].x * ring[$1].y
    }
}
struct Values {
    let lines: [String], rings: Int, holes: Int, vertices: Int, area: Double
}
func resultValues(_ region: Region, _ a: Rings, _ b: Rings?) -> Values {
    let rings = region.reduce(0) {
        $0 + $1.count
    }, holes = rings - region.count, vertices = region.flatMap {
        $0
    }.reduce(0) {
        $0 + $1.count
    }, area = RingOps.totalArea(region)
    var lines = ["polygons \(region.count) rings \(rings) holes \(holes) vertices \(vertices) area \(realText(area))"]
    var sx = 0.0, sy = 0.0, perimeter = 0.0, origins = [0, 0, 0], points: Ring = []
    for (k, polygon) in region.enumerated() {
        for (j, ring) in polygon.enumerated() {
            let label = j == 0 ? "outer \(k + 1)" : "hole \(k + 1) \(j)"
            lines.append("\(label) \(ring.count) \(realText(RingOps.area(ring))) " + ring.map(\.description).joined(separator: " "))
            perimeter += RingOps.perimeter(ring)
            for i in ring.indices {
                let (x1, y1) = ring[i].real, (x2, y2) = ring[(i + 1) % ring.count].real, c = x1 * y2 - x2 * y1
                sx += (x1 + x2) * c;
                sy += (y1 + y2) * c
                let v = ring[i]
                if a.contains(where: {
                    $0.contains(v)
                }) {
                    origins[0] += 1
                }
                else if b?.contains(where: {
                    $0.contains(v)
                }) == true {
                    origins[1] += 1
                }
                else {
                    origins[2] += 1
                }
                points.append(v)
            }
        }
    }
    if points.isEmpty {
        lines += ["bbox none", "centroid none"]
    }
    else {
        let minX = points.min(by: xLess)!, minY = points.min(by: yLess)!, maxX = points.max(by: xLess)!, maxY = points.max(by: yLess)!
        let low = Point(minX.x * minY.d, minY.y * minX.d, minX.d * minY.d), high = Point(maxX.x * maxY.d, maxY.y * maxX.d, maxX.d * maxY.d)
        lines.append("bbox \(low) \(high)")
        lines.append("centroid (\(realText(sx / (6 * area))),\(realText(sy / (6 * area))))")
    }
    lines += ["perimeter \(realText(perimeter))", "origins a \(origins[0]) b \(origins[1]) crossing \(origins[2])"]
    return Values(lines: lines, rings: rings, holes: holes, vertices: vertices, area: area)
}
func properties(_ polygon: Polygon, _ area: Double) -> [String] {
    let orientations = polygon.input.map {
        twiceArea($0) > 0 ? "ccw" : "cw"
    }.joined(separator: " ")
    let reflex = polygon.rings.reduce(0) {
        total, ring in total + ring.indices.filter {
            cross(ring[($0 + ring.count - 1) % ring.count], ring[$0], ring[($0 + 1) % ring.count]) < 0
        }.count
    }
    let hull = convexHull(polygon.rings[0]), hullArea = Double(twiceArea(hull)) / 2
    return ["input \(orientations)", "reflex \(reflex)", "hull \(hull.count) \(realText(hullArea)) solidity \(realText(area / hullArea, 6))"]
}
let kinds = ["UNION", "INTERSECTION", "DIFFERENCE", "XOR", "CLIP", "AREA", "MOVE", "ROTATE", "MIRROR", "SNAP", "LOCATE", "RENDER"]
func arguments(_ a: [String]) -> Bool {
    let expected: Int
    switch a[0] {
        case "UNION", "INTERSECTION", "DIFFERENCE", "XOR", "CLIP", "SNAP": expected = 3
        case "AREA": expected = 2
        case "LOCATE": expected = 4
        case "MOVE", "MIRROR": expected = 5
        case "ROTATE": expected = 6
        case "RENDER": expected = 8
        default: return false
    }
    if a.count != expected {
        return false
    }
    func valid(_ i: Int, _ low: Int128, _ high: Int128) -> Bool {
        integer(a[i]).map {
            low <= $0 && $0 <= high
        } ?? false
    }
    switch a[0] {
        case "LOCATE": return valid(2, 0, 1000) && valid(3, 0, 1000)
        case "RENDER":
        if !(valid(2, 0, 1000) && valid(3, 0, 1000) && valid(4, 1, 100) && valid(5, 1, 100) && valid(6, 1, 100) && valid(7, 1, 60)) {
            return false
        }
        let v = a.dropFirst(2).map {
            integer($0)!
        }
        return v[0] + v[2] * v[4] <= 1000 && v[1] + v[3] * v[5] <= 1000
        case "MOVE": return valid(2, -1000, 1000) && valid(3, -1000, 1000) && validName(a[4])
        case "ROTATE": return valid(2, 0, 1000) && valid(3, 0, 1000) && valid(4, 1, 3) && validName(a[5])
        case "MIRROR": return (a[2] == "x" || a[2] == "y") && valid(3, 0, 1000) && validName(a[4])
        case "SNAP": return validName(a[2])
        default: return true
    }
}
struct Operation {
    var lines: [String] = [], area: String?, drawing: [String] = [], target: Target?, definition: (String, Polygon)?
    var crossings = 0
}
func operation(_ number: Int, _ text: String, _ polygons: Polygons, _ results: [Int: Target]) throws -> Operation {
    let a = text.split(separator: " ").map(String.init), kind = a[0]
    if !kinds.contains(kind) {
        throw Rejection("unknown_operation \(kind)")
    }
    if !arguments(a) {
        throw Rejection("bad_arguments")
    }
    let binary = kinds.prefix(5).contains(kind), defining = ["MOVE", "ROTATE", "MIRROR", "SNAP"].contains(kind)
    let input = binary || ["AREA", "MOVE", "ROTATE", "MIRROR"].contains(kind) ? try polygons.get(a[1]) : nil
    let b = binary ? try polygons.get(a[2]) : nil
    let resolved = ["LOCATE", "RENDER", "SNAP"].contains(kind) ? try target(a[1], polygons, results) : nil
    let newName = defining ? a.last : nil
    if let name = newName, polygons.used.contains(name) {
        throw Rejection("duplicate_name \(name)")
    }
    if kind == "SNAP" && resolved!.region.count != 1 {
        throw Rejection("not_single \(a[1])")
    }
    if kind == "CLIP" && !convex(b!.rings) {
        throw Rejection("not_convex \(a[2])")
    }
    if binary, let reason = general(input!.rings, b!.rings, a[1], a[2]) {
        throw Rejection(reason)
    }
    var op = Operation(lines: ["op \(number) \(text)"])
    if kind == "LOCATE" {
        let target = resolved!, point = Point(integer(a[2])!, integer(a[3])!)
        op.lines.append("location \(locate(target.region, point))")
        if let (a, b) = target.operands {
            op.lines.append("operands a \(operandLocation(point, a)) b \(operandLocation(point, b))")
        }
        return op
    }
    if kind == "RENDER" {
        let target = resolved!, values = a.dropFirst(2).map {
            integer($0)!
        }
        let (drawing, counts) = Render.draw(target.region, target.operands, values)
        op.drawing = ["render \(number) \(a[1]) cols \(values[4]) rows \(values[5]) result \(counts[0]) a \(counts[1]) b \(counts[2]) both \(counts[3])"] + drawing
        op.lines = []
        return op
    }
    var polygon = input
    if defining {
        let inputRings: Rings
        if kind == "SNAP" {
            inputRings = resolved!.region[0].map {
                $0.map(\.snapped)
            }
        }
        else {
            inputRings = input!.input.map {
                ring in ring.map {
                    p in
                    var x = p.x, y = p.y
                    switch kind {
                        case "MOVE": x += integer(a[2])!;
                        y += integer(a[3])!
                        case "ROTATE":
                        let cx = integer(a[2])!, cy = integer(a[3])!, q = Int(integer(a[4])!)
                        for _ in 0..<q {
                            let nx = cx - (y - cy), ny = cy + (x - cx);
                            x = nx;
                            y = ny
                        }
                        default:
                        let c = integer(a[3])!
                        if a[2] == "x" {
                            x = 2 * c - x
                        } else {
                            y = 2 * c - y
                        }
                    }
                    return Point(x, y)
                }
            }
        }
        if kind == "SNAP" {
            if let reason = validate(inputRings) {
                throw Rejection("invalid_result \(reason)")
            }
        }
        else if inputRings.flatMap({
            $0
        }).contains(where: {
            $0.x < 0 || $0.y < 0 || $0.x > 1000 || $0.y > 1000
        }) {
            throw Rejection("out_of_range \(newName!)")
        }
        let defined = Polygon(input: inputRings, rings: RingOps.canonical(inputRings))
        op.definition = (newName!, defined)
        polygon = defined
    }
    let region: Region
    if binary {
        let aRings = input!.rings, bRings = b!.rings, graph = Graph(aRings, bRings)
        let relation: String
        if !graph.ordered.isEmpty {
            relation = "overlap"
        }
        else if graph.na == aRings.count && graph.nb == 0 {
            relation = "within"
        }
        else if graph.nb == bRings.count && graph.na == 0 {
            relation = "contains"
        }
        else if graph.na == 0 && graph.nb == 0 {
            relation = "disjoint"
        }
        else {
            relation = "overlap"
        }
        let union = graph.result("UNION"), intersection = graph.result("INTERSECTION")
        let iou = RingOps.totalArea(intersection) / RingOps.totalArea(union)
        op.crossings = graph.ordered.count
        op.lines += ["relation \(relation) iou \(realText(iou, 6))", "crossings \(op.crossings)"]
        for (point, enter) in graph.ordered {
            op.lines.append("crossing \(point) \(enter ? "in" : "out")")
        }
        switch kind {
            case "UNION": region = union
            case "INTERSECTION", "CLIP": region = intersection
            case "DIFFERENCE": region = graph.result("DIFFERENCE")
            default: region = (graph.result("DIFFERENCE") + Graph(bRings, aRings).result("DIFFERENCE")).sorted {
                $0[0][0] < $1[0][0]
            }
        }
        op.target = Target(region: region, operands: (aRings, bRings))
    } else {
        region = [polygon!.rings];
        op.target = Target(region: region, operands: nil)
    }
    let operandA = binary ? input!.rings : polygon!.rings
    let values = resultValues(region, operandA, b?.rings)
    op.lines += values.lines
    op.area = "\(number):\(a.joined(separator: ":")),\(values.rings),\(values.holes),\(values.vertices),\(realText(values.area))"
    if !binary {
        op.lines += properties(polygon!, values.area)
    }
    if kind == "CLIP" {
        let clipped = clip(operandA, b!.rings[0]), resultRings = region.flatMap {
            $0
        }
        let match = resultRings.count == clipped.count && resultRings.allSatisfy {
            ring in clipped.contains {
                cyclic(ring, $0)
            }
        }
        op.lines.append("crosscheck \(match ? "match" : "mismatch") rings \(clipped.count) vertices \(clipped.reduce(0) { $0 + $1.count })")
    }
    return op
}
func write(_ name: String, _ lines: [String]) {
    try! FileManager.default.createDirectory(atPath: "output", withIntermediateDirectories: true)
    try! (lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n").write(toFile: "output/" + name, atomically: false, encoding: .ascii)
}
func runProgram() {
    var polygons = Polygons.read(), targets: [Int: Target] = [:]
    var rejections = polygons.rejected, result: [String] = [], areas = ["operation,rings,holes,vertices,area"], drawing: [String] = []
    var total = 0, succeeded = 0, defined = 0, crossings = 0, counts = Array(repeating: [0, 0], count: kinds.count)
    let lines = try! String(contentsOfFile: "input/operations.txt", encoding: .ascii).components(separatedBy: "\n")
    for line in lines where !line.isEmpty && line.first != "#" {
        total += 1
        let kind = String(line.split(separator: " ")[0]), index = kinds.firstIndex(of: kind)
        if let index {
            counts[index][0] += 1
        }
        do {
            let op = try operation(total, line, polygons, targets)
            succeeded += 1
            counts[index!][1] += 1
            crossings += op.crossings
            result += op.lines
            if let area = op.area {
                areas.append(area)
            }
            drawing += op.drawing
            if let target = op.target {
                targets[total] = target
            }
            if let (name, polygon) = op.definition {
                polygons.used.insert(name);
                polygons.valid[name] = polygon;
                defined += 1
            }
        } catch let error as Rejection {
            rejections.append("op \(total) \(error.reason)")
        }
        catch {
            preconditionFailure()
        }
    }
    result += ["summary polygons \(polygons.blocks) valid \(polygons.validBlocks) invalid \(polygons.blocks - polygons.validBlocks) defined \(defined)",
    "summary operations \(total) succeeded \(succeeded) rejected \(total - succeeded)", "summary crossings \(crossings)"]
    for (i, kind) in kinds.enumerated() {
        result.append("kind \(kind) \(counts[i][0]) \(counts[i][1])")
    }
    rejections.insert("rejections \(rejections.count)", at: 0)
    write("results.txt", result);
    write("areas.csv", areas);
    write("render.txt", drawing);
    write("rejections.txt", rejections)
}
runProgram()
