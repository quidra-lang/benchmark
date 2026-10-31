enum PeakCategory: String, CaseIterable {
    case qrs, searchback, twave, refractory, noise
}

final class Peak {
    let time: Int
    let r: Int
    let integrated: Int
    let filtered: Int
    let slope: Int
    var thresholdI = 0
    var thresholdF = 0
    var category: PeakCategory?

    init(time: Int, r: Int, integrated: Int, filtered: Int, slope: Int) {
        self.time = time
        self.r = r
        self.integrated = integrated
        self.filtered = filtered
        self.slope = slope
    }
}

func findPeaks(_ signals: Signals) -> [Peak] {
    let count = signals.integrated.count
    var peaks: [Peak] = []
    for time in 0..<count {
        let value = signals.integrated[time]
        if value <= 0 { continue }
        if (max(0, time - 20)..<time).contains(where: { signals.integrated[$0] >= value }) { continue }
        if ((time + 1)..<min(count, time + 21)).contains(where: { signals.integrated[$0] > value }) { continue }
        var r = max(0, time - 30)
        for index in r...time where abs(signals.bandpass[index]) > abs(signals.bandpass[r]) { r = index }
        let slope = (max(0, time - 29)...time).map { abs(signals.derivative[$0]) }.max()!
        peaks.append(Peak(time: time, r: r, integrated: value, filtered: abs(signals.bandpass[r]), slope: slope))
    }
    return peaks
}

func initialLevels(_ signals: Signals) -> Levels {
    let integrated = signals.integrated.prefix(400)
    let filtered = signals.bandpass.prefix(400).map(abs)
    return Levels(spki: integrated.max()! / 3, npki: integrated.reduce(0, +) / 800,
                   spkf: filtered.max()! / 3, npkf: filtered.reduce(0, +) / 800)
}

func widthMilliseconds(_ filtered: [Int], _ r: Int) -> Int {
    let peak = abs(filtered[r])
    let positions = (max(0, r - 25)..<min(filtered.count, r + 26)).filter { 4 * abs(filtered[$0]) >= peak }
    return 5 * (positions.last! - positions.first! + 1)
}
