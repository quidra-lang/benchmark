import Foundation

let chartOrder = ["XBAR_R", "R", "XBAR_S", "S", "I", "MR", "CUSUM", "EWMA", "MA"]
let familyNames = ["XBAR_R", "XBAR_S", "I_MR"]
let familyCharts = ["XBAR_R": ["XBAR_R", "R"], "XBAR_S": ["XBAR_S", "S"], "I_MR": ["I", "MR"]]
let ruleOrder = (1...8).map(String.init) + ["UPPER", "LOWER"]
func real(_ value: Double) -> String {
    let text = String(format: "%.4f", locale: Locale(identifier: "en_US_POSIX"), value)
    return text == "-0.0000" ? "0.0000" : text
}
func numbers(_ values: [Int]) -> String { values.isEmpty ? "none" : values.sorted().map(String.init).joined(separator: " ") }
func status(_ converged: Bool) -> String { converged ? "converged" : "stopped" }
func limitsText(_ label: String, _ limits: Limits) -> String { "\(label) lcl \(real(limits.lcl)) cl \(real(limits.cl)) ucl \(real(limits.ucl))" }
func pairText(_ family: String, _ pair: FamilyLimits) -> String {
    limitsText(family == "I_MR" ? "I" : "XBAR", pair.first) + " " + limitsText(familyCharts[family]![1], pair.second)
}
struct EstimationPass {
    let points: Int
    let limits: FamilyLimits
    let out: [Int]
}
struct Estimate {
    let passes: [EstimationPass]
    let converged: Bool
    let retained: [Int]
    let removed: [Int]
    var limits: FamilyLimits { passes.last!.limits }
}
struct PatternCheck {
    let chart: String
    let points: Int
    let signals: [Signal]
}
struct Proposal {
    let family: String
    let points: Int
    let limits: FamilyLimits
}
struct CusumPoint {
    let number: Int
    let upper: Double
    let lower: Double
}
struct BandPoint {
    let number: Int
    let value: Double
    let width: Double
}
final class Event {
    let number: Int
    let start: Int
    var end: Int
    var signals: [Signal] = []
    var counts = Array(repeating: 0, count: 5)
    var onset: Int
    var shift = 0.0
    var spread = 0.0
    var outside = 0
    var detection: [Int?] = []
    var length: Int { end - start + 1 }
    var kind: String { ["SHIFT_UP", "SHIFT_DOWN", "SPREAD_UP", "SPREAD_DOWN", "PATTERN"][counts.firstIndex(of: counts.max()!)!] }
    init(_ number: Int, _ start: Int) { self.number = number; self.start = start; end = start; onset = start }
    func contains(_ group: Int) -> Bool { start <= group && group <= end }
}
struct AttributePass {
    let lots: Int
    let center: Double
    let out: [Int]
}
struct AttributeResult {
    let chart: String
    let passes: [AttributePass]
    let converged: Bool
    let retained: Int
    let removed: [Int]
    let points: [LotPoint]
    let signals: [Signal]
}
struct CapabilityGroup {
    let name: String
    let groups: Int
    let result: Capability
}
struct RollingResult {
    let first: Int
    let last: Int
    let result: Capability
}

final class Analysis {
    let settings: Settings
    let samples: [Int]
    let lots: [Lot]
    let groups: [Subgroup]
    let constants: ControlConstants
    var estimates: [String: Estimate] = [:]
    var checks: [PatternCheck] = []
    var signals: [Signal] = []
    var cusum: [CusumPoint] = []
    var ewma: [BandPoint] = []
    var movingAverage: [BandPoint] = []
    var events: [Event] = []
    var proposals: [Proposal] = []
    var attributes: [AttributeResult] = []
    var capabilities: [CapabilityGroup] = []
    var rolling: [RollingResult] = []
    var mu = 0.0
    var sigma = 0.0
    var reference = 0.0
    var interval = 0.0
    var ewmaWidth = 0.0
    var maWidth = 0.0
    var phase2: ArraySlice<Subgroup> { groups.dropFirst(settings.phase1) }

    init(_ settings: Settings, _ samples: [Int], _ lots: [Lot]) {
        self.settings = settings
        self.samples = samples
        self.lots = lots
        constants = controlConstants(settings.size)
        groups = stride(from: 0, to: samples.count, by: settings.size).map { start in Subgroup(number: start / settings.size + 1, values: Array(samples[start..<(start + settings.size)])) }
    }
    func limits(_ family: String, _ ids: [Int]) -> FamilyLimits { familyLimits(family, ids, groups, samples, settings.size, constants) }
    func chartLimits(_ chart: String) -> Limits {
        let family = familyNames.first { familyCharts[$0]!.contains(chart) }!
        let pair = estimates[family]!.limits
        return chart == familyCharts[family]![0] ? pair.first : pair.second
    }
    func series(_ family: String, _ ids: [Int]) -> ([Point], [Point]) {
        if family == "I_MR" {
            return (ids.map { Point(number: $0, value: Double(samples[$0 - 1])) }, zip(ids, ids.dropFirst()).map { pair in Point(number: pair.1, value: Double(abs(samples[pair.1 - 1] - samples[pair.0 - 1]))) })
        }
        let chosen = ids.map { groups[$0 - 1] }
        return (chosen.map { Point(number: $0.number, value: $0.mean) }, chosen.map { Point(number: $0.number, value: family == "XBAR_R" ? Double($0.range) : $0.sd) })
    }
    func estimate(_ family: String) {
        let initial = Array(1...(family == "I_MR" ? settings.phase1 * settings.size : settings.phase1))
        var ids = initial
        var passes: [EstimationPass] = []
        var converged = false
        for pass in 1...settings.passes {
            let limits = self.limits(family, ids)
            let pair = series(family, ids)
            let out = Array(Set((pair.0.filter { limits.first.outside($0.value) } + pair.1.filter { limits.second.outside($0.value) }).map(\.number))).sorted()
            passes.append(EstimationPass(points: ids.count, limits: limits, out: out))
            if out.isEmpty { converged = true; break }
            if pass == settings.passes { break }
            ids.removeAll { out.contains($0) }
        }
        estimates[family] = Estimate(passes: passes, converged: converged, retained: ids, removed: initial.filter { !ids.contains($0) })
    }
    func phase2Series(_ chart: String) -> [Point] {
        if chart == "I" || chart == "MR" {
            return ((settings.phase1 * settings.size + 1)...samples.count).map { number in Point(number: number, value: chart == "I" ? Double(samples[number - 1]) : Double(abs(samples[number - 1] - samples[number - 2]))) }
        }
        return phase2.map { group in
            let value = chart == "R" ? Double(group.range) : chart == "S" ? group.sd : group.mean
            return Point(number: group.number, value: value)
        }
    }
    func hasSignal(_ chart: String, _ end: Int, _ rule: String? = nil) -> Bool { signals.contains { $0.chart == chart && $0.end == end && (rule == nil || $0.rule == rule!) } }
    func eventOf(_ group: Int) -> Event? { events.first { $0.contains(group) } }
    func addBandSignal(_ chart: String, _ point: BandPoint, _ start: Int) {
        if point.value > mu + point.width { signals.append(Signal(chart: chart, rule: "UPPER", start: start, end: point.number, value: point.value, direction: "UP")) }
        else if point.value < mu - point.width { signals.append(Signal(chart: chart, rule: "LOWER", start: start, end: point.number, value: point.value, direction: "DOWN")) }
    }
    func monitor() {
        for chart in chartOrder.prefix(6) { signals += runRules(chart, phase2Series(chart), chartLimits(chart), settings.rules[chart]!) }
        var upper = 0.0
        var lower = 0.0
        var upperRun = 0
        var lowerRun = 0
        var smoothed = mu
        var factor = 1.0
        let decay = (1 - settings.lambda) * (1 - settings.lambda)
        let ratio = settings.lambda / (2 - settings.lambda)
        ewmaWidth = settings.ewmaL * sigma * sqrt(ratio)
        maWidth = 3 * sigma / sqrt(Double(settings.maSpan))
        for group in phase2 {
            let number = group.number
            upper = max(0, upper + (group.mean - mu - reference))
            lower = max(0, lower + (mu - group.mean - reference))
            upperRun = upper > 0 ? upperRun + 1 : 0
            lowerRun = lower > 0 ? lowerRun + 1 : 0
            cusum.append(CusumPoint(number: number, upper: upper, lower: lower))
            if upper > interval { signals.append(Signal(chart: "CUSUM", rule: "UPPER", start: number - upperRun + 1, end: number, value: upper, direction: "UP")); upper = 0; upperRun = 0 }
            if lower > interval { signals.append(Signal(chart: "CUSUM", rule: "LOWER", start: number - lowerRun + 1, end: number, value: lower, direction: "DOWN")); lower = 0; lowerRun = 0 }
            smoothed = settings.lambda * group.mean + (1 - settings.lambda) * smoothed
            factor *= decay
            let weighted = BandPoint(number: number, value: smoothed, width: settings.ewmaL * sigma * sqrt(ratio * (1 - factor)))
            ewma.append(weighted)
            addBandSignal("EWMA", weighted, number)
            let first = max(settings.phase1 + 1, number - settings.maSpan + 1)
            let count = number - first + 1
            let total = groups[(first - 1)..<number].reduce(0) { $0 + $1.total }
            let average = BandPoint(number: number, value: Double(total) / Double(settings.size * count), width: 3 * sigma / sqrt(Double(count)))
            movingAverage.append(average)
            addBandSignal("MA", average, first)
        }
        signals.sort { a, b in
            if a.chart != b.chart { return chartOrder.firstIndex(of: a.chart)! < chartOrder.firstIndex(of: b.chart)! }
            if a.end != b.end { return a.end < b.end }
            return ruleOrder.firstIndex(of: a.rule)! < ruleOrder.firstIndex(of: b.rule)!
        }
    }
    func buildEvents() {
        for group in Set(signals.map { $0.subgroup(settings.size) }).sorted() {
            if let last = events.last, group - last.end - 1 <= settings.eventGap { last.end = group }
            else { events.append(Event(events.count + 1, group)) }
        }
        let locations = Set(["XBAR_R", "XBAR_S", "I", "CUSUM", "EWMA", "MA"])
        for event in events {
            event.signals = signals.filter { event.contains($0.subgroup(settings.size)) }
            for signal in event.signals {
                let index = signal.direction == "NONE" ? 4 : locations.contains(signal.chart) ? (signal.direction == "UP" ? 0 : 1) : (signal.direction == "UP" ? 2 : 3)
                event.counts[index] += 1
            }
            event.onset = event.signals.filter { $0.chart == "CUSUM" }.map(\.start).min() ?? event.start
            let covered = groups[(event.start - 1)..<event.end]
            let mean = Double(covered.reduce(0) { $0 + $1.total }) / Double(settings.size * event.length)
            event.shift = (mean - mu) / sigma
            event.spread = realSum(covered.map(\.sd)) / Double(event.length) / estimates["XBAR_S"]!.limits.second.cl
            event.outside = covered.reduce(0) { count, group in count + group.values.filter { $0 < settings.lsl || $0 > settings.usl }.count }
            event.detection = chartOrder.map { chart in event.signals.filter { $0.chart == chart }.map { $0.subgroup(settings.size) }.min() }
        }
    }
    func estimateAttribute(_ chart: String) {
        var chosen = lots
        var passes: [AttributePass] = []
        var converged = false
        var center = attributeCenter(chart, chosen)
        for pass in 1...settings.passes {
            center = attributeCenter(chart, chosen)
            let out = chosen.filter { attributePoint($0, center).status != "ok" }.map(\.number)
            passes.append(AttributePass(lots: chosen.count, center: center.value, out: out))
            if out.isEmpty { converged = true; break }
            if pass == settings.passes { break }
            chosen.removeAll { out.contains($0.number) }
        }
        let points = lots.map { attributePoint($0, center) }
        let retained = Set(chosen.map(\.number))
        let signals = runRules(chart, points.map { Point(number: $0.lot.number, value: $0.z) }, Limits(lcl: -3, cl: 0, ucl: 3), settings.rules["STD"]!)
        attributes.append(AttributeResult(chart: chart, passes: passes, converged: converged, retained: chosen.count, removed: lots.filter { !retained.contains($0.number) }.map(\.number), points: points, signals: signals))
    }
    func run() {
        for family in familyNames { estimate(family) }
        for family in familyNames {
            let estimate = estimates[family]!
            let pair = series(family, estimate.retained)
            let charts = familyCharts[family]!
            checks.append(PatternCheck(chart: charts[0], points: pair.0.count, signals: runRules(charts[0], pair.0, estimate.limits.first, settings.rules[charts[0]]!)))
            checks.append(PatternCheck(chart: charts[1], points: pair.1.count, signals: runRules(charts[1], pair.1, estimate.limits.second, settings.rules[charts[1]]!)))
        }
        mu = estimates["XBAR_R"]!.limits.first.cl
        sigma = estimates["XBAR_R"]!.limits.second.cl / constants.d2 / sqrt(Double(settings.size))
        reference = settings.cusumK * sigma
        interval = settings.cusumH * sigma
        monitor()
        buildEvents()
        let free = phase2.filter { eventOf($0.number) == nil }.map(\.number)
        for family in familyNames {
            let added = family == "I_MR" ? free.flatMap { Array((($0 - 1) * settings.size + 1)...($0 * settings.size)) } : free
            let ids = estimates[family]!.retained + added
            proposals.append(Proposal(family: family, points: ids.count, limits: limits(family, ids)))
        }
        for chart in ["p", "np", "c", "u"] { estimateAttribute(chart) }
        for (name, ids) in [("phase1", estimates["XBAR_R"]!.retained), ("phase2", phase2.map(\.number))] {
            capabilities.append(CapabilityGroup(name: name, groups: ids.count, result: capability(ids, groups, settings, constants)))
        }
        var first = settings.phase1 + 1
        while first + settings.rollingWindow - 1 <= groups.count {
            let last = first + settings.rollingWindow - 1
            rolling.append(RollingResult(first: first, last: last, result: capability(Array(first...last), groups, settings, constants)))
            first += settings.rollingStep
        }
    }
    func limitsLines() -> [String] {
        var lines = ["characteristic \(settings.characteristic)", "subgroup_size \(settings.size)", "subgroups \(groups.count)", "samples \(samples.count)", "phase1_subgroups \(settings.phase1)"]
        for family in familyNames {
            let estimate = estimates[family]!
            lines.append("family \(family)")
            for (index, pass) in estimate.passes.enumerated() { lines.append("pass \(index + 1) points \(pass.points) \(pairText(family, pass.limits)) out \(numbers(pass.out))") }
            lines.append("result \(status(estimate.converged)) passes \(estimate.passes.count) retained \(estimate.retained.count) removed \(numbers(estimate.removed))")
        }
        for check in checks {
            for signal in check.signals { lines.append("phase1_signal \(check.chart) \(signal.rule) \(signal.start) \(signal.end) \(real(signal.value))") }
            lines.append("phase1_check \(check.chart) points \(check.points) signals \(check.signals.count)")
        }
        for proposal in proposals { lines.append("proposed \(proposal.family) points \(proposal.points) \(pairText(proposal.family, proposal.limits))") }
        let target = "target \(real(mu)) sigma \(real(sigma))"
        lines.append("cusum \(target) k \(real(reference)) h \(real(interval))")
        lines.append("ewma \(target) lcl \(real(mu - ewmaWidth)) ucl \(real(mu + ewmaWidth))")
        lines.append("ma \(target) span \(settings.maSpan) lcl \(real(mu - maWidth)) ucl \(real(mu + maWidth))")
        for chart in chartOrder {
            let selected = signals.filter { $0.chart == chart }
            let points = chart == "I" || chart == "MR" ? samples.count - settings.phase1 * settings.size : phase2.count
            let rules = chartOrder.prefix(6).contains(chart) ? settings.rules[chart]!.map(String.init) : ["UPPER", "LOWER"]
            let ends = Set(selected.map(\.end))
            let first = ends.min().map(String.init) ?? "none"
            let counts = rules.map { rule in "\(rule):\(selected.filter { $0.rule == rule }.count)" }.joined(separator: " ")
            lines.append("phase2 \(chart) points \(points) signals \(selected.count) signalled \(ends.count) first \(first) by_rule \(counts)")
        }
        return lines
    }
    func signalLines() -> [String] {
        ["chart,rule,start,end,value,direction"] + signals.map { "\($0.chart),\($0.rule),\($0.start),\($0.end),\(real($0.value)),\($0.direction)" }
    }
    func eventLines() -> [String] {
        var lines = ["events \(events.count)"]
        for event in events {
            let charts = chartOrder.enumerated().filter { event.detection[$0.offset] != nil }.map(\.element).joined(separator: ",")
            let counts = event.counts
            lines.append("event \(event.number) start \(event.start) end \(event.end) length \(event.length) signals \(event.signals.count) charts \(charts) location_up \(counts[0]) location_down \(counts[1]) spread_up \(counts[2]) spread_down \(counts[3]) pattern \(counts[4]) onset \(event.onset) shift \(real(event.shift)) spread \(real(event.spread)) out_of_spec \(event.outside) type \(event.kind)")
            let detection = chartOrder.enumerated().map { index, chart in "\(chart):\(event.detection[index].map(String.init) ?? "-")" }.joined(separator: " ")
            lines.append("detection \(event.number) \(detection)")
        }
        return lines
    }
    func subgroupLines() -> [String] {
        var lines = ["subgroup,phase,mean,zone,range,sd,cusum_upper,cusum_lower,ewma,ma,signals,event"]
        let estimate = estimates["XBAR_R"]!
        for group in groups {
            let index = group.number - settings.phase1 - 1
            let phase = index >= 0 ? "phase2" : estimate.removed.contains(group.number) ? "excluded" : "phase1"
            let monitored = index >= 0 ? [real(cusum[index].upper), real(cusum[index].lower), real(ewma[index].value), real(movingAverage[index].value)] : Array(repeating: "-", count: 4)
            let count = signals.filter { $0.subgroup(settings.size) == group.number }.count
            let fields = [String(group.number), phase, real(group.mean), zoneName(group.mean, estimate.limits.first), String(group.range), real(group.sd)] + monitored + [String(count), eventOf(group.number).map { String($0.number) } ?? "-"]
            lines.append(fields.joined(separator: ","))
        }
        return lines
    }
    func attributeLines() -> [String] {
        var lines: [String] = []
        for result in attributes {
            lines.append("chart \(result.chart)")
            for (index, pass) in result.passes.enumerated() { lines.append("pass \(index + 1) lots \(pass.lots) center \(real(pass.center)) out \(numbers(pass.out))") }
            lines.append("result \(status(result.converged)) passes \(result.passes.count) retained \(result.retained) removed \(numbers(result.removed))")
            for point in result.points {
                let value = result.chart == "np" ? String(point.lot.defectives) : result.chart == "c" ? String(point.lot.defects) : real(point.value)
                lines.append("lot \(point.lot.number) size \(point.lot.inspected) value \(value) lcl \(real(point.lcl)) ucl \(real(point.ucl)) z \(real(point.z)) status \(point.status)")
            }
            for signal in result.signals { lines.append("signal \(signal.rule) \(signal.start) \(signal.end) \(real(signal.value))") }
            lines.append("signals \(result.signals.count)")
        }
        return lines
    }
    func capabilityLines() -> [String] {
        var lines: [String] = []
        for group in capabilities {
            let result = group.result
            lines.append("group \(group.name) subgroups \(group.groups) values \(result.samples.count)")
            for (name, value) in result.metrics where name != "ppm" { lines.append("\(name) \(real(value))") }
            for name in ["cpk", "ppk"] {
                let bounds = confidence(result.value(name), result.samples.count, settings.ciZ)
                lines.append("\(name)_ci \(real(bounds.0)) \(real(bounds.1))")
            }
            lines.append("below_lsl \(result.below)")
            lines.append("above_usl \(result.above)")
            lines.append("ppm \(real(result.value("ppm")))")
            for sample in result.samples where sample.value < settings.lsl || sample.value > settings.usl {
                lines.append("out_of_spec sample \(sample.number) subgroup \(sample.subgroup) value \(sample.value) side \(sample.value < settings.lsl ? "low" : "high")")
            }
            lines.append("verdict \(result.verdict)")
            lines += histogram(result, settings)
        }
        for window in rolling {
            let result = window.result
            let metrics = ["mean", "sigma_within", "sigma_overall", "cpk", "ppk"].map { "\($0) \(real(result.value($0)))" }.joined(separator: " ")
            lines.append("rolling \(window.first) \(window.last) \(metrics) verdict \(result.verdict)")
        }
        return lines
    }
    func chartLines() -> [String] {
        var lines: [String] = []
        for (name, chart, family) in [("XBAR", "XBAR_R", "XBAR_R"), ("R", "R", "XBAR_R"), ("S", "S", "XBAR_S")] {
            let limits = chartLimits(chart)
            lines.append(limitsText("chart \(name)", limits))
            for group in groups {
                let value = chart == "R" ? Double(group.range) : chart == "S" ? group.sd : group.mean
                let mark = group.number > settings.phase1 ? "2" : estimates[family]!.removed.contains(group.number) ? "x" : "1"
                let band = variableBand(limits, value, group.number > settings.phase1 && hasSignal(chart, group.number))
                lines.append("\(String(format: "%3d", group.number)) \(mark) \(band) \(real(value))")
            }
        }
        lines.append("chart CUSUM h \(real(interval))")
        for point in cusum {
            let band = cusumBand(point.upper, point.lower, interval, hasSignal("CUSUM", point.number, "UPPER"), hasSignal("CUSUM", point.number, "LOWER"))
            lines.append("\(String(format: "%3d", point.number)) \(band) \(real(point.upper)) \(real(point.lower))")
        }
        for (chart, points, width) in [("EWMA", ewma, ewmaWidth), ("MA", movingAverage, maWidth)] {
            lines.append(limitsText("chart \(chart)", Limits(lcl: mu - width, cl: mu, ucl: mu + width)))
            for point in points {
                let band = smoothBand(width, point.width, point.value, mu, hasSignal(chart, point.number))
                lines.append("\(String(format: "%3d", point.number)) \(band) \(real(point.value)) \(real(mu - point.width)) \(real(mu + point.width))")
            }
        }
        for (index, result) in attributes.enumerated() {
            lines.append(limitsText("chart \(["P_STD", "NP_STD", "C_STD", "U_STD"][index])", Limits(lcl: -3, cl: 0, ucl: 3)))
            for point in result.points { lines.append("\(String(format: "%3d", point.lot.number)) \(standardBand(point.z, point.status == "ok")) \(real(point.z))") }
        }
        return lines
    }
}

let analysis = try Analysis(readSettings(), readMeasurements(), readLots())
analysis.run()
try FileManager.default.createDirectory(atPath: "output", withIntermediateDirectories: true)
for (name, lines) in [("limits.txt", analysis.limitsLines()), ("signals.csv", analysis.signalLines()), ("events.txt", analysis.eventLines()), ("subgroups.csv", analysis.subgroupLines()), ("attribute_charts.txt", analysis.attributeLines()), ("capability.txt", analysis.capabilityLines()), ("charts.txt", analysis.chartLines())] {
    try (lines.joined(separator: "\n") + "\n").write(toFile: "output/\(name)", atomically: true, encoding: .utf8)
}
