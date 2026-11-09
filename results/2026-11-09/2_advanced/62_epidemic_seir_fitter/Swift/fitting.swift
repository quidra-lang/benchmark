import Foundation

struct GoldenRecord { let a: Double; let b: Double; let c: Double; let d: Double; let fc: Double; let fd: Double }
struct GoldenResult { let point: Double; let value: Double; let records: [GoldenRecord] }
func golden(_ function: (Double) -> Double, _ lower: Double, _ upper: Double, _ iterations: Int) -> GoldenResult {
    let phi = 0.6180339887498949
    var a = lower, b = upper, c = b - phi * (b - a), d = a + phi * (b - a), fc = function(c), fd = function(d), records = [GoldenRecord(a: a, b: b, c: c, d: d, fc: fc, fd: fd)]
    for _ in 0..<iterations { if fc < fd { b = d; d = c; fd = fc; c = b - phi * (b - a); fc = function(c) } else { a = c; c = d; fc = fd; d = a + phi * (b - a); fd = function(d) }; records.append(GoldenRecord(a: a, b: b, c: c, d: d, fc: fc, fd: fd)) }
    return GoldenResult(point: fc < fd ? c : d, value: fc < fd ? fc : fd, records: records)
}
struct Coordinates { let beta: Double; let gamma: Double }
struct Vertex { let number: Int; let point: Coordinates; let value: Double }
struct NelderRecord { let operation: String; let vertex: Vertex }
struct NelderResult { let initial: [Vertex]; let records: [NelderRecord]; let vertices: [Vertex] }
func vertexBefore(_ first: Vertex, _ second: Vertex) -> Bool { first.value == second.value ? first.number < second.number : first.value < second.value }
func toward(_ origin: Coordinates, _ target: Coordinates, _ factor: Double) -> Coordinates { Coordinates(beta: origin.beta + factor * (target.beta - origin.beta), gamma: origin.gamma + factor * (target.gamma - origin.gamma)) }
func nelderMead(_ function: (Double, Double) -> Double, _ beta: Double, _ gamma: Double, _ simplex: SimplexSettings, _ settings: NelderMeadSettings) -> NelderResult {
    let points = [Coordinates(beta: beta, gamma: gamma), Coordinates(beta: beta + simplex.beta, gamma: gamma), Coordinates(beta: beta, gamma: gamma + simplex.gamma)]
    var vertices = points.enumerated().map { Vertex(number: $0.offset, point: $0.element, value: function($0.element.beta, $0.element.gamma)) }, serial = 3, records: [NelderRecord] = []
    let initial = vertices
    for _ in 0..<settings.iterations {
        vertices.sort(by: vertexBefore)
        let first = vertices[0], second = vertices[1], third = vertices[2], centroid = Coordinates(beta: (first.point.beta + second.point.beta) / 2, gamma: (first.point.gamma + second.point.gamma) / 2), reflected = Coordinates(beta: centroid.beta + settings.alpha * (centroid.beta - third.point.beta), gamma: centroid.gamma + settings.alpha * (centroid.gamma - third.point.gamma)), fr = function(reflected.beta, reflected.gamma)
        var accepted: Coordinates?, value = 0.0, operation = "shrink"
        if fr < first.value { let expanded = toward(centroid, reflected, settings.chi), fe = function(expanded.beta, expanded.gamma); if fe < fr { accepted = expanded; value = fe; operation = "expand" } else { accepted = reflected; value = fr; operation = "reflect" } }
        else if fr < second.value { accepted = reflected; value = fr; operation = "reflect" }
        else if fr < third.value { let contracted = toward(centroid, reflected, settings.psi), fc = function(contracted.beta, contracted.gamma); if fc <= fr { accepted = contracted; value = fc; operation = "contract_out" } }
        else { let contracted = toward(centroid, third.point, settings.psi), fc = function(contracted.beta, contracted.gamma); if fc < third.value { accepted = contracted; value = fc; operation = "contract_in" } }
        if let accepted { vertices = [first, second, Vertex(number: serial, point: accepted, value: value)]; serial += 1 }
        else { vertices = [first]; for vertex in [second, third] { let point = toward(first.point, vertex.point, settings.omega); vertices.append(Vertex(number: serial, point: point, value: function(point.beta, point.gamma))); serial += 1 } }
        vertices.sort(by: vertexBefore); records.append(NelderRecord(operation: operation, vertex: vertices[0]))
    }
    return NelderResult(initial: initial, records: records, vertices: vertices)
}
