struct Histogram {
    let maxval: Int
    let pixels: Int64
    let counts: [Int64]
    let belowCounts: [Int64]
    let belowSums: [Int64]
    let total: Int64
    let minimum: Int
    let maximum: Int
    let levels: Int
    let median: Int
    let mode: Int
    let binWidth: Int
    let bins: [Int64]

    init(_ image: Image) {
        maxval = image.maxval
        let pixels = Int64(image.width * image.height)
        self.pixels = pixels
        var counts = Array<Int64>(repeating: 0, count: image.maxval + 1)
        for row in image.pixels { for value in row { counts[Int(value)] += 1 } }
        self.counts = counts
        var belowCounts: [Int64] = []
        var belowSums: [Int64] = []
        var count: Int64 = 0
        var sum: Int64 = 0
        for (value, frequency) in counts.enumerated() {
            count += frequency
            sum += Int64(value) * frequency
            belowCounts.append(count)
            belowSums.append(sum)
        }
        self.belowCounts = belowCounts
        self.belowSums = belowSums
        total = sum
        let present = counts.indices.filter { counts[$0] > 0 }
        minimum = present[0]
        maximum = present.last!
        levels = present.count
        median = belowCounts.firstIndex { 2 * $0 >= pixels }!
        mode = counts.firstIndex(of: counts.max()!)!
        let binWidth = (image.maxval + 8) / 8
        self.binWidth = binWidth
        bins = stride(from: 0, through: image.maxval, by: binWidth).map { start in
            counts[start..<min(start + binWidth, counts.count)].reduce(0, +)
        }
    }

    func split(_ cutoff: Int) -> (below: Int64, sumBelow: Int64, above: Int64, sumAbove: Int64) {
        let below = belowCounts[cutoff]
        let sum = belowSums[cutoff]
        return (below, sum, pixels - below, total - sum)
    }
}

struct Candidate {
    let cutoff: Int
    let below: Int64
    let sumBelow: Int64
    let above: Int64
    let sumAbove: Int64
    let numerator: Int64
    let denominator: Int64

    init(_ cutoff: Int, _ below: Int64, _ sumBelow: Int64, _ above: Int64, _ sumAbove: Int64) {
        self.cutoff = cutoff
        self.below = below
        self.sumBelow = sumBelow
        self.above = above
        self.sumAbove = sumAbove
        numerator = sumBelow * sumBelow * above + sumAbove * sumAbove * below
        denominator = below * above
    }
}

private func compareScores(_ first: Candidate, _ second: Candidate) -> Int {
    let q1 = first.numerator / first.denominator
    let q2 = second.numerator / second.denominator
    if q1 != q2 { return q1 > q2 ? 1 : -1 }
    let left = (first.numerator % first.denominator) * second.denominator
    let right = (second.numerator % second.denominator) * first.denominator
    return left == right ? 0 : (left > right ? 1 : -1)
}

struct OtsuResult {
    let cutoff: Int
    let upper: Int
    let candidates: [Candidate]
}

func otsu(_ histogram: Histogram) -> OtsuResult {
    var candidates: [Candidate] = []
    for cutoff in 0..<histogram.maxval {
        let values = histogram.split(cutoff)
        if histogram.counts[cutoff] > 0 && values.above > 0 {
            candidates.append(Candidate(cutoff, values.below, values.sumBelow, values.above, values.sumAbove))
        }
    }
    candidates.sort { first, second in
        let order = compareScores(first, second)
        return order == 0 ? first.cutoff < second.cutoff : order > 0
    }
    guard let best = candidates.first else { return OtsuResult(cutoff: histogram.minimum, upper: histogram.minimum, candidates: []) }
    let following = ((best.cutoff + 1)...histogram.maxval).first { histogram.counts[$0] > 0 }!
    return OtsuResult(cutoff: best.cutoff, upper: following - 1, candidates: candidates)
}

func isodata(_ histogram: Histogram) -> (cutoff: Int, iterations: Int) {
    var cutoff = Int(histogram.total / histogram.pixels)
    var iterations = 0
    while true {
        let values = histogram.split(cutoff)
        if values.below == 0 || values.above == 0 { break }
        let following = Int((values.sumBelow * values.above + values.sumAbove * values.below) / (2 * values.below * values.above))
        iterations += 1
        if following == cutoff { break }
        cutoff = following
        if iterations == 100 { break }
    }
    return (cutoff, iterations)
}
