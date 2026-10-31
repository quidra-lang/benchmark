func envelope(_ samples: [Int], _ attack: Int, _ release: Int) -> [Int] {
    var level = 0
    return samples.map { value in let magnitude = min(abs(value), 32767); let coefficient = magnitude > level ? attack : release; level += rdiv((magnitude - level) * coefficient, 32768); return level }
}
func normalize(_ samples: [Int], _ target: Int) -> ([Int], Int) { let sourcePeak = peak(samples); return (sourcePeak == 0 ? samples : samples.map { rdiv($0 * target, sourcePeak) }, sourcePeak) }
func gate(_ samples: [Int], _ threshold: Int, _ hold: Int) -> ([Int], Int) {
    var lastLoud = -1
    var muted = 0
    let output = samples.enumerated().map { index, value -> Int in
        if abs(value) >= threshold { lastLoud = index }
        if lastLoud >= 0 && index - lastLoud <= hold { return value }
        muted += 1
        return 0
    }
    return (output, muted)
}
struct Compression { let samples: [Int]; let minGain: Int; let reduced: Int }
func compress(_ samples: [Int], _ threshold: Int, _ ratioNum: Int, _ ratioDen: Int, _ attack: Int, _ release: Int) -> Compression {
    let levels = envelope(samples, attack, release)
    var gain = 32768, minGain = 32768, reduced = 0
    let output = samples.enumerated().map { index, value in
        let level = levels[index]
        let target = level > threshold ? rdiv((threshold + rdiv((level - threshold) * ratioDen, ratioNum)) * 32768, level) : 32768
        gain = target < gain ? target : gain + rdiv((target - gain) * release, 32768)
        minGain = min(minGain, gain)
        if gain < 32768 { reduced += 1 }
        return rdiv(value * gain, 32768)
    }
    return Compression(samples: output, minGain: minGain, reduced: reduced)
}
