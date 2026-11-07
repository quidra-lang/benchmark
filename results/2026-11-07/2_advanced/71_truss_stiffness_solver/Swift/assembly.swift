import Foundation

struct Geometry { let length: Double; let cosine: Double; let sine: Double; let dofs: [Int] }
struct Properties { let area: Double; let inertia: Double; let young: Double; let yieldStress: Double; let density: Double; let expansion: Double; let stiffness: Double }
struct Loading { let external: [Double]; let total: [Double]; let temperature: [Double]; let settlement: Bool }
func memberGeometry(_ nodes: [Node], _ members: [Member], _ nodeDofs: [[Int]]) -> [Geometry] {
    members.map { member in
        let start = nodes[member.start], end = nodes[member.end], dx = end.x - start.x, dy = end.y - start.y
        let length = sqrt(Double(dx * dx + dy * dy))
        return Geometry(length: length, cosine: Double(dx) / length, sine: Double(dy) / length, dofs: nodeDofs[member.start] + nodeDofs[member.end])
    }
}
func memberProperties(_ model: Model, _ choices: [Int], _ geometry: [Geometry]) -> [Properties] {
    model.members.indices.map { index in
        let member = model.members[index], section = model.sections[choices[index]], material = model.materials[member.material]
        return Properties(area: section.area, inertia: section.inertia, young: material.young, yieldStress: material.yieldStress, density: material.density, expansion: material.expansion, stiffness: material.young * section.area / geometry[index].length)
    }
}
func memberWeight(_ properties: Properties, _ geometry: Geometry) -> Double { properties.density * 9.81 * properties.area * geometry.length / 1000000000 }
func memberStiffness(_ properties: Properties, _ geometry: Geometry) -> [[Double]] {
    let stiffness = properties.stiffness, c = geometry.cosine, s = geometry.sine
    let xx = stiffness * (c * c), xy = stiffness * (c * s), yy = stiffness * (s * s)
    return [[xx, xy, -xx, -xy], [xy, yy, -xy, -yy], [-xx, -xy, xx, xy], [-xy, -yy, xy, yy]]
}
func assemble(_ geometry: [Geometry], _ properties: [Properties], _ degrees: Int, _ removed: Int? = nil) -> [[Double]] {
    var matrix = Array(repeating: Array(repeating: 0.0, count: degrees), count: degrees)
    for number in geometry.indices where number != removed {
        let shape = geometry[number], local = memberStiffness(properties[number], shape)
        for row in 0..<4 { for column in 0..<4 { matrix[shape.dofs[row]][shape.dofs[column]] += local[row][column] } }
    }
    return matrix
}
func loadVectors(_ loadCase: LoadCase, _ geometry: [Geometry], _ properties: [Properties], _ nodeDofs: [[Int]], _ degrees: Int, _ removed: Int? = nil) -> Loading {
    var external = Array(repeating: 0.0, count: degrees), thermal = external, temperature = Array(repeating: 0.0, count: geometry.count), settlement = false
    for load in loadCase.lines {
        switch load {
        case let .force(node, horizontal, vertical): external[nodeDofs[node][0]] += horizontal * 1000; external[nodeDofs[node][1]] += vertical * 1000
        case let .temperature(number, change):
            if number == removed { continue }
            let member = properties[number], shape = geometry[number], force = member.young * member.area * member.expansion * change
            let direction = [-shape.cosine, -shape.sine, shape.cosine, shape.sine]
            temperature[number] = force
            for index in 0..<4 { thermal[shape.dofs[index]] += force * direction[index] }
        case .selfWeight:
            for number in geometry.indices where number != removed {
                let weight = memberWeight(properties[number], geometry[number])
                external[geometry[number].dofs[1]] -= weight / 2; external[geometry[number].dofs[3]] -= weight / 2
            }
        case .settlement: settlement = true
        }
    }
    return Loading(external: external, total: zip(external, thermal).map { $0.0 + $0.1 }, temperature: temperature, settlement: settlement)
}
