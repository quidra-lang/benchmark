import Foundation

struct Query {
    let kind: String
    let arguments: [Int]
}

struct Parameters {
    var snap = 1
    var merge = true
    var degenerate = true
    var duplicates = true
    var orient = true
    var outward = true
    var fillHoles = 0
    var keepUnused = true
    var sections = ["summary", "components"]
    var queries: [Query] = []
}

func readParameters() throws -> Parameters {
    var parameters = Parameters()
    for line in try readLines("input/params.txt") where !line.isEmpty && !line.hasPrefix("#") {
        let words = line.split(separator: " ").map(String.init)
        let arguments = Array(words.dropFirst())
        switch words[0] {
        case "snap": parameters.snap = Int(arguments[0])!
        case "merge": parameters.merge = arguments[0] == "on"
        case "degenerate": parameters.degenerate = arguments[0] == "on"
        case "duplicates": parameters.duplicates = arguments[0] == "on"
        case "orient": parameters.orient = arguments[0] == "on"
        case "outward": parameters.outward = arguments[0] == "on"
        case "fill_holes": parameters.fillHoles = Int(arguments[0])!
        case "keep_unused": parameters.keepUnused = arguments[0] == "on"
        case "sections": parameters.sections = arguments
        default: parameters.queries.append(Query(kind: arguments[0], arguments: arguments.dropFirst().map { Int($0)! }))
        }
    }
    return parameters
}

struct BoundaryLoop {
    let number: Int
    let component: Int
    let vertices: [Int]
    let length: Int
    let kind: String
    var filled = false
}

struct ComponentProperties {
    let topology: ComponentTopology
    let closed: Bool
    let manifold: Bool
    let consistent: Bool
    let solid: Bool
    let orientable: Bool
    let loops: Int
    let euler: Int
    let genus: Int?
    let crosscaps: Int?
    let sixVolume: Int
    let center: [String]?
    let area: Double
    let normalSum: Vector3
    let box: [Int]
    let inside: [Int]
    let angles: [String: Int]
    let edgeMinimum: Int
    let edgeMaximum: Int
    let valenceMinimum: Int
    let valenceMaximum: Int
}

func polygonIsNonplanar(_ polygon: Polygon, _ points: [Vector3]) -> Bool {
    let origin = points[polygon.vertices[0]]
    var total = Vector3.zero
    for index in 1..<(polygon.vertices.count - 1) {
        total = add(total, cross(subtract(points[polygon.vertices[index]], origin),
                                 subtract(points[polygon.vertices[index + 1]], origin)))
    }
    return polygon.vertices.contains { dot(subtract(points[$0], origin), total) != 0 }
}

func classifyLoops(_ mesh: MeshTopology, _ faces: [Face]) -> [BoundaryLoop] {
    boundaryTraces(mesh).enumerated().map { index, trace in
        var vertices = trace.vertices
        let kind: String
        if !trace.closed { kind = "open" }
        else {
            let directions = vertices.indices.map { position in
                let first = vertices[position]
                let second = vertices[(position + 1) % vertices.count]
                let faceID = mesh.edges[EdgeKey(first, second)]![0]
                return hasDirected(faces[faceID - 1].vertices, first, second)
            }
            if directions.allSatisfy({ $0 }) { kind = "coherent" }
            else if directions.allSatisfy({ !$0 }) {
                kind = "coherent"
                vertices = [vertices[0]] + Array(vertices.dropFirst().reversed())
            } else { kind = "mixed" }
        }
        return BoundaryLoop(number: index + 1, component: trace.component, vertices: vertices,
                             length: trace.closed ? vertices.count : vertices.count - 1, kind: kind)
    }
}

func isSolid(_ component: ComponentTopology, _ inconsistent: Set<EdgeKey>) -> Bool {
    component.boundary.isEmpty && component.nonmanifold.isEmpty && component.nonmanifoldVertices.isEmpty
        && !component.edges.contains { inconsistent.contains($0) }
}

func edgeShape(_ edge: EdgeKey, _ faces: [Face], _ points: [Vector3], _ adjacent: [Int]) -> String {
    if adjacent.count != 2 { return "-" }
    let first = faces[adjacent[0] - 1]
    let second = faces[adjacent[1] - 1]
    if hasDirected(first.vertices, edge.first, edge.second) == hasDirected(second.vertices, edge.first, edge.second) {
        return "inconsistent"
    }
    let third = second.vertices.first { !edge.contains($0) }!
    let signed = dot(subtract(points[third], points[first.vertices[0]]), normal(first, points))
    return signed < 0 ? "convex" : signed > 0 ? "concave" : "flat"
}

func componentProperties(_ faces: [Face], _ points: [Vector3], _ mesh: MeshTopology,
                         _ loopCounts: [Int: Int], _ orientability: [Int: Bool],
                         _ nesting: [Int: [Int]]) -> [ComponentProperties] {
    let inconsistent = Set(inconsistentEdges(faces, mesh.edges))
    return mesh.components.map { component in
        let closed = component.boundary.isEmpty
        let manifold = component.nonmanifold.isEmpty && component.nonmanifoldVertices.isEmpty
        let consistent = !component.edges.contains { inconsistent.contains($0) }
        let solid = closed && manifold && consistent
        let orientable = orientability[component.number]!
        let loops = loopCounts[component.number, default: 0]
        let euler = component.vertices.count - component.edges.count + component.faces.count
        let genus = manifold && orientable ? floorDivide(2 - euler - loops, 2) : nil
        let crosscaps = manifold && !orientable ? 2 - euler - loops : nil
        let signed = volume6(component.faces, faces, points)
        let center = solid && signed != 0 ? centroid(component.faces, faces, points, signed) : nil
        var totalNormal = Vector3.zero
        var angles: [String: Int] = [:]
        for faceID in component.faces {
            totalNormal = add(totalNormal, normal(faces[faceID - 1], points))
            angles[triangleAngle(faces[faceID - 1], points), default: 0] += 1
        }
        var degrees: [Int: Int] = [:]
        for edge in component.edges {
            degrees[edge.first, default: 0] += 1
            degrees[edge.second, default: 0] += 1
        }
        let lengths = component.edges.map { edgeLengthSquared($0, points) }
        return ComponentProperties(topology: component, closed: closed, manifold: manifold, consistent: consistent,
                                    solid: solid, orientable: orientable, loops: loops, euler: euler, genus: genus,
                                    crosscaps: crosscaps, sixVolume: signed, center: center,
                                    area: area(component.faces.map { faces[$0 - 1] }, points), normalSum: totalNormal,
                                    box: boundingBox(component.vertices, points), inside: solid ? nesting[component.number, default: []] : [],
                                    angles: angles, edgeMinimum: lengths.min()!, edgeMaximum: lengths.max()!,
                                    valenceMinimum: degrees.values.min()!, valenceMaximum: degrees.values.max()!)
    }
}

final class MeshAnalysis {
    let source: OBJSource
    let settings: Parameters
    let snapped: [Vector3]
    let changes: [SnappedVertex]
    let representative: [Int]
    let triangles: [Face]
    let removed: [RemovedTriangle]
    let points: [Vector3]
    var faces: [Face]
    let renumber: [Int: Int]
    let initialFaceCount: Int
    let meshBefore: MeshTopology
    let initialInconsistent: [EdgeKey]
    let inconsistentAfter: [EdgeKey]
    var loopsBefore: [BoundaryLoop]
    let fillFaceCount: Int
    let mesh: MeshTopology
    let components: [ComponentProperties]
    let outwardComponents: Int
    let flippedFaces: Int
    let nonplanar: Set<Int>
    let groupOrder: [String]
    let groupFaces: [String: [Int]]
    var mergedCount: Int { (1..<representative.count).filter { representative[$0] != $0 }.count }

    init(_ source: OBJSource, _ settings: Parameters) {
        self.source = source
        self.settings = settings
        let snapping = snappedVertices(source.vertices, settings.snap)
        snapped = snapping.points
        changes = snapping.changes
        representative = representatives(snapping.points, merge: settings.merge)
        triangles = splitPolygons(source.polygons)
        let cleaned = cleanedFaces(triangles, snapped, representative,
                                   removeZero: settings.degenerate, removeDuplicate: settings.duplicates)
        removed = cleaned.removed
        let remapped = remapVertices(snapped, representative, cleaned.faces, keepUnused: settings.keepUnused)
        points = remapped.points
        renumber = remapped.numbers
        var currentFaces = remapped.faces
        initialFaceCount = currentFaces.count
        let initialOrientations = currentFaces.map { $0.vertices }
        meshBefore = analyzeMesh(currentFaces)
        initialInconsistent = inconsistentEdges(currentFaces, meshBefore.edges)
        if settings.orient { repairOrientation(&currentFaces, meshBefore.edges) }
        inconsistentAfter = inconsistentEdges(currentFaces, meshBefore.edges)
        let violations = Set(inconsistentAfter)
        let permitted = Set(meshBefore.components.filter {
            $0.nonmanifold.isEmpty && !$0.edges.contains { violations.contains($0) }
        }.map { $0.number })
        var loops = classifyLoops(meshBefore, currentFaces)
        var added = 0
        for index in loops.indices {
            let loop = loops[index]
            if loop.kind == "coherent" && loop.length >= 3 && loop.length <= settings.fillHoles
                && Set(loop.vertices).count == loop.length && permitted.contains(loop.component) {
                let newFaces = holeTriangles(loop.vertices)
                currentFaces += newFaces
                added += newFaces.count
                loops[index].filled = true
            }
        }
        loopsBefore = loops
        fillFaceCount = added
        mesh = analyzeMesh(currentFaces)
        let inconsistent = Set(inconsistentEdges(currentFaces, mesh.edges))
        let solids = mesh.components.filter { isSolid($0, inconsistent) }
        var nesting: [Int: [Int]] = [:]
        for component in solids {
            var inside: [Int] = []
            for other in solids where other.number != component.number {
                let otherVertices = Set(other.vertices)
                if let vertex = component.vertices.first(where: { !otherVertices.contains($0) }),
                   windingNumber(other.faces, currentFaces, points, points[vertex]) != 0 { inside.append(other.number) }
            }
            nesting[component.number] = inside
        }
        var flipped = 0
        if settings.outward {
            for component in solids {
                let signed = volume6(component.faces, currentFaces, points)
                let depth = nesting[component.number, default: []].count
                if signed != 0 && ((depth % 2 == 0 && signed < 0) || (depth % 2 == 1 && signed > 0)) {
                    for faceID in component.faces { flip(&currentFaces[faceID - 1]) }
                    flipped += 1
                }
            }
        }
        outwardComponents = flipped
        flippedFaces = initialOrientations.indices.filter { currentFaces[$0].vertices != initialOrientations[$0] }.count
        faces = currentFaces
        let orientability = orientableComponents(currentFaces, mesh)
        var loopCounts: [Int: Int] = [:]
        for trace in boundaryTraces(mesh) { loopCounts[trace.component, default: 0] += 1 }
        components = componentProperties(currentFaces, points, mesh, loopCounts, orientability, nesting)
        nonplanar = Set(source.polygons.filter { polygonIsNonplanar($0, snapping.points) }.map { $0.number })
        var order: [String] = []
        for polygon in source.polygons where !order.contains(polygon.group) { order.append(polygon.group) }
        if added > 0 { order.append("fill") }
        groupOrder = order
        var groups: [String: [Int]] = [:]
        for (index, face) in currentFaces.enumerated() { groups[face.group, default: []].append(index + 1) }
        groupFaces = groups
    }
}

func yes(_ value: Bool) -> String { value ? "yes" : "no" }
func listing(_ values: [Int]) -> String { values.isEmpty ? "-" : values.map(String.init).joined(separator: " ") }
func listing(_ values: [String]) -> String { values.isEmpty ? "-" : values.joined(separator: " ") }

func summarySection(_ data: MeshAnalysis) -> [String] {
    let source = data.source
    var sizes: [Int: Int] = [:]
    for polygon in source.polygons { sizes[polygon.vertices.count, default: 0] += 1 }
    var removals: [String: Int] = [:]
    for removed in data.removed { removals[removed.reason, default: 0] += 1 }
    let signed = data.components.filter { $0.solid }.reduce(0) { $0 + $1.sixVolume }
    var lines = ["[summary]", "lines \(source.lineCount)", "vertices \(source.vertices.count - 1)",
                 "polygons \(source.polygons.count)", "errors \(source.errors.count)", "ignored \(source.ignored)",
                 "nonplanar_polygons \(data.nonplanar.count)"]
    lines += sizes.keys.sorted().map { "polygon_size \($0) \(sizes[$0]!)" }
    lines += ["triangles \(data.triangles.count)", "snapped \(data.changes.count)", "merged \(data.mergedCount)",
              "removed_repeated \(removals["repeated", default: 0])", "removed_zero_area \(removals["zero_area", default: 0])",
              "removed_duplicate \(removals["duplicate", default: 0])", "faces \(data.initialFaceCount)",
              "inconsistent_before \(data.initialInconsistent.count)", "flipped_faces \(data.flippedFaces)",
              "outward_components \(data.outwardComponents)", "boundary_loops \(data.loopsBefore.count)",
              "holes_filled \(data.loopsBefore.filter { $0.filled }.count)", "fill_faces \(data.fillFaceCount)",
              "final_vertices \(data.points.count - 1)", "final_faces \(data.faces.count)",
              "components \(data.components.count)", "solids \(data.components.filter { $0.solid }.count)",
              "total_area \(real(area(data.faces, data.points)))", "total_volume \(fraction(signed, 6))"]
    return lines
}

func warningsSection(_ data: MeshAnalysis) -> [String] {
    ["[warnings]"] + data.source.errors.map { "line \($0.line) \($0.kind)" }
}

func cleanupSection(_ data: MeshAnalysis) -> [String] {
    var lines = ["[cleanup]", "snapped \(data.changes.count)"]
    lines += data.changes.map { "snap \($0.number) \($0.before.text) to \($0.after.text)" }
    lines.append("merged \(data.mergedCount)")
    var members: [Int: [Int]] = [:]
    for number in 1..<data.representative.count { members[data.representative[number], default: []].append(number) }
    for representative in members.keys.sorted() where members[representative]!.count > 1 {
        let number = data.renumber[representative].map(String.init) ?? "-"
        lines.append("merge \(number) \(listing(members[representative]!))")
    }
    lines.append("removed \(data.removed.count)")
    lines += data.removed.map { removed in
        "remove \(removed.face.triangle!) polygon \(removed.face.polygon!) line \(removed.face.line!) \(removed.reason)"
    }
    return lines
}

func shapeCounts(_ edges: [EdgeKey], _ data: MeshAnalysis) -> [String: Int] {
    var counts: [String: Int] = [:]
    for edge in edges { counts[edgeShape(edge, data.faces, data.points, data.mesh.edges[edge]!), default: 0] += 1 }
    return counts
}

func componentsSection(_ data: MeshAnalysis) -> [String] {
    var lines: [String] = []
    for component in data.components {
        let topology = component.topology
        let faceGroups = Set(topology.faces.map { data.faces[$0 - 1].group })
        let groups = data.groupOrder.filter { faceGroups.contains($0) }
        let shapes = shapeCounts(topology.edges, data)
        lines += ["[component \(topology.number)]", "groups \(listing(groups))", "faces \(topology.faces.count)",
                  "vertices \(topology.vertices.count)", "edges \(topology.edges.count)", "boundary_edges \(topology.boundary.count)",
                  "nonmanifold_edges \(topology.nonmanifold.count)", "nonmanifold_vertices \(topology.nonmanifoldVertices.count)",
                  "boundary_loops \(component.loops)", "closed \(yes(component.closed))", "manifold \(yes(component.manifold))",
                  "orientable \(yes(component.orientable))", "consistent \(yes(component.consistent))", "solid \(yes(component.solid))",
                  "euler \(component.euler)"]
        if let genus = component.genus { lines.append("genus \(genus)") }
        else if let crosscaps = component.crosscaps { lines.append("crosscaps \(crosscaps)") }
        else { lines.append("genus -") }
        lines += ["volume \(component.solid ? fraction(component.sixVolume, 6) : "-")", "area \(real(component.area))",
                  "normal_sum \(component.normalSum.text)", "bbox \(listing(component.box))", "inside \(listing(component.inside))",
                  "centroid \(component.center.map(listing) ?? "-")", "convex \(shapes["convex", default: 0])",
                  "concave \(shapes["concave", default: 0])", "flat \(shapes["flat", default: 0])",
                  "acute \(component.angles["acute", default: 0])", "right \(component.angles["right", default: 0])",
                  "obtuse \(component.angles["obtuse", default: 0])", "edge_len2 \(component.edgeMinimum) \(component.edgeMaximum)",
                  "valence \(component.valenceMinimum) \(component.valenceMaximum)"]
    }
    return lines
}

func groupsSection(_ data: MeshAnalysis) -> [String] {
    var lines: [String] = []
    for group in data.groupOrder {
        let polygons = data.source.polygons.filter { $0.group == group }
        let triangles = data.triangles.filter { $0.group == group }
        let assigned = data.groupFaces[group, default: []]
        let components = Set(assigned.map { data.mesh.faceComponents[$0] }).sorted()
        lines += ["[group \(group)]", "polygons \(polygons.count)", "triangles \(triangles.count)",
                  "nonplanar \(polygons.filter { data.nonplanar.contains($0.number) }.count)", "faces \(assigned.count)",
                  "area \(real(area(assigned.map { data.faces[$0 - 1] }, data.points)))", "components \(listing(components))"]
    }
    return lines
}

func contactsSection(_ data: MeshAnalysis) -> [String] {
    var lines = ["[contacts]"]
    for firstIndex in data.components.indices {
        let first = data.components[firstIndex]
        for secondIndex in (firstIndex + 1)..<data.components.count {
            let second = data.components[secondIndex]
            if !(0..<3).allSatisfy({ first.box[$0] <= second.box[$0 + 3] && second.box[$0] <= first.box[$0 + 3] }) { continue }
            let shared = Set(first.topology.vertices).intersection(second.topology.vertices).count
            var gap = Int.max
            for a in first.topology.vertices {
                for b in second.topology.vertices where a != b {
                    let difference = subtract(data.points[a], data.points[b])
                    gap = min(gap, dot(difference, difference))
                }
            }
            lines.append("contact \(first.topology.number) \(second.topology.number) shared \(shared) gap2 \(gap)")
        }
    }
    return lines
}

func edgesSection(_ data: MeshAnalysis) -> [String] {
    let edges = data.mesh.orderedEdges
    let shapes = shapeCounts(edges, data)
    var counts: [Int: Int] = [:]
    var maximum = 0
    var shortest = edges[0]
    var longest = edges[0]
    for edge in edges {
        let count = data.mesh.edges[edge]!.count
        counts[min(3, count), default: 0] += 1
        maximum = max(maximum, count)
        let length = edgeLengthSquared(edge, data.points)
        if length < edgeLengthSquared(shortest, data.points) { shortest = edge }
        if length > edgeLengthSquared(longest, data.points) { longest = edge }
    }
    return ["[edges]", "edges \(edges.count)", "boundary \(counts[1, default: 0])", "manifold \(counts[2, default: 0])",
            "nonmanifold \(counts[3, default: 0])", "max_faces \(maximum)", "convex \(shapes["convex", default: 0])",
            "concave \(shapes["concave", default: 0])", "flat \(shapes["flat", default: 0])", "inconsistent \(shapes["inconsistent", default: 0])",
            "shortest \(shortest.text) len2 \(edgeLengthSquared(shortest, data.points))",
            "longest \(longest.text) len2 \(edgeLengthSquared(longest, data.points))"]
}

func valenceSection(_ data: MeshAnalysis) -> [String] {
    var degrees: [Int: Int] = [:]
    for edge in data.mesh.orderedEdges {
        degrees[edge.first, default: 0] += 1
        degrees[edge.second, default: 0] += 1
    }
    var histogram: [Int: Int] = [:]
    for degree in degrees.values { histogram[degree, default: 0] += 1 }
    var lines = ["[valence]", "used \(degrees.count)", "isolated \(data.points.count - 1 - degrees.count)",
                 "min \(degrees.values.min()!)", "max \(degrees.values.max()!)",
                 "mean \(fraction(degrees.values.reduce(0, +), degrees.count))"]
    lines += histogram.keys.sorted().map { "degree \($0) \(histogram[$0]!)" }
    return lines
}

func vertexQuery(_ vertex: Int, _ data: MeshAnalysis) -> String {
    if vertex < 1 || vertex >= data.points.count { return "vertex \(vertex) invalid" }
    let containing = data.faces.indices.filter { data.faces[$0].vertices.contains(vertex) }.map { $0 + 1 }
    let edges = data.mesh.orderedEdges.filter { $0.contains(vertex) }
    let boundary = edges.contains { data.mesh.edges[$0]!.count == 1 }
    let components = Set(containing.map { data.mesh.faceComponents[$0] }).sorted()
    return "vertex \(vertex) at \(data.points[vertex].text) faces \(containing.count)"
        + " valence \(edges.count) fans \(data.mesh.fans[vertex, default: []].count) boundary \(yes(boundary)) components \(listing(components))"
}

func faceQuery(_ number: Int, _ data: MeshAnalysis) -> String {
    if number < 1 || number > data.faces.count { return "face \(number) invalid" }
    let face = data.faces[number - 1]
    let neighbors = triangleEdges(face.vertices).map { first, second -> String in
        let adjacent = data.mesh.edges[EdgeKey(first, second)]!
        if adjacent.count == 1 { return "-" }
        if adjacent.count >= 3 { return "*" }
        return String(adjacent.first { $0 != number }!)
    }
    return "face \(number) vertices \(listing(face.vertices)) group \(face.group) polygon \(face.polygon.map(String.init) ?? "-") "
        + "line \(face.line.map(String.init) ?? "-") component \(data.mesh.faceComponents[number]) normal \(normal(face, data.points).text) "
        + "area \(real(area([face], data.points))) neighbors \(listing(neighbors))"
}

func edgeQuery(_ first: Int, _ second: Int, _ data: MeshAnalysis) -> String {
    let edge = EdgeKey(first, second)
    guard let adjacent = data.mesh.edges[edge] else { return "edge \(edge.text) none" }
    let kind = adjacent.count == 1 ? "boundary" : adjacent.count == 2 ? "manifold" : "nonmanifold"
    let shape = edgeShape(edge, data.faces, data.points, adjacent)
    return "edge \(edge.text) faces \(listing(adjacent)) kind \(kind) shape \(shape) len2 \(edgeLengthSquared(edge, data.points))"
}

func pointQuery(_ coordinates: [Int], _ data: MeshAnalysis) -> String {
    let point = Vector3(x: coordinates[0], y: coordinates[1], z: coordinates[2])
    var inside: [Int] = []
    var total = 0
    for component in data.components where component.solid {
        let winding = windingNumber(component.topology.faces, data.faces, data.points, point)
        if winding != 0 {
            inside.append(component.topology.number)
            total += winding
        }
    }
    return "point \(point.text) inside \(listing(inside)) winding \(total)"
}

func pathQuery(_ first: Int, _ second: Int, _ data: MeshAnalysis) -> String {
    if first < 1 || first >= data.points.count || second < 1 || second >= data.points.count { return "path \(first) \(second) invalid" }
    var neighbors: [Int: Set<Int>] = [:]
    for edge in data.mesh.orderedEdges {
        neighbors[edge.first, default: []].insert(edge.second)
        neighbors[edge.second, default: []].insert(edge.first)
    }
    var queue = [first]
    var parent = [first: first]
    var head = 0
    while head < queue.count {
        let current = queue[head]
        head += 1
        for other in neighbors[current, default: []].sorted() where parent[other] == nil {
            parent[other] = current
            queue.append(other)
        }
    }
    if parent[second] == nil { return "path \(first) \(second) none" }
    var path = [second]
    var current = second
    while current != first {
        current = parent[current]!
        path.append(current)
    }
    path.reverse()
    return "path \(first) \(second) hops \(path.count - 1) vertices \(listing(path))"
}

func viewQuery(_ coordinates: [Int], _ data: MeshAnalysis) -> String {
    let direction = Vector3(x: coordinates[0], y: coordinates[1], z: coordinates[2])
    let scores = data.faces.map { dot(normal($0, data.points), direction) }
    var silhouette = 0
    for adjacent in data.mesh.edges.values where adjacent.count == 2 {
        let first = scores[adjacent[0] - 1]
        let second = scores[adjacent[1] - 1]
        if (first > 0 && second < 0) || (first < 0 && second > 0) { silhouette += 1 }
    }
    return "view \(direction.text) front \(scores.filter { $0 > 0 }.count) back \(scores.filter { $0 < 0 }.count) "
        + "side \(scores.filter { $0 == 0 }.count) silhouette \(silhouette)"
}

func queriesSection(_ data: MeshAnalysis) -> [String] {
    var lines = ["[queries]"]
    for query in data.settings.queries {
        let arguments = query.arguments
        switch query.kind {
        case "vertex": lines.append(vertexQuery(arguments[0], data))
        case "face": lines.append(faceQuery(arguments[0], data))
        case "edge": lines.append(edgeQuery(arguments[0], arguments[1], data))
        case "point": lines.append(pointQuery(arguments, data))
        case "path": lines.append(pathQuery(arguments[0], arguments[1], data))
        default: lines.append(viewQuery(arguments, data))
        }
    }
    return lines
}

func reportSections(_ data: MeshAnalysis) -> [String] {
    data.settings.sections.flatMap { section -> [String] in
        switch section {
        case "summary": return summarySection(data)
        case "warnings": return warningsSection(data)
        case "cleanup": return cleanupSection(data)
        case "components": return componentsSection(data)
        case "groups": return groupsSection(data)
        case "contacts": return contactsSection(data)
        case "edges": return edgesSection(data)
        case "valence": return valenceSection(data)
        default: return queriesSection(data)
        }
    }
}

func componentCSV(_ data: MeshAnalysis) -> [String] {
    ["component,faces,vertices,closed,euler,genus,volume6,area"] + data.components.map { component in
        [String(component.topology.number), String(component.topology.faces.count), String(component.topology.vertices.count),
         yes(component.closed), String(component.euler), component.genus.map(String.init) ?? "-",
         component.solid ? String(component.sixVolume) : "-", real(component.area)].joined(separator: ",")
    }
}

func boundariesReport(_ data: MeshAnalysis) -> [String] {
    let mesh = data.meshBefore
    var lines = ["loops \(data.loopsBefore.count)"]
    lines += data.loopsBefore.map { loop in
        "loop \(loop.number) component \(loop.component) length \(loop.length) \(loop.kind) \(loop.filled ? "filled" : "kept") "
            + "vertices \(listing(loop.vertices))"
    }
    let nonmanifold = mesh.orderedEdges.filter { mesh.edges[$0]!.count >= 3 }
    lines.append("nonmanifold_edges \(nonmanifold.count)")
    lines += nonmanifold.map { "edge \($0.text) faces \(listing(mesh.edges[$0]!))" }
    lines.append("nonmanifold_vertices \(mesh.nonmanifoldVertices.count)")
    for vertex in mesh.nonmanifoldVertices {
        let components = Set(mesh.fans[vertex]!.flatMap { $0.map { mesh.faceComponents[$0] } }).sorted()
        lines.append("vertex \(vertex) fans \(mesh.fans[vertex]!.count) components \(listing(components))")
    }
    lines.append("inconsistent_edges \(data.inconsistentAfter.count)")
    lines += data.inconsistentAfter.map { "edge \($0.text) faces \(listing(mesh.edges[$0]!))" }
    return lines
}

func writeLines(_ filename: String, _ lines: [String]) throws {
    try FileManager.default.createDirectory(atPath: "output", withIntermediateDirectories: true)
    let text = lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"
    try text.write(toFile: "output/" + filename, atomically: true, encoding: .ascii)
}

let source = try readOBJ()
let parameters = try readParameters()
let analysis = MeshAnalysis(source, parameters)
try writeLines("report.txt", reportSections(analysis))
try writeLines("components.csv", componentCSV(analysis))
try writeLines("boundaries.txt", boundariesReport(analysis))
try writeLines("repaired.obj", repairedOBJ(analysis.points, analysis.faces))
