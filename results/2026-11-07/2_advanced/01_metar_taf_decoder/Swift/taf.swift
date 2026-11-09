import Foundation

let tafSlots = ["wind", "visibility", "weather", "cloud"]

let temporaryKinds = ["TEMPO", "PROB30", "PROB40", "PROB30 TEMPO", "PROB40 TEMPO"]

final class Change {
    let kind: String, start: Int, end: Int, groups: [WordGroup]
    var state = State()
    init(_ kind: String, _ start: Int, _ end: Int, _ groups: [WordGroup]) {
        self.kind = kind
        self.start = start
        self.end = end
        self.groups = groups
    }
}

final class Forecast {
    let number: Int, station: Station, issue: Int, modifier: String, start: Int, end: Int
    var base = State(), changes: [Change] = []
    init(_ number: Int, _ station: Station, _ issue: Int, _ modifier: String, _ start: Int, _ end: Int) {
        self.number = number
        self.station = station
        self.issue = issue
        self.modifier = modifier
        self.start = start
        self.end = end
    }
}

func fmIndicator(_ t: String) -> Bool {
    captures("FM([0-9]{6})", t) != nil
}

func changeIndicator(_ t: String) -> Bool {
    ["BECMG", "TEMPO", "PROB30", "PROB40"].contains(t) || fmIndicator(t)
}

func parsePeriod(_ t: String, _ issueDay: Int, _ c: Calendar) -> (Int, Int)? {
    guard let m = captures("([0-9]{2})([0-9]{2})/([0-9]{2})([0-9]{2})", t) else {
        return nil
    }
    let n = m.map {
        Int($0)!
    }
    if n[1] > 23 || n[3] < 1 || n[3] > 24 {
        return nil
    }
    guard let s = c.forecastTime(n[0], n[1], 0, issueDay), let e = c.forecastTime(n[2], n[3], 0, issueDay), s < e else {
        return nil
    }
    return (s, e)
}

func splitChanges(_ f: Forecast, _ groups: [WordGroup], _ c: Calendar, _ errors: inout [WordGroup]) -> ([WordGroup], [Change]) {
    var i = 0
    while i < groups.count && !changeIndicator(groups[i].1) {
        i += 1
    }
    let base = Array(groups.prefix(i))
    var changes: [Change] = []
    while i < groups.count { let indicator = groups[i]
        i += 1
        var kind = indicator.1, start: Int? = nil, end = 0
        if ["PROB30", "PROB40"].contains(kind) && i < groups.count && groups[i].1 == "TEMPO" {
            kind += " TEMPO"
            i += 1
        }
        if fmIndicator(kind) {
            let d = Int(slice(kind, 2, 4))!, h = Int(slice(kind, 4, 6))!, m = Int(slice(kind, 6))!
            start = h <= 23 && m <= 59 ? c.forecastTime(d, h, m, f.issue / 1440 + 1) : nil
            if let t = start, t >= f.start && t < f.end {
                kind = "FM"
                end = t
            } else {
                errors.append((indicator.0, "invalid period \"\(kind)\""))
                start = nil
            }
        } else if i == groups.count || captures("([0-9]{4})/([0-9]{4})", groups[i].1) == nil {
            errors.append((indicator.0, "missing period \"\(kind)\""))
        } else {
            let p = groups[i]
            i += 1
            if let period = parsePeriod(p.1, f.issue / 1440 + 1, c), period.0 >= f.start && period.1 <= f.end {
                start = period.0
                end = period.1
            } else {
                errors.append((p.0, "invalid period \"\(p.1)\""))
            }
        }
        let first = i
        while i < groups.count && !changeIndicator(groups[i].1) {
            i += 1
        }
        if let start {
            changes.append(Change(kind, start, end, Array(groups[first..<i])))
        }
    }
    return (base, changes)
}

func overlay(_ s: State, _ c: State) -> State {
    State(c.wind ?? s.wind, c.visibility ?? s.visibility, c.weather ?? s.weather, c.cloud ?? s.cloud)
}

func prevailing(_ f: Forecast, _ h: Int) -> State {
    var state = f.base
    for c in f.changes {
        if c.kind == "FM" && c.start <= h {
            state = c.state
        } else if c.kind == "BECMG" && c.end <= h {
            state = overlay(state, c.state)
        }
    }
    return state
}

func temporary(_ f: Forecast, _ h: Int) -> [(String, State)] {
    let p = prevailing(f, h)
    return f.changes.filter {
        temporaryKinds.contains($0.kind) && $0.start <= h && h < $0.end
    }.map {
        ($0.kind, overlay(p, $0.state))
    }
}
