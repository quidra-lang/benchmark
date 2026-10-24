import Foundation

let mainSlots = ["modifier", "wind", "variation", "visibility", "rvr", "weather", "cloud", "temperature", "pressure", "no trend"]

let trendSlots = ["wind", "visibility", "weather", "cloud"]

func repeatable(_ kind: String) -> Bool {
    ["rvr", "weather", "cloud"].contains(kind)
}

typealias WordGroup = (Int, String)

final class Trend {
    let kind: String, times: [String], groups: [WordGroup]
    let section = Section([], true)
    init(_ kind: String, _ times: [String], _ groups: [WordGroup]) {
        self.kind = kind
        self.times = times
        self.groups = groups
    }
}

func splitMetar(_ groups: [WordGroup]) -> ([WordGroup], [[WordGroup]], [WordGroup]) {
    let r = groups.firstIndex {
        $0.1 == "RMK"
    } ?? groups.count
    let before = Array(groups.prefix(r)), remarks = Array(groups.dropFirst(r + 1))
    let t = before.firstIndex {
        ["BECMG", "TEMPO"].contains($0.1)
    } ?? before.count
    var trends: [[WordGroup]] = []
    for g in before.dropFirst(t) {
        if ["BECMG", "TEMPO"].contains(g.1) {
            trends.append([])
        }
        trends[trends.count - 1].append(g)
    }
    return (Array(before.prefix(t)), trends, remarks)
}

func readTrend(_ groups: [WordGroup], _ errors: inout [WordGroup]) -> Trend? {
    func time(_ i: Int, _ prefixes: [String]) -> Bool {
        i < groups.count && captures("(FM|TL|AT)([0-9]{4})", groups[i].1) != nil && prefixes.contains(slice(groups[i].1, 0, 2))
    }
    let count = time(1, ["FM"]) ? (time(2, ["TL"]) ? 2 : 1) : (time(1, ["TL", "AT"]) ? 1 : 0)
    var times: [String] = []
    for (position, text) in groups.dropFirst().prefix(count) {
        if Int(slice(text, 2, 4))! > 23 || Int(slice(text, 4))! > 59 {
            errors.append((position, "invalid period \"\(text)\""))
            return nil
        }
        times.append(text)
    }
    return Trend(groups[0].1, times, Array(groups.dropFirst(1 + count)))
}

func readRemarks(_ groups: [WordGroup]) -> ([Int], [(Int, Int)]) {
    var pressures: [Int] = [], temperatures: [(Int, Int)] = []
    for (_, text) in groups {
        if let m = captures("SLP([0-9]{3})", text) {
            let p = Int(m[0])!
            pressures.append((p >= 500 ? 9000 : 10000) + p)
        }
        if let m = captures("T([01])([0-9]{3})([01])([0-9]{3})", text) {
            temperatures.append((Int(m[1])! * (m[0] == "1" ? -1 : 1), Int(m[3])! * (m[2] == "1" ? -1 : 1)))
        }
    }
    return (pressures, temperatures)
}
