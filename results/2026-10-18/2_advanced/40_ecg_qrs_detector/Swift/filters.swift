struct Signals {
    let lowpass: [Int]
    let bandpass: [Int]
    let derivative: [Int]
    let squared: [Int]
    let integrated: [Int]
}

func filterECG(_ samples: [Int]) -> Signals {
    let count = samples.count
    var accumulator = Array(repeating: 0, count: count)
    var lowpass = accumulator
    var running = accumulator
    var bandpass = accumulator
    var derivative = accumulator
    var squared = accumulator
    var integrated = accumulator
    var window = 0
    func at(_ values: [Int], _ index: Int) -> Int { index >= 0 ? values[index] : 0 }
    for index in samples.indices {
        accumulator[index] = 2 * at(accumulator, index - 1) - at(accumulator, index - 2)
            + samples[index] - 2 * at(samples, index - 6) + at(samples, index - 12)
        lowpass[index] = floorDivide(accumulator[index], 32)
        running[index] = at(running, index - 1) + lowpass[index] - at(lowpass, index - 32)
        bandpass[index] = at(lowpass, index - 16) - floorDivide(running[index], 32)
        derivative[index] = floorDivide(2 * bandpass[index] + at(bandpass, index - 1)
            - at(bandpass, index - 3) - 2 * at(bandpass, index - 4), 8)
        squared[index] = derivative[index] * derivative[index]
        window += squared[index]
        if index >= 30 { window -= squared[index - 30] }
        integrated[index] = window / 30
    }
    return Signals(lowpass: lowpass, bandpass: bandpass, derivative: derivative, squared: squared, integrated: integrated)
}
