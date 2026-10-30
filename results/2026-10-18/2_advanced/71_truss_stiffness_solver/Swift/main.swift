import Foundation

func total<S: Sequence>(_ values: S) -> Double where S.Element == Double { var result = 0.0; for value in values { result += value }; return result }
func real(_ value: Double, _ digits: Int = 4) -> String {
    let text = String(format: "%.*f", locale: Locale(identifier: "en_US_POSIX"), digits, value)
    return text.first == "-" && Double(text) == 0 ? String(text.dropFirst()) : text
}
func rounded(_ value: Double) -> Double { Double(real(value))! }
func extremeIndex(_ values: [Double], minimum: Bool = false) -> Int {
    var selected = 0
    for index in values.indices.dropFirst() {
        let next = rounded(values[index]), current = rounded(values[selected])
        if minimum ? next < current : next > current { selected = index }
    }
    return selected
}
func writeLines(_ name: String, _ lines: [String]) throws {
    try FileManager.default.createDirectory(atPath: "output", withIntermediateDirectories: true)
    try (lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n").write(toFile: "output/" + name, atomically: false, encoding: .ascii)
}
func renumber(_ nodes: [Node], _ members: [Member]) -> (order: [Int], neighbors: [Set<Int>]) {
    var neighbors = Array(repeating: Set<Int>(), count: nodes.count)
    for member in members { neighbors[member.start].insert(member.end); neighbors[member.end].insert(member.start) }
    func precedes(_ first: Int, _ second: Int) -> Bool {
        neighbors[first].count == neighbors[second].count ? nodes[first].identifier < nodes[second].identifier : neighbors[first].count < neighbors[second].count
    }
    var queue = [nodes.indices.min(by: precedes)!], visited = Set(queue), head = 0
    while head < queue.count {
        let node = queue[head]; head += 1
        let following = neighbors[node].subtracting(visited).sorted(by: precedes)
        queue += following; visited.formUnion(following)
    }
    return (Array(queue.reversed()), neighbors)
}
func numberingMetrics(_ numbers: [Int], _ neighbors: [Set<Int>], _ members: [Member]) -> (bandwidth: Int, profile: Int) {
    let bandwidth = members.map { abs(numbers[$0.start] - numbers[$0.end]) }.max()!
    var profile = 0
    for node in numbers.indices { profile += numbers[node] - neighbors[node].union([node]).map { numbers[$0] }.min()! }
    return (bandwidth, profile)
}
struct GridPosition { let column: Int; let row: Int }
struct Canvas {
    let x0: Int, y1: Int, horizontal: Int, vertical: Int, width: Int, height: Int
    var grid: [[UInt8]]
    init(_ nodes: [Node], _ horizontal: Int, _ vertical: Int) {
        let x0 = nodes.map { $0.x }.min()!, x1 = nodes.map { $0.x }.max()!, y0 = nodes.map { $0.y }.min()!, y1 = nodes.map { $0.y }.max()!
        let width = Int(floor(Double(x1 - x0) / Double(horizontal) + 0.5)) + 5, height = Int(floor(Double(y1 - y0) / Double(vertical) + 0.5)) + 5
        self.x0 = x0; self.y1 = y1; self.horizontal = horizontal; self.vertical = vertical; self.width = width; self.height = height
        grid = Array(repeating: Array(repeating: 32, count: width), count: height)
    }
    func position(_ x: Double, _ y: Double) -> GridPosition {
        GridPosition(column: Int(floor((x - Double(x0)) / Double(horizontal) + 0.5)) + 2, row: Int(floor((Double(y1) - y) / Double(vertical) + 0.5)) + 2)
    }
    mutating func put(_ position: GridPosition, _ character: UInt8) {
        if position.column >= 0 && position.column < width && position.row >= 0 && position.row < height { grid[position.row][position.column] = character }
    }
    mutating func line(_ first: GridPosition, _ last: GridPosition, _ character: UInt8) {
        var column = first.column, row = first.row
        let dc = abs(last.column - column), dr = -abs(last.row - row), sc = column < last.column ? 1 : -1, sr = row < last.row ? 1 : -1
        var error = dc + dr
        while true {
            put(GridPosition(column: column, row: row), character)
            if column == last.column && row == last.row { break }
            let twice = 2 * error
            if twice >= dr { error += dr; column += sc }
            if twice <= dc { error += dc; row += sr }
        }
    }
    func framed() -> [String] {
        let border = "+" + String(repeating: "-", count: width) + "+"
        return [border] + grid.map { "|" + String(decoding: $0, as: UTF8.self) + "|" } + [border]
    }
}
struct DofOwner { let node: Int; let axis: Int }
struct SupportDirection { let node: Int; let axis: Int; let degree: Int }
struct Group { let name: String; var members: [Int] }
struct GroupChange { let group: Int; let current: Int; let chosen: Int; let utilization: Double }
struct System { let properties: [Properties]; let matrix: [[Double]]; let freeMatrix: [[Double]]; let lower: [[Double]]?; let unstable: Int?; let removed: Int? }
final class Truss {
    let model: Model
    var nodes: [Node] { model.nodes }
    var members: [Member] { model.members }
    var settings: Settings { model.settings }
    var degrees: Int { 2 * nodes.count }
    var order: [Int] = [], numbers: [Int] = []
    var neighbors: [Set<Int>] = []
    var nodeDofs: [[Int]] = []
    var owners: [DofOwner] = []
    var prescribed: [Double] = []
    var supportDirections: [SupportDirection] = []
    var restrained: [Int] = [], free: [Int] = []
    var geometry: [Geometry] = []
    var groups: [Group] = []
    var resultOrder: [(kind: String, name: String)] { model.cases.map { ("case", $0.name) } + model.combinations.map { ("combination", $0.name) } }
    var deck: [Int] { settings.deck }
    var deckX: [Int] { deck.map { nodes[$0].x } }
    var choices: [Int] = []
    var finalSystem: System!
    var properties: [Properties] = []
    var results: [String: Result] = [:]
    var combinations: [Result] = []
    var limits: [Double] = []
    var utilizations: [[Double]] = []
    var weight = 0.0
    var governingCases: [Int] = []
    var governing: [Double] = []
    var units: [Int: Result] = [:]
    init(_ model: Model) {
        self.model = model
        let numbering = renumber(nodes, members)
        order = numbering.order; neighbors = numbering.neighbors; numbers = Array(repeating: 0, count: nodes.count)
        for (number, node) in order.enumerated() { numbers[node] = number }
        nodeDofs = numbers.map { [2 * $0, 2 * $0 + 1] }
        owners = order.flatMap { [DofOwner(node: $0, axis: 0), DofOwner(node: $0, axis: 1)] }
        prescribed = Array(repeating: 0, count: degrees)
        for support in model.supports {
            for axis in 0..<2 where support.fixed[axis] {
                let degree = nodeDofs[support.node][axis]
                prescribed[degree] = support.prescribed[axis]
                supportDirections.append(SupportDirection(node: support.node, axis: axis, degree: degree))
            }
        }
        restrained = supportDirections.map { $0.degree }.sorted()
        let fixed = Set(restrained)
        free = (0..<degrees).filter { !fixed.contains($0) }
        geometry = memberGeometry(nodes, members, nodeDofs)
        for (number, member) in members.enumerated() {
            if let index = groups.firstIndex(where: { $0.name == member.group }) { groups[index].members.append(number) }
            else { groups.append(Group(name: member.group, members: [number])) }
        }
    }
    func system(_ choices: [Int], _ removed: Int? = nil) -> System {
        let properties = memberProperties(model, choices, geometry), matrix = assemble(geometry, properties, degrees, removed)
        let freeMatrix = free.map { row in free.map { matrix[row][$0] } }, factorization = cholesky(freeMatrix, free)
        return System(properties: properties, matrix: matrix, freeMatrix: freeMatrix, lower: factorization.lower, unstable: factorization.unstable, removed: removed)
    }
    func displacement(_ system: System, _ force: [Double], settlement: Bool = false) -> [Double] {
        var displacement = Array(repeating: 0.0, count: degrees), right: [Double] = []
        for degree in restrained { displacement[degree] = settlement ? prescribed[degree] : 0 }
        for degree in free {
            var value = force[degree]
            for fixed in restrained { value -= system.matrix[degree][fixed] * displacement[fixed] }
            right.append(value)
        }
        for (degree, value) in zip(free, solve(system.lower!, right)) { displacement[degree] = value }
        return displacement
    }
    func caseResult(_ system: System, _ loadCase: LoadCase) -> Result {
        let loading = loadVectors(loadCase, geometry, system.properties, nodeDofs, degrees, system.removed)
        let displacement = self.displacement(system, loading.total, settlement: loading.settlement)
        let forces = axialForces(geometry, system.properties, displacement, loading.temperature, system.removed)
        let reaction = reactions(system.matrix, displacement, loading.total, restrained)
        return Result(name: loadCase.name, displacement: displacement, forces: forces, reactions: reaction, external: loading.external)
    }
    func analyze(_ system: System, _ combination: Combination? = nil) -> [String: Result] {
        let combinations = combination.map { [$0] } ?? model.combinations, needed = Set(combinations.flatMap { $0.terms.map { $0.name } })
        var results: [String: Result] = [:]
        for loadCase in model.cases where combination == nil || needed.contains(loadCase.name) { results[loadCase.name] = caseResult(system, loadCase) }
        for combination in combinations { results[combination.name] = superpose(combination, results) }
        return results
    }
    func unitResult(_ node: Int) -> Result {
        if let result = units[node] { return result }
        var force = Array(repeating: 0.0, count: degrees); force[nodeDofs[node][1]] = -1000
        let displacement = self.displacement(finalSystem, force)
        let forces = axialForces(geometry, properties, displacement, Array(repeating: 0, count: members.count))
        let reaction = reactions(finalSystem.matrix, displacement, force, restrained)
        let result = Result(name: "unit", displacement: displacement, forces: forces, reactions: reaction, external: force)
        units[node] = result
        return result
    }
    func designSections() -> [String] {
        var choices = members.map { $0.section }, history: [String] = [], round = 1
        while true {
            let system = self.system(choices), results = analyze(system), combinations = model.combinations.map { results[$0.name]! }
            let limits = members.indices.map { slendernessLimit($0, combinations, settings.slenderness) }
            let utilizations = members.indices.map { number in combinations.map { utilization($0.forces[number], system.properties[number], geometry[number]) } }
            let flat = utilizations.flatMap { $0 }, maximum = extremeIndex(flat), member = maximum / combinations.count, combination = maximum % combinations.count
            let weight = total(members.indices.map { memberWeight(system.properties[$0], geometry[$0]) })
            var changes: [GroupChange] = []
            for (index, group) in groups.enumerated() {
                let chosen = selectSection(group.members, model.sections, system.properties, geometry, combinations, limits), current = choices[group.members[0]]
                if chosen != current {
                    let values = group.members.flatMap { utilizations[$0] }
                    changes.append(GroupChange(group: index, current: current, chosen: chosen, utilization: values[extremeIndex(values)]))
                }
            }
            history.append("round \(round) weight \(real(weight / 1000)) max_utilization \(real(flat[maximum])) at \(members[member].identifier) \(combinations[combination].name) changes \(changes.count)")
            for change in changes { history.append("change \(groups[change.group].name) \(model.sections[change.current].name) \(model.sections[change.chosen].name) utilization \(real(change.utilization))") }
            if changes.isEmpty || round == 10 {
                self.choices = choices; finalSystem = system; properties = system.properties; self.results = results; self.combinations = combinations
                self.limits = limits; self.utilizations = utilizations; self.weight = weight
                governingCases = utilizations.map { extremeIndex($0) }; governing = utilizations.indices.map { utilizations[$0][governingCases[$0]] }
                history.append("result \(changes.isEmpty ? "converged" : "not_converged") rounds \(round)")
                return history
            }
            for change in changes { for member in groups[change.group].members { choices[member] = change.chosen } }
            round += 1
        }
    }
    func magnitudes(_ result: Result) -> [Double] {
        nodeDofs.map { let x = result.displacement[$0[0]], y = result.displacement[$0[1]]; return sqrt(x * x + y * y) }
    }
    func designReport(_ history: [String]) -> [String] {
        var lines = history
        for group in groups {
            let number = group.members[extremeIndex(group.members.map { governing[$0] })], section = model.sections[choices[group.members[0]]].name
            lines.append("group \(group.name) section \(section) members \(group.members.count) utilization \(real(governing[number])) at \(members[number].identifier)")
        }
        for number in members.indices {
            let member = members[number], section = model.sections[choices[number]].name, value = governing[number]
            let slender = slenderness(properties[number], geometry[number]), limit = limits[number], combination = combinations[governingCases[number]].name
            lines.append("member \(member.identifier) group \(member.group) section \(section) utilization \(real(value)) governing \(combination) slenderness \(real(slender)) limit \(real(limit)) \(value <= 1 && slender <= limit ? "ok" : "over")")
        }
        let ranking = members.indices.sorted { rounded(governing[$0]) == rounded(governing[$1]) ? $0 < $1 : rounded(governing[$0]) > rounded(governing[$1]) }
        for (rank, number) in ranking.prefix(5).enumerated() { lines.append("rank \(rank + 1) member \(members[number].identifier) utilization \(real(governing[number]))") }
        for number in members.indices {
            let values = combinations.map { $0.forces[number] / 1000 }, largest = extremeIndex(values), smallest = extremeIndex(values, minimum: true)
            lines.append("envelope \(members[number].identifier) max \(real(values[largest])) \(combinations[largest].name) min \(real(values[smallest])) \(combinations[smallest].name)")
        }
        for (section, description) in model.sections.enumerated() {
            let members = self.members.indices.filter { choices[$0] == section }
            if !members.isEmpty { lines.append("section \(description.name) members \(members.count) length \(real(total(members.map { geometry[$0].length })))") }
        }
        lines.append("weight " + real(weight / 1000))
        return lines
    }
}
extension Truss {
    func resultSummary(_ kind: String, _ result: Result) -> String {
        let magnitudes = self.magnitudes(result), node = extremeIndex(magnitudes)
        let energy = total(members.indices.map { result.forces[$0] * result.forces[$0] * geometry[$0].length / (2 * properties[$0].young * properties[$0].area) }) / 1000
        let reactionsTotal = (0..<2).map { axis in total(nodeDofs.map { result.reactions[$0[axis]] }) / 1000 }
        let forcesTotal = (0..<2).map { axis in total(nodeDofs.map { result.external[$0[axis]] }) / 1000 }
        let scale = max(1, max(result.external.map(abs).max()!, result.reactions.map(abs).max()!))
        let equilibrium = equilibriumResidual(result, geometry) <= 0.000001 * scale ? "ok" : "failed"
        return "\(kind) \(result.name) equilibrium \(equilibrium) max_displacement \(real(magnitudes[node])) at \(nodes[node].identifier) energy \(real(energy)) reactions \(real(reactionsTotal[0])) \(real(reactionsTotal[1])) loads \(real(forcesTotal[0])) \(real(forcesTotal[1]))"
    }
    func analysisReport() -> [String] {
        let before = numberingMetrics(Array(nodes.indices), neighbors, members), after = numberingMetrics(numbers, neighbors, members)
        let indeterminacy = members.count + restrained.count - 2 * nodes.count
        var lines = ["model nodes \(nodes.count) members \(members.count) supports \(model.supports.count) free_dofs \(free.count) restrained_dofs \(restrained.count) indeterminacy \(indeterminacy)", "renumbering " + order.map { String(nodes[$0].identifier) }.joined(separator: " "), "bandwidth before \(before.bandwidth) after \(after.bandwidth)", "profile before \(before.profile) after \(after.profile)"]
        for (member, shape) in zip(members, geometry) { lines.append("member \(member.identifier) nodes \(nodes[member.start].identifier) \(nodes[member.end].identifier) length \(real(shape.length)) cos \(real(shape.cosine, 6)) sin \(real(shape.sine, 6))") }
        for item in resultOrder { lines.append(resultSummary(item.kind, results[item.name]!)) }
        for support in supportDirections {
            let values = combinations.map { $0.reactions[support.degree] / 1000 }, largest = extremeIndex(values), smallest = extremeIndex(values, minimum: true)
            var line = "reaction_envelope \(nodes[support.node].identifier) \(support.axis == 0 ? "x" : "y") max \(real(values[largest])) \(combinations[largest].name) min \(real(values[smallest])) \(combinations[smallest].name)"
            if support.axis == 1 { line += " uplift " + (values.contains { $0 < 0 } ? "yes" : "no") }
            lines.append(line)
        }
        let displacements = combinations.map { magnitudes($0) }
        for (node, description) in nodes.enumerated() {
            let values = displacements.map { $0[node] }, largest = extremeIndex(values)
            lines.append("displacement_envelope \(description.identifier) max \(real(values[largest])) \(combinations[largest].name)")
        }
        lines += deflectionReport(); lines += removalReport()
        return lines
    }
    func deflectionReport() -> [String] {
        let name = settings.deflectionName, result = results[name]!
        let fixed = Set(supportDirections.filter { $0.axis == 1 }.map { $0.node }), anchors = deck.indices.filter { fixed.contains(deck[$0]) }
        var lines: [String] = []
        for index in 0..<(anchors.count - 1) {
            let first = anchors[index], last = anchors[index + 1], left = deck[first], right = deck[last], xa = deckX[first], xb = deckX[last]
            let va = result.displacement[nodeDofs[left][1]], vb = result.displacement[nodeDofs[right][1]], interior = Array((first + 1)..<last)
            let deflections = interior.map { abs(result.displacement[nodeDofs[deck[$0]][1]] - (va + (vb - va) * Double(deckX[$0] - xa) / Double(xb - xa))) }
            let chosen = extremeIndex(deflections), maximum = deflections[chosen], node = deck[interior[chosen]], limit = Double(xb - xa) / Double(settings.deflectionRatio)
            let unit = unitResult(node), virtual = total(members.indices.map { result.forces[$0] * (unit.forces[$0] / 1000) * geometry[$0].length / (properties[$0].young * properties[$0].area) })
            let stiffness = -result.displacement[nodeDofs[node][1]], verified = abs(virtual - stiffness) <= 0.000001 * max(1, abs(stiffness))
            lines.append("deflection \(name) span \(nodes[left].identifier) \(nodes[right].identifier) max \(real(maximum)) at \(nodes[node].identifier) limit \(real(limit)) \(maximum <= limit ? "ok" : "exceeded")")
            lines.append("virtual_work \(name) node \(nodes[node].identifier) stiffness \(real(stiffness)) virtual \(real(virtual)) \(verified ? "ok" : "failed")")
        }
        return lines
    }
    func removalReport() -> [String] {
        let combination = model.combinations.first { $0.name == settings.removalName }!
        var lines: [String] = []
        for (removed, description) in members.enumerated() {
            let system = self.system(choices, removed)
            if let unstable = system.unstable {
                let owner = owners[unstable]
                lines.append("removal \(description.identifier) unstable at \(nodes[owner.node].identifier) \(owner.axis == 0 ? "x" : "y")")
                continue
            }
            let result = analyze(system, combination)[combination.name]!, remaining = members.indices.filter { $0 != removed }
            let values = remaining.map { utilization(result.forces[$0], system.properties[$0], geometry[$0]) }, largest = extremeIndex(values)
            let magnitudes = self.magnitudes(result), node = extremeIndex(magnitudes)
            lines.append("removal \(description.identifier) stable max_utilization \(real(values[largest])) at \(members[remaining[largest]].identifier) max_displacement \(real(magnitudes[node])) at \(nodes[node].identifier)")
        }
        return lines
    }
    func ordinate(_ ordinates: [Double], _ position: Int) -> Double {
        let coordinates = deckX
        if position < coordinates[0] || position > coordinates.last! { return 0 }
        if position == coordinates.last! { return ordinates.last! }
        var index = 0
        while coordinates[index + 1] <= position { index += 1 }
        return ordinates[index] + (ordinates[index + 1] - ordinates[index]) * Double(position - coordinates[index]) / Double(coordinates[index + 1] - coordinates[index])
    }
    func vehicleRange(_ ordinates: [Double], _ positions: [Int]) -> (maximum: Double, highPosition: Int, minimum: Double, lowPosition: Int) {
        let effects = positions.map { position in total(settings.axles.map { $0.load * ordinate(ordinates, position - $0.offset) }) }
        let largest = extremeIndex(effects), smallest = extremeIndex(effects, minimum: true)
        return (effects[largest], positions[largest], effects[smallest], positions[smallest])
    }
    func influenceReport() -> [String] {
        var memberOrdinates = Array(repeating: [Double](), count: members.count)
        var reactionOrdinates = Dictionary(uniqueKeysWithValues: supportDirections.map { ($0.degree, [Double]()) })
        for node in deck {
            let result = unitResult(node)
            for number in members.indices { memberOrdinates[number].append(result.forces[number] / 1000) }
            for support in supportDirections { reactionOrdinates[support.degree]!.append(result.reactions[support.degree] / 1000) }
        }
        var lines: [String] = []
        for number in settings.influence {
            let ordinates = memberOrdinates[number]
            lines.append("influence \(members[number].identifier)")
            for (node, ordinate) in zip(deck, ordinates) { lines.append("node \(nodes[node].identifier) \(real(ordinate))") }
            let largest = extremeIndex(ordinates), smallest = extremeIndex(ordinates, minimum: true)
            let positive = total(ordinates.filter { $0 > 0 }), negative = total(ordinates.filter { $0 < 0 })
            lines.append("max \(real(ordinates[largest])) at \(nodes[deck[largest]].identifier) min \(real(ordinates[smallest])) at \(nodes[deck[smallest]].identifier) positive \(real(positive)) negative \(real(negative))")
            var crossings: [Double] = []
            for index in 0..<(ordinates.count - 1) {
                let first = ordinates[index], last = ordinates[index + 1]
                if (first > 0 && last < 0) || (first < 0 && last > 0) { crossings.append(Double(deckX[index]) + Double(deckX[index + 1] - deckX[index]) * first / (first - last)) }
            }
            lines.append("crossings \(crossings.count)" + (crossings.isEmpty ? "" : " " + crossings.map { real($0, 1) }.joined(separator: " ")))
        }
        let positions = Array(stride(from: deckX[0], through: deckX.last! + settings.axles.last!.offset, by: settings.vehicleStep))
        lines.append("vehicle axles \(settings.axles.count) positions \(positions.count)")
        var memberRanges: [(Double, Double)] = []
        for (number, member) in members.enumerated() {
            let range = vehicleRange(memberOrdinates[number], positions)
            memberRanges.append((range.maximum, range.minimum))
            lines.append("vehicle_member \(member.identifier) max \(real(range.maximum)) at \(range.highPosition) min \(real(range.minimum)) at \(range.lowPosition)")
        }
        for support in supportDirections {
            let range = vehicleRange(reactionOrdinates[support.degree]!, positions)
            lines.append("vehicle_reaction \(nodes[support.node].identifier) \(support.axis == 0 ? "x" : "y") max \(real(range.maximum)) at \(range.highPosition) min \(real(range.minimum)) at \(range.lowPosition)")
        }
        let dead = results[settings.ratingName]!
        var ratings: [(member: Int, kind: String, value: Double)] = []
        for number in members.indices {
            let member = members[number], properties = self.properties[number], shape = geometry[number]
            let largest = memberRanges[number].0, smallest = memberRanges[number].1, deadForce = dead.forces[number] / 1000
            let tensionCapacity = properties.area * properties.yieldStress / 1000, compressionCapacity = min(properties.area * properties.yieldStress, buckling(properties, shape)) / 1000
            var tension = "none", compression = "none"
            if rounded(largest) > 0 {
                let rating = (tensionCapacity - settings.deadFactor * deadForce) / (settings.vehicleFactor * largest)
                tension = real(rating); ratings.append((number, "tension", rating))
            }
            if rounded(smallest) < 0 {
                let rating = (compressionCapacity + settings.deadFactor * deadForce) / (settings.vehicleFactor * (-smallest))
                compression = real(rating); ratings.append((number, "compression", rating))
            }
            lines.append("rating \(member.identifier) tension \(tension) compression \(compression)")
        }
        let minimum = ratings[extremeIndex(ratings.map { $0.value }, minimum: true)]
        lines.append("rating_min \(real(minimum.value)) at \(members[minimum.member].identifier) \(minimum.kind)")
        return lines
    }
    func vibrationReport() -> [String] {
        let name = settings.vibrationName, external = results[name]!.external
        let masses = nodeDofs.map { -external[$0[1]] / 9.81 }, freeMasses = free.map { masses[owners[$0].node] }, size = free.count, system = finalSystem!
        var modes: [[Double]] = [], lines = ["vibration \(name) mass \(real(total(masses))) iterations \(settings.iterations)"]
        for mode in 1...settings.modeCount {
            var vector = Array(repeating: 1.0, count: size)
            for _ in 0..<settings.iterations {
                for previous in modes {
                    let beta = total((0..<size).map { previous[$0] * freeMasses[$0] * vector[$0] })
                    vector = (0..<size).map { vector[$0] - beta * previous[$0] }
                }
                let right = (0..<size).map { freeMasses[$0] * vector[$0] }, solution = solve(system.lower!, right)
                let norm = sqrt(total((0..<size).map { freeMasses[$0] * solution[$0] * solution[$0] }))
                vector = solution.map { $0 / norm }
            }
            modes.append(vector)
            let stiffnessProduct = (0..<size).map { row in total((0..<size).map { system.freeMatrix[row][$0] * vector[$0] }) }
            let numerator = total((0..<size).map { vector[$0] * stiffnessProduct[$0] }), denominator = total((0..<size).map { freeMasses[$0] * vector[$0] * vector[$0] })
            let frequency = sqrt(1000 * (numerator / denominator)) / (2 * pi)
            lines.append("mode \(mode) frequency \(real(frequency)) period \(real(1 / frequency))")
            var peak = 0
            for index in 1..<size where abs(vector[index]) > abs(vector[peak]) { peak = index }
            var normalized = Array(repeating: 0.0, count: degrees)
            for (degree, value) in zip(free, vector) { normalized[degree] = value / vector[peak] }
            for (node, dofs) in zip(nodes, nodeDofs) { lines.append("node \(node.identifier) \(real(normalized[dofs[0]])) \(real(normalized[dofs[1]]))") }
        }
        return lines
    }
    func drawingReport() -> [String] {
        var lines: [String] = []
        for drawing in settings.drawings {
            let result = results[drawing.name]!
            var canvas = Canvas(nodes, drawing.horizontal, drawing.vertical)
            let original = nodes.map { canvas.position(Double($0.x), Double($0.y)) }
            let deformed = nodes.indices.map { node in canvas.position(Double(nodes[node].x) + Double(drawing.magnification) * result.displacement[nodeDofs[node][0]], Double(nodes[node].y) + Double(drawing.magnification) * result.displacement[nodeDofs[node][1]]) }
            for member in members { canvas.line(original[member.start], original[member.end], 46) }
            for position in original { canvas.put(position, 43) }
            for member in members { canvas.line(deformed[member.start], deformed[member.end], 42) }
            for position in deformed { canvas.put(position, 111) }
            lines.append("drawing \(drawing.name) magnification \(drawing.magnification) columns \(canvas.width) rows \(canvas.height)")
            lines += canvas.framed()
        }
        var canvas = Canvas(nodes, settings.mapHorizontal, settings.mapVertical)
        let positions = nodes.map { canvas.position(Double($0.x), Double($0.y)) }
        for (member, value) in zip(members, governing) {
            let character = value >= 1 ? UInt8(35) : UInt8(Int(floor(10 * value)) + 48)
            canvas.line(positions[member.start], positions[member.end], character)
        }
        for position in positions { canvas.put(position, 111) }
        lines.append("utilization_map columns \(canvas.width) rows \(canvas.height)"); lines += canvas.framed()
        return lines
    }
    func csvReports() -> (displacements: [String], forces: [String], reactions: [String]) {
        var displacements = ["case,node,dx,dy"], forces = ["case,member,force,stress,utilization"], reactions = ["case,node,rx,ry"]
        for item in resultOrder {
            let name = item.name, result = results[name]!
            for (node, dofs) in zip(nodes, nodeDofs) { displacements.append("\(name),\(node.identifier),\(real(result.displacement[dofs[0]])),\(real(result.displacement[dofs[1]]))") }
            for number in members.indices {
                let force = result.forces[number], value = utilization(force, properties[number], geometry[number])
                forces.append("\(name),\(members[number].identifier),\(real(force / 1000)),\(real(force / properties[number].area)),\(real(value))")
            }
            for support in model.supports {
                let dofs = nodeDofs[support.node]
                reactions.append("\(name),\(nodes[support.node].identifier),\(real(result.reactions[dofs[0]] / 1000)),\(real(result.reactions[dofs[1]] / 1000))")
            }
        }
        return (displacements, forces, reactions)
    }
    func run() throws {
        let history = designSections(), csv = csvReports()
        let outputs = [("analysis.txt", analysisReport()), ("displacements.csv", csv.displacements), ("member_forces.csv", csv.forces), ("reactions.csv", csv.reactions), ("design.txt", designReport(history)), ("influence.txt", influenceReport()), ("drawing.txt", drawingReport()), ("vibration.txt", vibrationReport())]
        for (name, lines) in outputs { try writeLines(name, lines) }
    }
}
try Truss(readModel()).run()
