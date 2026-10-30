import Foundation

struct AircraftType { let climb: Int; let descent: Int; let minimum: Int }
struct Waypoint { let x: Int; let y: Int; let level: Int? }
struct Plan {
    let callsign: String
    let type: String
    let departure: Int
    let level: Int
    let initialSpeed: Int
    let waypoints: [Waypoint]
    var speed: Int
    var delay = 0
    var offset = 0
    var history: [String] = []
    var levels: [Int] { [level + offset] + waypoints.dropFirst().compactMap { $0.level.map { $0 + offset } } }
}
struct Sector { let name: String; let x1: Int; let y1: Int; let x2: Int; let y2: Int; let lower: Int; let upper: Int; let capacity: Int }
struct Radar { let x0: Int; let y0: Int; let x1: Int; let y1: Int; let width: Int; let height: Int }
struct Settings {
    let dh: Int, dv: Int, lookahead: Int, maximumDelay: Int, minimumLevel: Int, maximumLevel: Int, sampleStart: Int, sampleEnd: Int
    let radar: Radar
    let snapshots: [Int]
    let leader: Int, alert: Int
    var samples: [Int] { Array(stride(from: sampleStart, to: sampleEnd, by: 60)) }
    init(_ rows: [[Int]]) {
        dh = rows[0][0]; dv = rows[0][1]; lookahead = rows[1][0]; maximumDelay = rows[2][0]; minimumLevel = rows[3][0]; maximumLevel = rows[3][1]
        sampleStart = rows[4][0]; sampleEnd = rows[4][1]
        let r = rows[5]; radar = Radar(x0: r[0], y0: r[1], x1: r[2], y1: r[3], width: r[4], height: r[5])
        snapshots = rows[6]; leader = rows[7][0]; alert = rows[8][0]
    }
}
struct Inputs { let plans: [Plan]; let types: [String: AircraftType]; let sectors: [Sector]; let settings: Settings }
func inputLines(_ name: String) throws -> [String] { try String(contentsOfFile: "input/" + name, encoding: .ascii).split(separator: "\n").map(String.init) }
func readInputs() throws -> Inputs {
    var types: [String: AircraftType] = [:]
    for line in try inputLines("aircraft.txt") { let fields = line.split(separator: " ").map(String.init); types[fields[0]] = AircraftType(climb: Int(fields[1])!, descent: Int(fields[2])!, minimum: Int(fields[3])!) }
    let sectors = try inputLines("sectors.txt").map { line -> Sector in
        let fields = line.split(separator: " ").map(String.init), v = fields.dropFirst().map { Int($0)! }
        return Sector(name: fields[0], x1: v[0], y1: v[1], x2: v[2], y2: v[3], lower: v[4], upper: v[5], capacity: v[6])
    }
    let plans = try inputLines("flights.csv").dropFirst().map { line -> Plan in
        let fields = line.split(separator: ",").map(String.init)
        let waypoints = fields[5].split(separator: " ").map { token -> Waypoint in let v = token.split(separator: ":").map { Int($0)! }; return Waypoint(x: v[0], y: v[1], level: v.count == 3 ? v[2] : nil) }
        return Plan(callsign: fields[0], type: fields[1], departure: Int(fields[2])!, level: Int(fields[3])!, initialSpeed: Int(fields[4])!, waypoints: waypoints, speed: Int(fields[4])!)
    }.sorted { $0.callsign < $1.callsign }
    let values = try inputLines("params.txt").map { $0.split(separator: " ").dropFirst().map { Int($0)! } }
    return Inputs(plans: plans, types: types, sectors: sectors, settings: Settings(values))
}
