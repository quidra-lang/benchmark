import Foundation

struct TargetSample {
    let number: Int
    let subgroup: Int
    let value: Int
}
struct Capability {
    let metrics: [(String, Double)]
    let samples: [TargetSample]
    let below: Int
    let above: Int
    func value(_ name: String) -> Double { metrics.first { $0.0 == name }!.1 }
    var verdict: String { value("cpk") >= 1.33 ? "capable" : value("cpk") >= 1 ? "marginal" : "incapable" }
}
func capability(_ ids: [Int], _ groups: [Subgroup], _ settings: Settings, _ constants: ControlConstants) -> Capability {
    let selected = ids.map { groups[$0 - 1] }
    let samples = selected.flatMap { group in group.values.enumerated().map { TargetSample(number: (group.number - 1) * settings.size + $0.offset + 1, subgroup: group.number, value: $0.element) } }
    let count = samples.count
    let mean = Double(samples.reduce(0) { $0 + $1.value }) / Double(count)
    let within = Double(selected.reduce(0) { $0 + $1.range }) / Double(selected.count) / constants.d2
    let sbar = realSum(selected.map(\.sd)) / Double(selected.count) / constants.c4
    var squared = 0.0
    for sample in samples { let difference = Double(sample.value) - mean; squared += difference * difference }
    let overall = sqrt(squared / Double(count - 1))
    let cp = Double(settings.usl - settings.lsl) / (6 * within)
    let cpu = (Double(settings.usl) - mean) / (3 * within)
    let cpl = (mean - Double(settings.lsl)) / (3 * within)
    let cpk = min(cpu, cpl)
    let pp = Double(settings.usl - settings.lsl) / (6 * overall)
    let ppu = (Double(settings.usl) - mean) / (3 * overall)
    let ppl = (mean - Double(settings.lsl)) / (3 * overall)
    let ppk = min(ppu, ppl)
    let offset = mean - Double(settings.target)
    let cpm = Double(settings.usl - settings.lsl) / (6 * sqrt(overall * overall + offset * offset))
    let below = samples.filter { $0.value < settings.lsl }.count
    let above = samples.filter { $0.value > settings.usl }.count
    let ppm = Double(1_000_000 * (below + above)) / Double(count)
    return Capability(metrics: [("mean", mean), ("sigma_within", within), ("sigma_sbar", sbar), ("sigma_overall", overall), ("cp", cp), ("cpu", cpu), ("cpl", cpl), ("cpk", cpk), ("pp", pp), ("ppu", ppu), ("ppl", ppl), ("ppk", ppk), ("cpm", cpm), ("ppm", ppm)], samples: samples, below: below, above: above)
}
func confidence(_ index: Double, _ count: Int, _ z: Double) -> (Double, Double) {
    let delta = z * sqrt(1 / Double(9 * count) + index * index / Double(2 * (count - 1)))
    return (index - delta, index + delta)
}
func histogram(_ capability: Capability, _ settings: Settings) -> [String] {
    let values = capability.samples.map(\.value)
    let low = settings.bin * (min(values.min()!, settings.lsl) / settings.bin)
    let high = settings.bin * (max(values.max()!, settings.usl) / settings.bin) + settings.bin
    var counts: [Int: Int] = [:]
    for value in values { counts[settings.bin * (value / settings.bin), default: 0] += 1 }
    let top = counts.values.max()!
    var lines: [String] = []
    for start in stride(from: low, to: high, by: settings.bin) {
        let end = start + settings.bin - 1
        let frequency = counts[start, default: 0]
        let length = (50 * frequency + top - 1) / top
        var parts = ["bin", String(start), String(end), String(frequency)]
        if length > 0 { parts.append(String(repeating: "#", count: length)) }
        if (start...end).contains(settings.lsl) { parts.append("lsl") }
        if (start...end).contains(settings.target) { parts.append("target") }
        if (start...end).contains(settings.usl) { parts.append("usl") }
        lines.append(parts.joined(separator: " "))
    }
    return lines
}
