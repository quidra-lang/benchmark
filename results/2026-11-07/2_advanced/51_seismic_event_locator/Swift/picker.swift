import Foundation

enum PickState: String { case used, dropped, added, rejected, unassociated }

final class Pick {
    unowned let station: Station
    let sample: Int
    let duration: Int
    let ratio: Double
    let amplitude: Int
    let clipped: Bool
    var time: Double { Double(sample) / 100 }
    var state = PickState.unassociated
    var event: Int?
    var residual: Double?
    var firstResidual: Double?
    var assigned = false
    init(_ station: Station, _ sample: Int, _ duration: Int, _ ratio: Double, _ amplitude: Int, _ clipped: Bool) {
        self.station = station; self.sample = sample; self.duration = duration; self.ratio = ratio; self.amplitude = amplitude; self.clipped = clipped
    }
}

func floorDivide(_ numerator: Int, _ denominator: Int) -> Int { numerator / denominator - (numerator % denominator < 0 ? 1 : 0) }

func detectStation(_ station: Station, _ params: Parameters) -> [Pick] {
    let samples = station.samples, length = samples.count
    let mean = floorDivide(samples.reduce(0, +), length), detrended = samples.map { $0 - mean }
    let energy = detrended.map { $0 * $0 }, sw = params.staWindow, lw = params.ltaWindow
    var prefix = [0]
    for value in energy { prefix.append(prefix.last! + value) }
    var picks: [Pick] = [], triggers = 0, shortTriggers = 0, on = false, beginning = 0, peakRatio = 0.0
    func finish(_ end: Int) {
        triggers += 1
        let duration = end - beginning
        if duration < params.minDuration { shortTriggers += 1; return }
        var position = beginning
        while position - 1 >= beginning - sw + 1 && energy[position - 1] >= params.noiseLevel { position -= 1 }
        let last = min(position + params.amplitudeWindow, length)
        let amplitude = (position..<last).map { abs(detrended[$0]) }.max()!
        let clipped = (position..<last).contains { abs(samples[$0]) >= params.clipLevel }
        picks.append(Pick(station, station.start + position, duration, peakRatio, amplitude, clipped))
    }
    for i in (sw + lw - 1)..<length {
        let sta = prefix[i + 1] - prefix[i - sw + 1], lta = prefix[i - sw + 1] - prefix[i - sw - lw + 1]
        if !on {
            if sta * lw * params.triggerOn[1] >= params.triggerOn[0] * lta * sw {
                on = true; beginning = i; peakRatio = Double(sta * lw) / Double(lta * sw)
            }
        } else if sta * lw * params.triggerOff[1] < params.triggerOff[0] * lta * sw { finish(i); on = false }
        else { peakRatio = max(peakRatio, Double(sta * lw) / Double(lta * sw)) }
    }
    if on { finish(length) }
    station.mean = mean
    station.noise = median(detrended.map { Double(abs($0)) })
    station.peak = detrended.map { abs($0) }.max()!
    station.clippedSamples = samples.filter { abs($0) >= params.clipLevel }.count
    station.triggers = triggers; station.shortTriggers = shortTriggers; station.picks = picks
    return picks
}
