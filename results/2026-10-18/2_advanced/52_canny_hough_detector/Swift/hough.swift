import Foundation

func floorDivide(_ numerator: Int, _ denominator: Int) -> Int { numerator / denominator - (numerator % denominator < 0 ? 1 : 0) }
func rho(_ point: Pixel, _ angle: Int, _ trig: [TrigValue], _ step: Int) -> Int { floorDivide(point.x * trig[angle].cosine + point.y * trig[angle].sine, 16384 * step) }

func circlePoints(_ radius: Int) -> [Pixel] {
    var points = Set<Pixel>(), a = radius, b = 0, error = 1 - radius
    while a >= b {
        points.formUnion([Pixel(x: a, y: b), Pixel(x: b, y: a), Pixel(x: -b, y: a), Pixel(x: -a, y: b), Pixel(x: -a, y: -b), Pixel(x: -b, y: -a), Pixel(x: b, y: -a), Pixel(x: a, y: -b)])
        b += 1
        if error < 0 { error += 2 * b + 1 } else { a -= 1; error += 2 * (b - a) + 1 }
    }
    return points.sorted()
}

struct CircleVotes { let cells: [Int: Image]; let outlines: [Int: [Pixel]] }
struct CircleCandidate { let radius: Int; let center: Pixel; let votes: Int }
struct CirclePeaks { let candidates: Int; let peaks: [CircleCandidate] }

func circleVotes(_ edges: Set<Pixel>, _ width: Int, _ height: Int, _ params: Parameters) -> CircleVotes {
    var cells: [Int: Image] = [:], outlines: [Int: [Pixel]] = [:]
    for radius in params.circleMinRadius...params.circleMaxRadius {
        let offsets = circlePoints(radius)
        outlines[radius] = offsets
        var votes = Array(repeating: Array(repeating: 0, count: width), count: height)
        for point in edges { for offset in offsets { let center = point + offset; if center.x >= 0 && center.x < width && center.y >= 0 && center.y < height { votes[center.y][center.x] += 1 } } }
        cells[radius] = votes
    }
    return CircleVotes(cells: cells, outlines: outlines)
}

func circlePeaks(_ votes: CircleVotes, _ width: Int, _ height: Int, _ minimum: Int) -> CirclePeaks {
    let low = votes.cells.keys.min()!, high = votes.cells.keys.max()!
    var candidates = 0, peaks: [CircleCandidate] = []
    for radius in low...high {
        let size = votes.outlines[radius]!.count
        for y in 0..<height {
            for x in 0..<width {
                let count = votes.cells[radius]![y][x]
                if 100 * count < minimum * size { continue }
                candidates += 1
                var peak = true
                outer: for otherRadius in max(low, radius - 2)...min(high, radius + 2) {
                    let otherSize = votes.outlines[otherRadius]!.count
                    for yy in max(0, y - 2)...min(height - 1, y + 2) {
                        for xx in max(0, x - 2)...min(width - 1, x + 2) {
                            if otherRadius == radius && xx == x && yy == y { continue }
                            let left = count * otherSize, right = votes.cells[otherRadius]![yy][xx] * size
                            if left < right || (left == right && [otherRadius, yy, xx].lexicographicallyPrecedes([radius, y, x])) { peak = false; break outer }
                        }
                    }
                }
                if peak { peaks.append(CircleCandidate(radius: radius, center: Pixel(x: x, y: y), votes: count)) }
            }
        }
    }
    peaks.sort {
        let left = $0.votes * votes.outlines[$1.radius]!.count, right = $1.votes * votes.outlines[$0.radius]!.count
        return left == right ? [$0.radius, $0.center.y, $0.center.x].lexicographicallyPrecedes([$1.radius, $1.center.y, $1.center.x]) : left > right
    }
    return CirclePeaks(candidates: candidates, peaks: peaks)
}

struct LineCell: Hashable, Comparable {
    let angle: Int
    let rho: Int
    static func < (a: LineCell, b: LineCell) -> Bool { a.angle == b.angle ? a.rho < b.rho : a.angle < b.angle }
}
struct LinePeak { let cell: LineCell; let votes: Int }

func lineVotes(_ edges: Set<Pixel>, _ trig: [TrigValue], _ step: Int) -> [LineCell: Int] {
    var votes: [LineCell: Int] = [:]
    for point in edges { for angle in 0..<180 { votes[LineCell(angle: angle, rho: rho(point, angle, trig, step)), default: 0] += 1 } }
    return votes
}

func linePeaks(_ votes: [LineCell: Int], _ threshold: Int) -> [LinePeak] {
    var peaks: [LinePeak] = []
    for (cell, count) in votes where count >= threshold {
        var peak = true
        outer: for angle in max(0, cell.angle - 2)...min(179, cell.angle + 2) {
            for radial in (cell.rho - 2)...(cell.rho + 2) {
                let other = LineCell(angle: angle, rho: radial), otherCount = votes[LineCell(angle: angle, rho: radial)] ?? 0
                if other == cell { continue }
                if otherCount > count || (otherCount == count && other < cell) { peak = false; break outer }
            }
        }
        if peak { peaks.append(LinePeak(cell: cell, votes: count)) }
    }
    return peaks.sorted { $0.votes == $1.votes ? $0.cell < $1.cell : $0.votes > $1.votes }
}
