import Foundation

let regionNames = ["nonocc", "all", "disc"]
struct TruthRegions { let known: [Int]; let visible: [Int]; let occluded: [Int]; let discontinuities: [Int]
    var ordered: [[Int]] { [visible, known, discontinuities] }
}
func truthRegions(_ truth: [Int], _ width: Int, _ height: Int) -> TruthRegions {
    let known = truth.indices.filter { truth[$0] != 0 }
    var occluded: [Int] = []
    for p in known { let y = p / width, x = p % width, g = truth[p], target = x - g; if target < 0 || (0..<width).contains(where: { truth[y * width + $0] > g && $0 - truth[y * width + $0] == target }) { occluded.append(p) } }
    let hidden = Set(occluded), visible = known.filter { !hidden.contains($0) }
    var discontinuities: [Int] = []
    for p in visible { let y = p / width, x = p % width; var boundary = false; for yy in max(0, y - 1)...min(height - 1, y + 1) { for xx in max(0, x - 1)...min(width - 1, x + 1) { let q = yy * width + xx; if q != p && truth[q] != 0 && abs(truth[q] - truth[p]) >= 2 { boundary = true } } }; if boundary { discontinuities.append(p) } }
    return TruthRegions(known: known, visible: visible, occluded: occluded, discontinuities: discontinuities)
}
struct Metrics { let pixels: Int; let valid: Int; let bad1: Int; let bad2: Int; let errorSum: Int; let mae: String; let exact: Int }
func evaluate(_ disparities: [Int], _ truth: [Int], _ region: [Int]) -> Metrics { let errors = region.filter { disparities[$0] != 0 }.map { abs(disparities[$0] - truth[$0]) }, valid = errors.count, missing = region.count - valid, sum = errors.reduce(0, +); return Metrics(pixels: region.count, valid: valid, bad1: missing + errors.filter { $0 > 1 }.count, bad2: missing + errors.filter { $0 > 2 }.count, errorSum: sum, mae: valid == 0 ? "-" : twoDecimals(sum, valid), exact: errors.filter { $0 == 0 }.count) }
func gcd(_ first: Int, _ second: Int) -> Int { var a = first, b = second; while b != 0 { let remainder = a % b; a = b; b = remainder }; return a }
func ratio(_ numerator: Int, _ denominator: Int) -> String { if denominator == 0 { return "0/1 0.00" }; let divisor = gcd(numerator, denominator); return "\(numerator / divisor)/\(denominator / divisor) " + twoDecimals(100 * numerator, denominator) }
