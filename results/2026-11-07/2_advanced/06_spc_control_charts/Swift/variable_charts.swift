import Foundation

struct Subgroup {
    let number: Int
    let values: [Int]
    let total: Int
    let squares: Int
    let mean: Double
    let range: Int
    let sd: Double
    init(number: Int, values: [Int]) {
        self.number = number
        self.values = values
        total = values.reduce(0, +)
        squares = values.reduce(0) { $0 + $1 * $1 }
        mean = Double(total) / Double(values.count)
        range = values.max()! - values.min()!
        sd = sqrt(Double(values.count * squares - total * total) / Double(values.count * (values.count - 1)))
    }
}
struct Limits {
    let lcl: Double
    let cl: Double
    let ucl: Double
    func outside(_ value: Double) -> Bool { value < lcl || value > ucl }
}
struct FamilyLimits {
    let first: Limits
    let second: Limits
}
func realSum(_ values: [Double]) -> Double {
    var result = 0.0
    for value in values { result += value }
    return result
}
func familyLimits(_ family: String, _ ids: [Int], _ groups: [Subgroup], _ samples: [Int], _ size: Int, _ constants: ControlConstants) -> FamilyLimits {
    if family == "I_MR" {
        let values = ids.map { samples[$0 - 1] }
        let mean = Double(values.reduce(0, +)) / Double(values.count)
        let ranges = zip(values, values.dropFirst()).map { pair in abs(pair.1 - pair.0) }
        let moving = Double(ranges.reduce(0, +)) / Double(ranges.count)
        let pair = controlConstants(2)
        return FamilyLimits(first: Limits(lcl: mean - 3 * moving / pair.d2, cl: mean, ucl: mean + 3 * moving / pair.d2), second: Limits(lcl: pair.d3 * moving, cl: moving, ucl: pair.d4 * moving))
    }
    let selected = ids.map { groups[$0 - 1] }
    let mean = Double(selected.reduce(0) { $0 + $1.total }) / Double(ids.count * size)
    if family == "XBAR_R" {
        let range = Double(selected.reduce(0) { $0 + $1.range }) / Double(selected.count)
        return FamilyLimits(first: Limits(lcl: mean - constants.a2 * range, cl: mean, ucl: mean + constants.a2 * range), second: Limits(lcl: constants.d3 * range, cl: range, ucl: constants.d4 * range))
    }
    let sd = realSum(selected.map(\.sd)) / Double(selected.count)
    return FamilyLimits(first: Limits(lcl: mean - constants.a3 * sd, cl: mean, ucl: mean + constants.a3 * sd), second: Limits(lcl: constants.b3 * sd, cl: sd, ucl: constants.b4 * sd))
}
