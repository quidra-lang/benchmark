import Foundation

func squaredDistance(_ first: [Double], _ second: [Double]) -> Double { let dx = first[0] - second[0], dy = first[1] - second[1]; return dx * dx + dy * dy }
func distance(_ first: [Double], _ second: [Double]) -> Double { sqrt(squaredDistance(first, second)) }
func ospa(_ first: [[Double]], _ second: [[Double]], _ cutoff: Double) -> Double { if first.isEmpty && second.isEmpty { return 0 }; if first.isEmpty || second.isEmpty { return cutoff }; let smaller = first.count <= second.count ? first : second, larger = first.count <= second.count ? second : first, costs = smaller.map { point in larger.map { let clipped = min(cutoff, distance(point, $0)); return clipped * clipped } }, matches = minimumMatching(costs), cost = total(matches.map { costs[$0.row][$0.column] }); return sqrt((cost + cutoff * cutoff * Double(larger.count - smaller.count)) / Double(larger.count)) }
struct Continuity { let covered: Int; let breaks: Int; let swaps: Int; let delay: Int? }
func continuity(_ labels: [Int?]) -> Continuity {
    var covered = 0, groups = 0, swaps = 0, previousLabel: Int?, previousCovered = false, delay: Int?
    for (offset, label) in labels.enumerated() { guard let label else { previousCovered = false; continue }; covered += 1; if delay == nil { delay = offset }; if !previousCovered { groups += 1 }; if let previousLabel, label != previousLabel { swaps += 1 }; previousLabel = label; previousCovered = true }
    return Continuity(covered: covered, breaks: max(0, groups - 1), swaps: swaps, delay: delay)
}
func real(_ value: Double?) -> String { guard let value else { return "-" }; let text = String(format: "%.4f", locale: Locale(identifier: "en_US_POSIX"), value); return text.first == "-" && Double(text) == 0 ? String(text.dropFirst()) : text }
