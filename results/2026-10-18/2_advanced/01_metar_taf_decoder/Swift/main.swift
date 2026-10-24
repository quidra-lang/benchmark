import Foundation

struct Runway {
    let name: String
    let heading: Int
}

final class Station {
    let code: String, elevation: Int, runways: [Runway], name: String
    init(_ code: String, _ elevation: Int, _ runways: [Runway], _ name: String) {
        self.code = code
        self.elevation = elevation
        self.runways = runways
        self.name = name
    }
    var title: String {
        "\(code) (\(name))"
    }
}

final class Report {
    let number: Int
    var words: [String]
    var errors: [WordGroup] = []
    init(_ number: Int, _ words: [String]) {
        self.number = number
        self.words = words
    }
}

struct Header {
    let kind: String, station: Station, time: Int, start: Int, end: Int, modifier: String, body: [WordGroup]
}

struct RunwayWind {
    let runway: Runway
    let mean: (Int, Int)
    let gust: (Int, Int)?
    let usable: Bool
}

final class Observation {
    let number: Int, time: Int, kind: String, station: Station, main: Section
    var trends: [Trend] = []
    var pressures: [Int] = []
    var temperatures: [(Int, Int)] = []
    var ceilingValue: Int?
    var pressureAltitude: Int?
    var densityAltitude: Int?
    var category = ""
    var winds: [RunwayWind]?
    var reasons: [String] = []
    init(_ number: Int, _ h: Header) {
        self.number = number
        time = h.time
        kind = h.kind
        station = h.station
        main = Section(h.station.runways.map {
            $0.name
        })
    }
}

func readLines(_ path: String) throws -> [String] {
    try String(contentsOfFile: path, encoding: .ascii).split(separator: "\n").map(String.init)
}

func joinGroups(_ words: [String], _ start: Int) -> [WordGroup] {
    var result: [WordGroup] = [], i = start
    while i < words.count {
        if digits(words[i], 1, 1) && i + 1 < words.count && captures("([0-9])/([0-9]{1,2})SM", words[i + 1]) != nil {
            result.append((i + 1, "\(words[i]) \(words[i + 1])"))
            i += 2
        } else {
            result.append((i + 1, words[i]))
            i += 1
        }
    }
    return result
}

func parseHeader(_ r: Report, _ stations: [String: Station], _ c: Calendar) -> Header? {
    let w = r.words, kind = w[0]
    func reject(_ p: Int, _ message: String) {
        r.errors.append((p, "rejected report, \(message)"))
    }
    if !["METAR", "SPECI", "TAF"].contains(kind) {
        reject(1, "invalid type \"\(kind)\"")
        return nil
    }
    var i = 1, modifier = "", station: Station? = nil, time = 0, start = 0, end = 0
    if kind == "TAF" && i < w.count && ["AMD", "COR"].contains(w[i]) {
        modifier = w[i]
        i += 1
    }
    for item in ["station", "time"] + (kind == "TAF" ? ["validity"] : []) {
        if i == w.count {
            reject(i + 1, "missing \(item)")
            return nil
        }
        let text = w[i]
        var valid = false
        switch item {
            case "station":
            station = stations[text]
            valid = station != nil
            case "time":
            if let m = captures("([0-9]{2})([0-9]{2})([0-9]{2})Z", text) {
                let n = m.map {
                    Int($0)!
                }
                valid = n[0] >= 1 && n[0] <= c.days && n[1] <= 23 && n[2] <= 59
                if valid {
                    time = dayMinutes(n[0], n[1], n[2])
                }
            }
            default:
            if let p = parsePeriod(text, time / 1440 + 1, c), p.1 <= p.0 + 1800 {
                valid = true
                start = p.0
                end = p.1
            }
        }
        if !valid {
            reject(i + 1, "invalid \(item) \"\(text)\"")
            return nil
        }
        i += 1
    }
    return Header(kind: kind, station: station!, time: time, start: start, end: end, modifier: modifier, body: joinGroups(w, i))
}

func matchGroups(_ groups: [WordGroup], _ slots: [String], _ section: Section, _ errors: inout [WordGroup]) {
    var current = 0
    for (position, text) in groups { var index: Int? = nil, value: Group? = nil
        for j in current..<slots.count {
            if let g = parseGroup(slots[j], text) {
                index = j
                value = g
                break
            }
        }
        guard let index, let g = value else {
            let earlier = slots.prefix(current).contains {
                parseGroup($0, text) != nil
            }
            errors.append((position, "\(earlier ? "out of order group" : "unknown group") \"\(text)\""))
            continue
        }
        if !validGroup(g, section) {
            errors.append((position, "invalid group \"\(text)\""))
            continue
        }
        section.record(g)
        if g.kind == "visibility" && g.visibilityKind == "CAVOK" {
            section.state.weather = []
            section.state.cloud = []
            current = slots.firstIndex(of: "cloud")! + 1
        } else {
            current = index + (repeatable(slots[index]) ? 0 : 1)
        }
    }
}

func forecastState(_ groups: [WordGroup], _ nsw: Bool, _ errors: inout [WordGroup]) -> State {
    let section = Section([], nsw)
    matchGroups(groups, tafSlots, section, &errors)
    return section.state
}

func decodeObservation(_ r: Report, _ h: Header) -> Observation {
    let o = Observation(r.number, h), (main, trends, remarks) = splitMetar(h.body)
    matchGroups(main, mainSlots, o.main, &r.errors)
    for groups in trends {
        if let t = readTrend(groups, &r.errors) {
            matchGroups(t.groups, trendSlots, t.section, &r.errors)
            o.trends.append(t)
        }
    }
    (o.pressures, o.temperatures) = readRemarks(remarks)
    return o
}

func decodeForecast(_ r: Report, _ h: Header, _ c: Calendar) -> Forecast {
    let f = Forecast(r.number, h.station, h.time, h.modifier, h.start, h.end)
    let (base, changes) = splitChanges(f, h.body, c, &r.errors)
    f.base = forecastState(base, false, &r.errors)
    f.changes = changes
    for change in changes {
        change.state = forecastState(change.groups, true, &r.errors)
    }
    return f
}

func ceiling(_ s: State) -> Int? {
    s.cloud?.first {
        ["BKN", "OVC", "VV"].contains($0.amount)
    }?.height
}

func flightCategory(_ s: State) -> String {
    let c = ceiling(s), (n, d) = s.visibility.map(miles) ?? (1, 0)
    if c != nil && c! < 500 || n < d {
        return "LIFR"
    }
    if c != nil && c! < 1000 || n < 3 * d {
        return "IFR"
    }
    if c != nil && c! <= 3000 || n <= 5 * d {
        return "MVFR"
    }
    return "VFR"
}

func pressureInhg(_ g: Group) -> Int {
    g.unit == "A" ? g.pressureValue : inhg(g.pressureValue)
}

func components(_ d: Int, _ h: Int, _ w: Int) -> (Int, Int) {
    (floorDiv(w * cosine(d - h), 1000), floorDiv(w * sine(d - h), 1000))
}

func windChanges(_ a: Group?, _ b: Group?, _ alpha: Int) -> [String] {
    guard let a, let b else {
        return []
    }
    var result: [String] = []
    if a.directed && b.directed && max(a.speed, b.speed) >= 10 {
        let d = abs(Int(a.direction)! - Int(b.direction)!) % 360
        if min(d, 360 - d) >= alpha {
            result.append("wind shift")
        }
    }
    if abs(a.speed - b.speed) >= 10 {
        result.append("wind speed")
    }
    return result
}

func thunder(_ s: State) -> Bool {
    (s.weather ?? []).contains {
        $0.descriptor == "TS"
    }
}

func freezing(_ s: State) -> Bool {
    (s.weather ?? []).contains {
        $0.descriptor == "FZ" && $0.weatherPhenomena.contains {
            ["DZ", "RA"].contains($0)
        }
    }
}

func derive(_ o: Observation, _ previous: Observation?, _ crossLimit: Int, _ tailLimit: Int) {
    let s = o.main.state, p = o.main.pressure, t = o.main.temperature
    o.ceilingValue = ceiling(s)
    o.category = flightCategory(s)
    if let p {
        let a = o.station.elevation + (2992 - pressureInhg(p)) * 10
        o.pressureAltitude = a
        if let t {
            o.densityAltitude = a + floorDiv(120 * (1000 * t.air - 15000 + 2 * a), 1000)
        }
    }
    if let w = s.wind, w.directed {
        o.winds = o.station.runways.map { r in
            let mean = components(Int(w.direction)!, r.heading, w.speed)
            let gust = w.gust != nil ? components(Int(w.direction)!, r.heading, w.gust!) : nil
            let deciding = gust ?? mean
            return RunwayWind(runway: r, mean: mean, gust: gust, usable: abs(deciding.1) <= crossLimit && -deciding.0 <= tailLimit)
        }
    }
    if o.kind != "SPECI" {
        return
    }
    guard let previous else {
        o.reasons = ["no previous report"]
        return
    }
    if previous.category != o.category {
        o.reasons.append("category \(previous.category) to \(o.category)")
    }
    let before = previous.main.state
    o.reasons += windChanges(before.wind, s.wind, 45)
    if thunder(before) != thunder(s) {
        o.reasons.append("thunderstorm \(thunder(s) ? "began" : "ended")")
    }
    if freezing(before) != freezing(s) {
        o.reasons.append("freezing precipitation \(freezing(s) ? "began" : "ended")")
    }
    if o.reasons.isEmpty {
        o.reasons = ["no criteria met"]
    }
}

func windPhrase(_ g: Group) -> String {
    var t = g.calm ? "calm" : g.direction == "VRB" ? "variable at \(g.speed) KT" : "\(g.direction) degrees at \(g.speed) KT"
    if g.gust != nil {
        t += " gusting \(g.gust!) KT"
    }
    return t
}

func mileNumber(_ g: Group) -> String {
    if g.denominator == 0 {
        return String(g.whole)
    }
    return (g.whole == 0 ? "" : "\(g.whole) ") + "\(g.numerator)/\(g.denominator)"
}

func qualifier(_ q: String) -> String {
    q == "M" ? "less than " : q == "P" ? "more than " : ""
}

func visibilityPhrase(_ g: Group) -> String {
    if g.visibilityKind == "CAVOK" {
        return "10 km or more (CAVOK)"
    }
    if g.visibilityKind == "METERS" {
        return g.qualifier == "P" ? "10 km or more" : "\(g.meters) m"
    }
    return qualifier(g.qualifier) + mileNumber(g) + " SM"
}

func weatherPhrase(_ g: Group) -> String {
    if g.text == "NSW" {
        return "no significant weather"
    }
    var parts: [String] = []
    if let intensity = intensities[g.intensity] {
        parts.append(intensity)
    }
    if let descriptor = descriptors[g.descriptor] {
        parts.append(descriptor)
    }
    if !g.weatherPhenomena.isEmpty {
        parts.append(g.weatherPhenomena.map {
            phenomena[$0]!
        }.joined(separator: " and "))
    }
    return parts.joined(separator: " ")
}

func cloudPhrase(_ g: Group) -> String {
    if let clear = clearSkies[g.amount] {
        return clear
    }
    if g.amount == "VV" {
        return "vertical visibility \(g.height) ft"
    }
    return "\(amounts[g.amount]!) at \(g.height) ft" + (g.cloudType == "CB" ? " cumulonimbus" : g.cloudType == "TCU" ? " towering cumulus" : "")
}

func summary(_ s: State) -> String {
    var parts: [String] = []
    if let w = s.wind {
        parts.append("wind " + windPhrase(w))
    }
    if let v = s.visibility {
        parts.append("visibility " + visibilityPhrase(v))
    }
    if let weather = s.weather, !weather.isEmpty {
        parts.append("weather " + weather.map(weatherPhrase).joined(separator: ", "))
    }
    if let cloud = s.cloud, !cloud.isEmpty {
        parts.append("cloud " + cloud.map(cloudPhrase).joined(separator: ", "))
    }
    return parts.isEmpty ? "no conditions" : parts.joined(separator: "; ")
}

func windCode(_ g: Group) -> String {
    if g.calm {
        return "00000KT"
    }
    return g.direction + pad(g.speed, 2) + (g.gust != nil ? "G" + pad(g.gust!, 2) : "") + "KT"
}

func visibilityCode(_ g: Group) -> String {
    if g.visibilityKind == "CAVOK" {
        return "CAVOK"
    }
    if g.visibilityKind == "METERS" {
        return g.qualifier == "P" ? "9999" : pad(g.meters, 4)
    }
    return g.qualifier + mileNumber(g) + "SM"
}

func tokens(_ s: State) -> String {
    var parts: [String] = []
    if let w = s.wind {
        parts.append(windCode(w))
    }
    if let v = s.visibility {
        parts.append(visibilityCode(v))
    }
    parts += (s.weather ?? []).filter {
        $0.text != "NSW"
    }.map {
        $0.text
    }
    parts += (s.cloud ?? []).map {
        $0.text
    }
    return (parts + [flightCategory(s)]).joined(separator: " ")
}

func tenths(_ v: Int) -> String {
    "\(v < 0 ? "-" : "")\(abs(v) / 10).\(abs(v) % 10)"
}

func inhgText(_ v: Int) -> String {
    "\(v / 100).\(pad(v % 100, 2))"
}

func componentPhrase(_ c: (Int, Int)) -> String {
    let head = c.0 < 0 ? "tailwind \(-c.0)" : "headwind \(c.0)"
    let side = c.1 > 0 ? " from right" : c.1 < 0 ? " from left" : ""
    return "\(head) KT, crosswind \(abs(c.1)) KT\(side)"
}

func rvrPhrase(_ g: Group) -> String {
    let readings = g.readings.map { qualifier($0.qualifier) + String($0.value) }
    let value = readings.count == 1 ? readings.first! : "between \(readings.first!) and \(readings.last!)"
    let trend = g.trend.isEmpty ? "" : ", " + ["U":"rising", "D":"falling", "N":"no change"][g.trend]!
    return "runway \(g.runway) \(value)" + (g.feet ? " ft" : " m") + trend
}

func altitude(_ v: Int?) -> String {
    v.map {
        "\($0) ft"
    } ?? "not available"
}

func observationLines(_ o: Observation, _ c: Calendar) -> [String] {
    let m = o.main, s = m.state, w = s.wind, v = s.visibility, t = m.temperature, p = m.pressure
    var lines = ["REPORT \(o.number): \(o.kind) \(o.station.title)", "  time: \(c.stamp(o.time))"]
    if let modifier = m.modifier {
        lines.append("  modifier: " + (modifier.text == "AUTO" ? "automated" : "corrected"))
    }
    var wind = w.map(windPhrase) ?? "not reported"
    if let variation = m.variation {
        wind += ", varying between \(pad(variation.firstDirection, 3)) and \(pad(variation.secondDirection, 3)) degrees"
    }
    lines += ["  wind: \(wind)", "  visibility: \(v.map(visibilityPhrase) ?? "not reported")"]
    for g in m.rvrs {
        lines.append("  runway visual range: " + rvrPhrase(g))
    }
    for g in s.weather ?? [] {
        lines.append("  weather: " + weatherPhrase(g))
    }
    let clouds = v?.visibilityKind == "CAVOK" ? ["no significant cloud"] : s.cloud.map {
        $0.map(cloudPhrase)
    } ?? ["not reported"]
    for text in clouds {
        lines.append("  cloud: " + text)
    }
    let temperature = t.map {
        "\($0.air) C, dew point \($0.dewPoint) C, spread \($0.air - $0.dewPoint) C"
    } ?? "not reported"
    lines.append("  temperature: " + temperature)
    let pressure = p.map { g in
        g.unit == "A" ? "\(inhgText(g.pressureValue)) inHg (\(hpa(g.pressureValue)) hPa)" : "\(g.pressureValue) hPa (\(inhgText(pressureInhg(g))) inHg)"
    } ?? "not reported"
    lines.append("  altimeter: " + pressure)
    if m.noTrend != nil {
        lines.append("  trend: no significant change")
    }
    for trend in o.trends {
        var text = trend.kind == "BECMG" ? "becoming" : "temporarily"
        for time in trend.times {
            let prefix = ["FM":"from", "TL":"until", "AT":"at"][slice(time, 0, 2)]!
            text += " \(prefix) \(slice(time, 2, 4)):\(slice(time, 4))Z"
        }
        lines.append("  trend: \(text): \(summary(trend.section.state))")
    }
    for pressure in o.pressures {
        lines.append("  sea level pressure: \(tenths(pressure)) hPa")
    }
    for (air, dew) in o.temperatures {
        lines.append("  precise temperature: \(tenths(air)) C, dew point \(tenths(dew)) C")
    }
    lines += ["  ceiling: \(o.ceilingValue.map { "\($0) ft" } ?? "none")", "  flight category: \(o.category)", "  pressure altitude: \(altitude(o.pressureAltitude))", "  density altitude: \(altitude(o.densityAltitude))"]
    if let winds = o.winds {
        var preferred: RunwayWind? = nil, usable: [String] = []
        for r in winds {
            lines.append("  runway \(r.runway.name): \(componentPhrase(r.mean))" + (r.gust.map {
                "; gusts " + componentPhrase($0)
            } ?? ""))
            if r.usable {
                usable.append(r.runway.name)
                if preferred == nil || r.mean.0 > preferred!.mean.0 {
                    preferred = r
                }
            }
        }
        lines.append("  usable runways: " + (usable.isEmpty ? "none" : usable.joined(separator: " ")))
        lines.append("  preferred runway: " + (preferred?.runway.name ?? "none"))
    } else {
        lines.append("  runway wind: not computed")
    }
    if o.kind == "SPECI" {
        lines.append("  speci check: " + o.reasons.joined(separator: ", "))
    }
    return lines
}

func forecastLines(_ f: Forecast, _ c: Calendar) -> [String] {
    var lines = ["REPORT \(f.number): TAF \(f.station.title)", "  issued: \(c.stamp(f.issue))"]
    if !f.modifier.isEmpty {
        lines.append("  modifier: " + (f.modifier == "AMD" ? "amended" : "corrected"))
    }
    lines += ["  valid: \(c.stamp(f.start)) to \(c.stamp(f.end))", "  base: \(summary(f.base))"]
    for g in f.changes {
        let period = c.stamp(g.start) + (g.kind == "FM" ? "" : " to " + c.stamp(g.end))
        lines.append("  \(g.kind) \(period): \(summary(g.state))")
    }
    return lines
}

func categoryCounts(_ cs: [String]) -> String {
    categories.map { name in "\(name) \(cs.filter { $0 == name }.count)"
    }.joined(separator: ", ")
}

func timelineLines(_ f: Forecast, _ c: Calendar) -> [String] {
    var lines = ["TAF \(f.station.code) issued \(c.stamp(f.issue)) valid \(c.stamp(f.start)) to \(c.stamp(f.end))"], cs: [String] = []
    for h in stride(from: f.start, to: f.end, by: 60) {
        let state = prevailing(f, h)
        var line = "\(c.stamp(h)) \(tokens(state))"
        for (kind, temporary) in temporary(f, h) {
            line += " | \(kind) \(tokens(temporary))"
        }
        lines.append(line)
        cs.append(flightCategory(state))
    }
    lines.append("summary: " + categoryCounts(cs))
    return lines
}

func extremeLines(_ os: [Observation], _ c: Calendar) -> [String] {
    var cold: Observation? = nil, warm: Observation? = nil, wind: Observation? = nil, cloud: Observation? = nil, vis: Observation? = nil
    for o in os {
        if let t = o.main.temperature {
            if cold == nil || t.air < cold!.main.temperature!.air {
                cold = o
            }
            if warm == nil || t.air > warm!.main.temperature!.air {
                warm = o
            }
        }
        if let w = o.main.state.wind, wind == nil || w.strength > wind!.main.state.wind!.strength {
            wind = o
        }
        if let height = o.ceilingValue, cloud == nil || height < cloud!.ceilingValue! {
            cloud = o
        }
        if let v = o.main.state.visibility, vis == nil || lessFraction(miles(v), miles(vis!.main.state.visibility!)) {
            vis = o
        }
    }
    func line(_ label: String, _ o: Observation?, _ describe: (Observation) -> String) -> String {
        guard let o else {
            return label + ": not available"
        }
        return "\(label): \(describe(o)) at \(c.stamp(o.time))"
    }
    return [
    line("lowest temperature", cold) {
        "\($0.main.temperature!.air) C"
    },
    line("highest temperature", warm) {
        "\($0.main.temperature!.air) C"
    },
    line("strongest wind", wind) {
        windPhrase($0.main.state.wind!)
    },
    line("lowest ceiling", cloud) {
        "\($0.ceilingValue!) ft"
    },
    line("lowest visibility", vis) {
        visibilityPhrase($0.main.state.visibility!)
    }
    ]
}

func tableRow(_ label: String, _ cells: [String]) -> String {
    label + String(repeating: " ", count: max(0, 8 - label.count)) + cells.map {
        String(repeating: " ", count: max(0, 6 - $0.count)) + $0
    }.joined()
}

func verificationLines(_ station: Station, _ observations: [Observation], _ forecasts: [Forecast], _ c: Calendar) -> [String] {
    let os = observations.filter {
        $0.station === station
    }, fs = forecasts.filter {
        $0.station === station
    }, cont = Contingency()
    var amendments: [String] = [], noForecast = 0, pairs = Array(repeating: 0, count: 5), hits = Array(repeating: 0, count: 5)
    var lines = ["station \(station.title)", "reports: METAR \(os.filter { $0.kind == "METAR" }.count), SPECI \(os.filter { $0.kind == "SPECI" }.count)", "observed categories: \(categoryCounts(os.map { $0.category }))"]
    lines += extremeLines(os, c)
    for o in os {
        guard let f = chosenForecast(fs, o.time) else {
            noForecast += 1
            continue
        }
        let h = o.time - o.time % 60, p = prevailing(f, h), expected = flightCategory(p)
        let alternatives = [expected] + temporary(f, h).map {
            flightCategory($0.1)
        }, hit = alternatives.contains(o.category)
        cont.add(expected, o.category, hit)
        var reasons: [String] = []
        if !hit {
            reasons.append("category \(o.category), forecast \(expected)")
        }
        if !windChanges(p.wind, o.main.state.wind, 60).isEmpty {
            reasons.append("wind \(windCode(o.main.state.wind!)), forecast \(windCode(p.wind!))")
        }
        if !reasons.isEmpty {
            amendments.append("amendment \(c.stamp(o.time)): " + reasons.joined(separator: "; "))
        }
    }
    for f in fs {
        for o in os where covers(f, o.time) {
            let h = o.time - o.time % 60, b = (h - f.start) / 360
            pairs[b] += 1
            if flightCategory(prevailing(f, h)) == o.category {
                hits[b] += 1
            }
        }
    }
    lines += ["verified: \(cont.total)", "no forecast: \(noForecast)", tableRow("forecast", categories + ["total"])]
    for i in 0..<4 {
        lines.append(tableRow(categories[i], (cont.table[i] + [cont.row(i)]).map(String.init)))
    }
    lines.append(tableRow("total", ((0..<4).map {
        cont.column($0)
    } + [cont.total]).map(String.init)))
    lines += ["hit rate: \(fraction(cont.hits, cont.total))", "hit rate with temporary groups: \(fraction(cont.temporaryHits, cont.total))", "heidke skill score: \(fraction(cont.skill.0, cont.skill.1))"]
    for i in 0..<4 {
        let pod = cont.detection(i), far = cont.falseAlarm(i)
        lines.append("\(categories[i]): pod \(fraction(pod.0, pod.1)), far \(fraction(far.0, far.1))")
    }
    for b in 0..<5 {
        lines.append("hours \(b * 6)-\(b * 6 + 5): \(fraction(hits[b], pairs[b]))")
    }
    return lines + amendments
}

func blocks(_ values: [[String]]) -> [String] {
    var lines: [String] = []
    for value in values {
        if !lines.isEmpty {
            lines.append("")
        }
        lines += value
    }
    return lines
}

func writeLines(_ path: String, _ lines: [String]) throws {
    try (lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n").write(toFile: path, atomically: true, encoding: .ascii)
}

func run() throws {
    var stations: [String: Station] = [:]
    for line in try readLines("input/stations.txt") {
        let p = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: false).map(String.init)
        let runways = p[2].split(separator: ",").map { entry in
            let a = entry.split(separator: "/")
            return Runway(name: String(a[0]), heading: Int(a[1])!)
        }
        stations[p[0]] = Station(p[0], Int(p[1])!, runways, p[3])
    }
    var settings: [String: [String]] = [:]
    for line in try readLines("input/params.txt") {
        let p = line.split(separator: " ").map(String.init)
        settings[p[0]] = Array(p.dropFirst())
    }
    let c = Calendar(year: Int(settings["YEAR"]![0])!, month: Int(settings["MONTH"]![0])!)
    let cross = Int(settings["CROSSWIND_LIMIT"]![0])!, tail = Int(settings["TAILWIND_LIMIT"]![0])!
    var reports: [Report] = []
    for line in try readLines("input/reports.txt") {
        let words = line.split(separator: " ").map(String.init)
        if line.hasPrefix(" ") {
            reports.last!.words += words
        } else {
            reports.append(Report(reports.count + 1, words))
        }
    }
    var observations: [Observation] = [], forecasts: [Forecast] = [], decoded: [[String]] = [], latest: [String: Observation] = [:]
    for r in reports {
        guard let h = parseHeader(r, stations, c) else {
            continue
        }
        if h.kind == "TAF" {
            let f = decodeForecast(r, h, c)
            forecasts.append(f)
            decoded.append(forecastLines(f, c))
        } else {
            let o = decodeObservation(r, h)
            derive(o, latest[h.station.code], cross, tail)
            latest[h.station.code] = o
            observations.append(o)
            decoded.append(observationLines(o, c))
        }
    }
    try FileManager.default.createDirectory(atPath: "output", withIntermediateDirectories: true)
    try writeLines("output/decoded.txt", blocks(decoded))
    let categoryLines = observations.map { o -> String in
        let v = o.main.state.visibility
        let visibility = v.map {
            $0.qualifier + String(meterValue($0))
        } ?? "NONE"
        return "\(o.station.code),\(c.stamp(o.time)),\(o.ceilingValue.map(String.init) ?? "NONE"),\(visibility),\(o.category)"
    }
    try writeLines("output/categories.csv", ["station,time,ceiling,visibility,category"] + categoryLines)
    try writeLines("output/taf_timeline.txt", blocks(forecasts.map {
        timelineLines($0, c)
    }))
    try writeLines("output/verification.txt", blocks(settings["VERIFY"]!.map {
        verificationLines(stations[$0]!, observations, forecasts, c)
    }))
    let errors = reports.flatMap { r in
        r.errors.sorted {
            $0.0 < $1.0
        }.map {
            "report \(r.number) word \($0.0): \($0.1)"
        }
    }
    try writeLines("output/errors.txt", errors)
}

try run()
