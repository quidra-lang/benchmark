func gain(_ samples: [Int], _ numerator: Int, _ denominator: Int) -> ClipResult { let counter = ClipCounter(); let output = samples.map { counter.saturate(rdiv($0 * numerator, denominator)) }; return ClipResult(samples: output, clipped: counter.count) }
func mix(_ tracks: [[Int]], _ weights: [Int], _ denominator: Int) -> ClipResult {
    let counter = ClipCounter()
    let output = (0..<tracks.map(\.count).max()!).map { index -> Int in
        var total = 0
        for track in tracks.indices where index < tracks[track].count { total += weights[track] * tracks[track][index] }
        return counter.saturate(rdiv(total, denominator))
    }
    return ClipResult(samples: output, clipped: counter.count)
}
func delay(_ samples: [Int], _ count: Int) -> [Int] { Array(repeating: 0, count: count) + samples }
func echo(_ samples: [Int], _ delay: Int, _ numerator: Int, _ denominator: Int, _ tail: Int) -> ClipResult {
    var output = samples + Array(repeating: 0, count: tail)
    let counter = ClipCounter()
    if delay < output.count { for index in delay..<output.count { output[index] = counter.saturate(output[index] + rdiv(numerator * output[index - delay], denominator)) } }
    return ClipResult(samples: output, clipped: counter.count)
}
func resampledLength(_ length: Int, _ oldRate: Int, _ newRate: Int) -> Int { (length - 1) * newRate / oldRate + 1 }
func resample(_ samples: [Int], _ oldRate: Int, _ newRate: Int) -> [Int] {
    (0..<resampledLength(samples.count, oldRate, newRate)).map { index in
        let position = index * oldRate / newRate
        let fraction = index * oldRate % newRate
        return samples[position] + (fraction == 0 ? 0 : rdiv((samples[position + 1] - samples[position]) * fraction, newRate))
    }
}
func fade(_ samples: [Int], _ fadeIn: Int, _ fadeOut: Int) -> [Int] {
    var output = samples
    for index in 0..<fadeIn { output[index] = rdiv(output[index] * index, fadeIn) }
    for index in (samples.count - fadeOut)..<samples.count { output[index] = rdiv(output[index] * (samples.count - 1 - index), fadeOut) }
    return output
}
