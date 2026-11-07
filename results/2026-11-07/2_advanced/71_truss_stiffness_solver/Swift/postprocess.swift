import Foundation

struct Result { let name: String; let displacement: [Double]; let forces: [Double]; let reactions: [Double]; let external: [Double] }
func axialForces(_ geometry: [Geometry], _ properties: [Properties], _ displacement: [Double], _ temperature: [Double], _ removed: Int? = nil) -> [Double] {
    var forces = Array(repeating: 0.0, count: geometry.count)
    for number in geometry.indices where number != removed {
        let shape = geometry[number], a = shape.dofs
        let extensionValue = (displacement[a[2]] - displacement[a[0]]) * shape.cosine + (displacement[a[3]] - displacement[a[1]]) * shape.sine
        forces[number] = properties[number].stiffness * extensionValue - temperature[number]
    }
    return forces
}
func reactions(_ matrix: [[Double]], _ displacement: [Double], _ force: [Double], _ restrained: [Int]) -> [Double] {
    var result = Array(repeating: 0.0, count: force.count)
    for row in restrained {
        var value = 0.0
        for column in force.indices { value += matrix[row][column] * displacement[column] }
        result[row] = value - force[row]
    }
    return result
}
func superpose(_ combination: Combination, _ results: [String: Result]) -> Result {
    let first = combination.terms[0], initial = results[first.name]!
    var displacement = initial.displacement.map { first.factor * $0 }, forces = initial.forces.map { first.factor * $0 }, reactions = initial.reactions.map { first.factor * $0 }, external = initial.external.map { first.factor * $0 }
    for term in combination.terms.dropFirst() {
        let result = results[term.name]!
        for index in displacement.indices { displacement[index] += term.factor * result.displacement[index]; reactions[index] += term.factor * result.reactions[index]; external[index] += term.factor * result.external[index] }
        for index in forces.indices { forces[index] += term.factor * result.forces[index] }
    }
    return Result(name: combination.name, displacement: displacement, forces: forces, reactions: reactions, external: external)
}
func equilibriumResidual(_ result: Result, _ geometry: [Geometry]) -> Double {
    var residual = zip(result.external, result.reactions).map { $0.0 + $0.1 }
    for number in geometry.indices {
        let shape = geometry[number], direction = [shape.cosine, shape.sine, -shape.cosine, -shape.sine]
        for index in 0..<4 { residual[shape.dofs[index]] += result.forces[number] * direction[index] }
    }
    return residual.map(abs).max()!
}
