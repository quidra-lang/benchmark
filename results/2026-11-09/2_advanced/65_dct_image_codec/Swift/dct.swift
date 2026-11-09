import Foundation

typealias Plane = [[Int]]
let zigzagOrder = (0..<8).flatMap { u in (0..<8).map { (u, $0) } }.sorted { first, second in let a = first.0 + first.1, b = second.0 + second.1; if a != b { return a < b }; return a % 2 == 1 ? first.0 < second.0 : first.0 > second.0 }
func floorDivide(_ value: Int, _ divisor: Int) -> Int { value >= 0 ? value / divisor : -((-value + divisor - 1) / divisor) }
func roundedShift(_ value: Int, _ shift: Int) -> Int { floorDivide(value + (1 << (shift - 1)), 1 << shift) }
func forwardDCT(_ block: Plane, _ transform: Plane) -> Plane {
    var intermediate = Array(repeating: Array(repeating: 0, count: 8), count: 8), result = intermediate
    for u in 0..<8 { for x in 0..<8 { var sum = 0; for y in 0..<8 { sum += transform[u][y] * (block[y][x] - 128) }; intermediate[u][x] = roundedShift(sum, 11) } }
    for u in 0..<8 { for v in 0..<8 { var sum = 0; for x in 0..<8 { sum += intermediate[u][x] * transform[v][x] }; result[u][v] = roundedShift(sum, 15) } }
    return result
}
func inverseDCT(_ coefficients: Plane, _ transform: Plane) -> Plane {
    var intermediate = Array(repeating: Array(repeating: 0, count: 8), count: 8), result = intermediate
    for y in 0..<8 { for v in 0..<8 { var sum = 0; for u in 0..<8 { sum += transform[u][y] * coefficients[u][v] }; intermediate[y][v] = roundedShift(sum, 11) } }
    for y in 0..<8 { for x in 0..<8 { var sum = 0; for v in 0..<8 { sum += intermediate[y][v] * transform[v][x] }; result[y][x] = clamp(roundedShift(sum, 15) + 128) } }
    return result
}
func quantizationTables(_ basic: [Plane], _ quality: Int) -> [Int: Plane] { let scale = quality < 50 ? 5000 / quality : 200 - 2 * quality; return Dictionary(uniqueKeysWithValues: basic.enumerated().map { index, plane in (index, plane.map { row in row.map { min(max(($0 * scale + 50) / 100, 1), 255) } }) }) }
func quantize(_ values: Plane, _ table: Plane) -> Plane { values.indices.map { y in values[y].indices.map { x in let value = values[y][x], divisor = table[y][x], magnitude = (abs(value) + divisor / 2) / divisor; return value >= 0 ? magnitude : -magnitude } } }
func zigzag(_ values: Plane) -> [Int] { zigzagOrder.map { values[$0.0][$0.1] } }
func unzigzag(_ sequence: [Int]) -> Plane { var result = Array(repeating: Array(repeating: 0, count: 8), count: 8); for (index, position) in zigzagOrder.enumerated() { result[position.0][position.1] = sequence[index] }; return result }
func dequantize(_ sequence: [Int], _ table: Plane, _ keep: Int = 64) -> Plane { var result = Array(repeating: Array(repeating: 0, count: 8), count: 8); for (index, position) in zigzagOrder.enumerated() where index < keep { result[position.0][position.1] = sequence[index] * table[position.0][position.1] }; return result }
