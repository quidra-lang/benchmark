import Foundation

func decimalLog(_ value: Double) -> Double { log(value) / 2.302585092994046 }
func median(_ values: [Double]) -> Double {
    let ordered = values.sorted(), middle = values.count / 2
    return values.count % 2 == 1 ? ordered[middle] : (ordered[middle - 1] + ordered[middle]) / 2
}

struct PickMagnitude {
    let pick: Pick
    let radius: Double
    let durationMagnitude: Double
    let local: Double?
}

func perPickMagnitude(_ pick: Pick, _ radius: Double, _ params: Parameters) -> PickMagnitude {
    let local = params.localMagnitude, duration = params.durationMagnitude
    let md = duration[0] + duration[1] * decimalLog(Double(pick.duration) / 100) + duration[2] * radius
    let ml = pick.clipped ? nil : decimalLog(Double(pick.amplitude)) + local[0] * decimalLog(radius / 100) + local[1] * (radius - 100) + local[2]
    return PickMagnitude(pick: pick, radius: radius, durationMagnitude: md, local: ml)
}

func classNumber(_ magnitude: Double) -> Int { floorDivide(scaledDecimal(magnitude, 2) + 5, 10) }
func magnitudeClass(_ value: Int) -> String { (value < 0 ? "-" : "") + "\(abs(value) / 10).\(abs(value) % 10)" }

struct FrequencyStatistics {
    let classes: [Int: Int]
    let completeness: Int
    let count: Int
    let bValue: Double
    let sigma: Double
    let aValue: Double
}

func frequencyStatistics(_ magnitudes: [Double]) -> FrequencyStatistics {
    let values = magnitudes.map(classNumber), counts = Dictionary(grouping: values, by: { $0 }).mapValues { $0.count }
    let completeness = counts.keys.min { counts[$0]! == counts[$1]! ? $0 < $1 : counts[$0]! > counts[$1]! }!
    let above = values.filter { $0 >= completeness }, mc = Double(completeness) / 10
    let mean = Double(above.reduce(0, +)) / Double(10 * above.count)
    let bValue = 0.4342944819032518 / (mean - (mc - 0.05))
    return FrequencyStatistics(classes: counts, completeness: completeness, count: above.count, bValue: bValue,
                               sigma: bValue / sqrt(Double(above.count)), aValue: decimalLog(Double(above.count)) + bValue * mc)
}
