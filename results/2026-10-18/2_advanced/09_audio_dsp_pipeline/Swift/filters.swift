func fir(_ samples: [Int], _ divisor: Int, _ taps: [Int]) -> ClipResult {
    let counter = ClipCounter()
    let output = samples.indices.map { index -> Int in
        var total = 0
        for tap in 0..<min(taps.count, index + 1) { total += taps[tap] * samples[index - tap] }
        return counter.saturate(floorDivide(total, divisor))
    }
    return ClipResult(samples: output, clipped: counter.count)
}
func biquad(_ samples: [Int], _ sections: [[Int]]) -> ClipResult {
    let counter = ClipCounter()
    var current = samples
    for section in sections {
        var output: [Int] = []
        var u1 = 0, u2 = 0, v1 = 0, v2 = 0
        for input in current {
            let value = counter.saturate(floorDivide(section[0] * input + section[1] * u1 + section[2] * u2 - section[3] * v1 - section[4] * v2, 16384))
            output.append(value)
            u2 = u1; u1 = input; v2 = v1; v1 = value
        }
        current = output
    }
    return ClipResult(samples: current, clipped: counter.count)
}
func movingAverage(_ samples: [Int], _ width: Int) -> [Int] {
    var total = 0
    return samples.enumerated().map { index, value in total += value; if index >= width { total -= samples[index - width] }; return rdiv(total, width) }
}
func dcBlock(_ samples: [Int], _ numerator: Int, _ denominator: Int) -> ClipResult {
    let counter = ClipCounter()
    var previousInput = 0, previousOutput = 0
    let output = samples.map { value -> Int in previousOutput = counter.saturate(value - previousInput + rdiv(numerator * previousOutput, denominator)); previousInput = value; return previousOutput }
    return ClipResult(samples: output, clipped: counter.count)
}
