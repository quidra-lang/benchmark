import Foundation

enum RemovalReason: String { case absent, na, flat, spike }
struct FlatRun { let first: Int; let last: Int; let value: Double }
struct Spike { let time: Int; let value: Double; let residual: Double; let median: Double; let mad: Double; let limit: Double }
struct Gap { let first: Int; let last: Int; let cause: String }
struct Cleaning {
    let first: Int
    let last: Int
    let numericTimes: [Int]
    var reasons: [Int: RemovalReason]
    let flatRuns: [FlatRun]
    let candidates: [Int]
    let values: [Int: Double]
    let rows: Int
    var prefitRMS = 0.0
    var spikes: [Spike] = []
    var tested = 0
    var usable: [Int] = []
    var gaps: [Gap] = []
    var length: Int { last - first }
}
func median(_ values: [Double]) -> Double { let ordered = values.sorted(), count = values.count; return count % 2 == 1 ? ordered[count / 2] : (ordered[count / 2 - 1] + ordered[count / 2]) / 2 }
func prepareRecord(_ record: ObservationSeries, _ minimumRun: Int) -> Cleaning {
    let numeric = record.values.keys.sorted(), first = numeric.first!, last = numeric.last!
    var reasons: [Int: RemovalReason] = [:], flats: [FlatRun] = [], cursor = 0
    for time in first...last { if record.missing.contains(time) { reasons[time] = .na } else if record.values[time] == nil { reasons[time] = .absent } }
    while cursor < numeric.count { let start = numeric[cursor]; var end = start; while cursor + 1 < numeric.count && numeric[cursor + 1] == end + 1 && record.milli[numeric[cursor + 1]]! == record.milli[start]! { cursor += 1; end = numeric[cursor] }; if end - start + 1 >= minimumRun { flats.append(FlatRun(first: start, last: end, value: record.values[start]!)); for time in (start + 1)...end { reasons[time] = .flat } }; cursor += 1 }
    return Cleaning(first: first, last: last, numericTimes: numeric, reasons: reasons, flatRuns: flats, candidates: numeric.filter { reasons[$0] == nil }, values: record.values, rows: record.rows)
}
func detectSpikes(_ cleaning: inout Cleaning, _ preliminary: [Int: Double], _ settings: Settings) {
    var lower = 0, upper = 0
    for time in cleaning.candidates { while lower < cleaning.candidates.count && cleaning.candidates[lower] < time - settings.spikeWindow { lower += 1 }; while upper < cleaning.candidates.count && cleaning.candidates[upper] <= time + settings.spikeWindow { upper += 1 }; let neighbors = cleaning.candidates[lower..<upper].map { preliminary[$0]! }; if neighbors.count < settings.spikeMinimum { continue }; cleaning.tested += 1; let center = median(neighbors), mad = median(neighbors.map { abs($0 - center) }), limit = max(settings.spikeFactor * 1.4826 * mad, settings.spikeFloor), residual = preliminary[time]!; if abs(residual - center) > limit { cleaning.reasons[time] = .spike; cleaning.spikes.append(Spike(time: time, value: cleaning.values[time]!, residual: residual, median: center, mad: mad, limit: limit)) } }
    cleaning.usable = cleaning.candidates.filter { cleaning.reasons[$0] == nil }; cleaning.gaps = listGaps(cleaning)
}
func listGaps(_ cleaning: Cleaning) -> [Gap] { var gaps: [Gap] = [], start = cleaning.first; while start <= cleaning.last { if cleaning.reasons[start] == nil { start += 1; continue }; var end = start; while end + 1 <= cleaning.last && cleaning.reasons[end + 1] != nil { end += 1 }; let causes = Set((start...end).map { cleaning.reasons[$0]!.rawValue }); gaps.append(Gap(first: start, last: end, cause: causes.count == 1 ? causes.first! : "mixed")); start = end + 1 }; return gaps }
