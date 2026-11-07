import Foundation

enum WaterKind { case high, low }
struct Extremum { let kind: WaterKind; let minute: Double; let rounded: Int; let height: Double; var label = ""
    var day: Int { rounded / 1440 }
}
func predictHeight(_ model: Model, _ time: Double) -> Double { var value = model.meanLevel; for constant in model.constants { let theta = angle(constant.speed, time); value += constant.a * cos(theta) + constant.b * sin(theta) }; return value }
func predictHours(_ model: Model, _ start: Int, _ hours: Int) -> [Double] { (0...hours).map { predictHeight(model, Double(start + $0)) } }
func findExtrema(_ model: Model, _ start: Int, _ hours: Int, _ spacing: Int) -> [Extremum] {
    let count = hours * 60 / spacing, minutes = (0...count).map { 60 * start + $0 * spacing }, heights = minutes.map { predictHeight(model, Double($0) / 60) }
    var extrema: [Extremum] = []
    for j in 1..<count { let left = heights[j - 1], center = heights[j], right = heights[j + 1], kind: WaterKind; if left < center && center > right { kind = .high } else if left > center && center < right { kind = .low } else { continue }; let delta = (left - right) / (2 * (left - 2 * center + right)), minute = Double(minutes[j]) + delta * Double(spacing), height = center - (left - right) * delta / 4; extrema.append(Extremum(kind: kind, minute: minute, rounded: Int(floor(minute + 0.5)), height: height)) }
    return extrema
}
