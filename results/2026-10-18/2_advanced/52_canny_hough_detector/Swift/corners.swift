import Foundation

struct CornerCandidate { let point: Pixel; let response: Int }
struct CornerDetection { let candidates: Int; let chosen: [CornerCandidate] }

func harrisCorners(_ gx: Image, _ gy: Image, _ window: Int, _ threshold: Int, _ maximum: Int) -> CornerDetection {
    let height = gx.count, width = gx[0].count, half = window / 2
    var response = Array(repeating: Array(repeating: 0, count: width), count: height)
    for y in 0..<height {
        for x in 0..<width {
            var xx = 0, yy = 0, xy = 0
            for dy in (-half)...half {
                for dx in (-half)...half {
                    let a = clamped(gx, x + dx, y + dy), b = clamped(gy, x + dx, y + dy)
                    xx += a * a; yy += b * b; xy += a * b
                }
            }
            response[y][x] = xx * yy - xy * xy - (xx + yy) * (xx + yy) / 25
        }
    }
    var candidates: [CornerCandidate] = []
    for y in 0..<height {
        for x in 0..<width {
            let value = response[y][x], point = Pixel(x: x, y: y)
            if value < threshold { continue }
            let keep = neighborOffsets.allSatisfy { offset in
                let other = point + offset
                if other.x < 0 || other.x >= width || other.y < 0 || other.y >= height { return true }
                return response[other.y][other.x] < value || (response[other.y][other.x] == value && !(other < point))
            }
            if keep { candidates.append(CornerCandidate(point: point, response: value)) }
        }
    }
    candidates.sort { $0.response == $1.response ? $0.point < $1.point : $0.response > $1.response }
    return CornerDetection(candidates: candidates.count, chosen: Array(candidates.prefix(maximum)))
}
