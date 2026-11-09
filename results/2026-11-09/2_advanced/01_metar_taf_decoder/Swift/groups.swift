import Foundation

let descriptors = ["MI":"shallow", "BC":"patches", "PR":"partial", "DR":"low drifting", "BL":"blowing", "SH":"showers", "TS":"thunderstorm", "FZ":"freezing"]

let phenomena = ["DZ":"drizzle", "RA":"rain", "SN":"snow", "SG":"snow grains", "IC":"ice crystals", "PL":"ice pellets", "GR":"hail", "GS":"small hail", "UP":"unknown precipitation", "BR":"mist", "FG":"fog", "FU":"smoke", "VA":"volcanic ash", "DU":"dust", "SA":"sand", "HZ":"haze", "PY":"spray", "PO":"dust whirls", "SQ":"squalls", "FC":"funnel cloud", "SS":"sandstorm", "DS":"duststorm"]

let precipitation: Set<String> = ["DZ", "RA", "SN", "SG", "IC", "PL", "GR", "GS", "UP"]

let amounts = ["FEW":"few", "SCT":"scattered", "BKN":"broken", "OVC":"overcast"]

let clearSkies = ["SKC":"sky clear", "CLR":"clear below 12000 ft", "NSC":"no significant cloud"]

let intensities = ["-":"light", "+":"heavy", "VC":"nearby"]

struct Reading {
    let qualifier: String
    let value: Int
}

struct Group {
    let text: String
    let kind: String
    let direction: String
    let speed: Int
    let gust: Int?
    let unit: String
    let firstDirection: Int
    let secondDirection: Int
    let visibilityKind: String
    let qualifier: String
    let meters: Int
    let whole: Int
    let numerator: Int
    let denominator: Int
    let joined: Bool
    let runway: String
    let readings: [Reading]
    let feet: Bool
    let trend: String
    let intensity: String
    let codes: [String]
    let amount: String
    let height: Int
    let cloudType: String
    let air: Int
    let dewPoint: Int
    let pressureValue: Int
    init(_ text: String, _ kind: String,
         direction: String = "",
         speed: Int = 0,
         gust: Int? = nil,
         unit: String = "",
         firstDirection: Int = 0,
         secondDirection: Int = 0,
         visibilityKind: String = "",
         qualifier: String = "",
         meters: Int = 0,
         whole: Int = 0,
         numerator: Int = 0,
         denominator: Int = 0,
         joined: Bool = false,
         runway: String = "",
         readings: [Reading] = [],
         feet: Bool = false,
         trend: String = "",
         intensity: String = "",
         codes: [String] = [],
         amount: String = "",
         height: Int = 0,
         cloudType: String = "",
         air: Int = 0,
         dewPoint: Int = 0,
         pressureValue: Int = 0) {
        self.text = text
        self.kind = kind
        self.direction = direction
        self.speed = speed
        self.gust = gust
        self.unit = unit
        self.firstDirection = firstDirection
        self.secondDirection = secondDirection
        self.visibilityKind = visibilityKind
        self.qualifier = qualifier
        self.meters = meters
        self.whole = whole
        self.numerator = numerator
        self.denominator = denominator
        self.joined = joined
        self.runway = runway
        self.readings = readings
        self.feet = feet
        self.trend = trend
        self.intensity = intensity
        self.codes = codes
        self.amount = amount
        self.height = height
        self.cloudType = cloudType
        self.air = air
        self.dewPoint = dewPoint
        self.pressureValue = pressureValue
    }
    var calm: Bool { kind == "wind" && direction == "000" }
    var directed: Bool { kind == "wind" && direction != "VRB" && !calm }
    var strength: Int { gust ?? speed }
    var descriptor: String { codes.first.flatMap { descriptors[$0] == nil ? nil : $0 } ?? "" }
    var weatherPhenomena: [String] { codes.filter { phenomena[$0] != nil } }
}

struct State {
    var wind: Group?
    var visibility: Group?
    var weather: [Group]?
    var cloud: [Group]?
    init(_ wind: Group? = nil, _ visibility: Group? = nil, _ weather: [Group]? = nil, _ cloud: [Group]? = nil) {
        self.wind = wind
        self.visibility = visibility
        self.weather = weather
        self.cloud = cloud
    }
}

final class Section {
    let runways: [String]
    let allowsNsw: Bool
    var state = State()
    var modifier: Group?
    var variation: Group?
    var temperature: Group?
    var pressure: Group?
    var noTrend: Group?
    var rvrs: [Group] = []
    init(_ runways: [String] = [], _ allowsNsw: Bool = false) {
        self.runways = runways
        self.allowsNsw = allowsNsw
    }
    func record(_ g: Group) {
        switch g.kind {
            case "wind":
                state.wind = Group(g.text, g.kind, direction: g.direction,
                    speed: knots(g.speed, g.unit), gust: g.gust.map { knots($0, g.unit) }, unit: "KT")
            case "visibility": state.visibility = g
            case "weather": state.weather = (state.weather ?? []) + [g]
            case "cloud": state.cloud = (state.cloud ?? []) + [g]
            case "modifier": modifier = g
            case "variation": variation = g
            case "temperature": temperature = g
            case "pressure": pressure = g
            case "no trend": noTrend = g
            case "rvr": rvrs.append(g)
            default: break
        }
    }
}

func slice(_ s: String, _ first: Int, _ last: Int? = nil) -> String {
    String(s.dropFirst(first).prefix((last ?? s.count) - first))
}

func captures(_ pattern: String, _ text: String) -> [String]? {
    let re = try! NSRegularExpression(pattern: "^(?:" + pattern + ")$")
    let ns = text as NSString
    guard let m = re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)), m.range.length == ns.length else {
        return nil
    }
    return (1..<m.numberOfRanges).map {
        let r = m.range(at: $0)
        return r.location == NSNotFound ? "" : ns.substring(with: r)
    }
}

func digits(_ text: String, _ a: Int, _ b: Int) -> Bool {
    text.count >= a && text.count <= b && text.utf8.allSatisfy {
        $0 >= 48 && $0 <= 57
    }
}

func parseGroup(_ kind: String, _ t: String) -> Group? {
    switch kind {
    case "modifier": if ["AUTO", "COR"].contains(t) { return Group(t, kind) }
    case "no trend": if t == "NOSIG" { return Group(t, kind) }
    case "wind":
        if let m = captures("(VRB|[0-9]{3})([0-9]{2,3})(?:G([0-9]{2,3}))?(KT|MPS)", t) {
            return Group(t, kind, direction: m[0], speed: Int(m[1])!, gust: Int(m[2]), unit: m[3])
        }
    case "variation":
        if let m = captures("([0-9]{3})V([0-9]{3})", t) {
            return Group(t, kind, firstDirection: Int(m[0])!, secondDirection: Int(m[1])!)
        }
    case "visibility":
        if t == "CAVOK" { return Group(t, kind, visibilityKind: "CAVOK", qualifier: "P", meters: 10000) }
        if digits(t, 4, 4) { return Group(t, kind, visibilityKind: "METERS", qualifier: t == "9999" ? "P" : "", meters: t == "9999" ? 10000 : Int(t)!) }
        if let m = captures("([0-9]) ([0-9])/([0-9]{1,2})SM", t) {
            return Group(t, kind, visibilityKind: "MILES", whole: Int(m[0])!, numerator: Int(m[1])!, denominator: Int(m[2])!, joined: true)
        }
        if let m = captures("([MP]?)(?:([0-9]{1,2})|([0-9])/([0-9]{1,2}))SM", t) {
            return Group(t, kind, visibilityKind: "MILES", qualifier: m[0], whole: Int(m[1]) ?? 0, numerator: Int(m[2]) ?? 0, denominator: Int(m[3]) ?? 0)
        }
    case "rvr":
        if let m = captures("R([0-9]{2}[LCR]?)/([MP]?)([0-9]{4})(?:V([MP]?)([0-9]{4}))?(FT)?([UDN]?)", t) {
            let readings = [Reading(qualifier: m[1], value: Int(m[2])!)] + (m[4].isEmpty ? [] : [Reading(qualifier: m[3], value: Int(m[4])!)])
            return Group(t, kind, runway: m[0], readings: readings, feet: m[5] == "FT", trend: m[6])
        }
    case "weather":
        if t == "NSW" { return Group(t, kind) }
        if let m = captures("(-|\\+|VC)?([A-Z]+)", t), m[1].count % 2 == 0 {
            let codes = stride(from: 0, to: m[1].count, by: 2).map { slice(m[1], $0, $0 + 2) }
            if codes.allSatisfy({ descriptors[$0] != nil || phenomena[$0] != nil }) { return Group(t, kind, intensity: m[0], codes: codes) }
        }
    case "cloud":
        if clearSkies[t] != nil { return Group(t, kind, amount: t) }
        if let m = captures("(FEW|SCT|BKN|OVC|VV)([0-9]{3})(CB|TCU)?", t), m[0] != "VV" || m[2].isEmpty {
            return Group(t, kind, amount: m[0], height: Int(m[1])! * 100, cloudType: m[2])
        }
    case "temperature":
        if let m = captures("(M?[0-9]{2})/(M?[0-9]{2})", t) {
            func celsius(_ v: String) -> Int { v.hasPrefix("M") ? -Int(v.dropFirst())! : Int(v)! }
            return Group(t, kind, air: celsius(m[0]), dewPoint: celsius(m[1]))
        }
    case "pressure":
        if let m = captures("([AQ])([0-9]{4})", t) { return Group(t, kind, unit: m[0], pressureValue: Int(m[1])!) }
    default: break
    }
    return nil
}

func validGroup(_ g: Group, _ section: Section) -> Bool {
    let state = section.state
    switch g.kind {
    case "wind":
        if g.direction == "VRB" {
            if g.speed < 1 { return false }
        } else {
            let d = Int(g.direction)!
            if d > 360 || d % 10 != 0 || (d == 0) != (g.speed == 0) { return false }
        }
        return g.gust == nil || (!g.calm && g.gust! > g.speed)
    case "variation":
        return [g.firstDirection, g.secondDirection].allSatisfy { $0 >= 10 && $0 <= 360 && $0 % 10 == 0 } && g.firstDirection != g.secondDirection && state.wind?.directed == true
    case "visibility":
        if g.visibilityKind != "MILES" { return true }
        if g.denominator == 0 { return !g.text.contains("/") && g.whole >= 1 }
        return (!g.joined || g.whole >= 1) && [2, 4, 8, 16].contains(g.denominator) && g.numerator >= 1 && g.numerator < g.denominator
    case "rvr": return section.runways.contains(g.runway) && (g.readings.count == 1 || g.readings.first!.value < g.readings.last!.value)
    case "weather":
        let accepted = state.weather ?? [], p = g.weatherPhenomena
        if accepted.count >= 3 || accepted.contains(where: { $0.text == "NSW" }) { return false }
        if g.text == "NSW" { return section.allowsNsw && accepted.isEmpty }
        if g.codes.dropFirst().contains(where: { descriptors[$0] != nil }) || Set(p).count != p.count { return false }
        if p.isEmpty && !["TS", "SH"].contains(g.descriptor) { return false }
        if ["-", "+"].contains(g.intensity) && !p.contains(where: { precipitation.contains($0) }) { return false }
        return p.count < 2 || p.allSatisfy { precipitation.contains($0) }
    case "cloud":
        guard let last = state.cloud?.last else { return true }
        return amounts[g.amount] != nil && amounts[last.amount] != nil && g.height > last.height
    case "temperature": return g.dewPoint <= g.air
    case "pressure": return g.unit == "A" ? (2500...3150).contains(g.pressureValue) : (850...1070).contains(g.pressureValue)
    default: return true
    }
}
