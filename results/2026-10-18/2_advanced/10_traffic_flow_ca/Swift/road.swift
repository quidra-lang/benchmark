final class Turn {
    let target: Segment
    let weight: Int
    var vehicles = 0
    init(_ target: Segment, _ weight: Int) { self.target = target; self.weight = weight }
}
final class BusStop {
    let segment: Segment
    let cell: Int
    let dwell: Int
    var buses = 0
    init(_ segment: Segment, _ cell: Int, _ dwell: Int) { self.segment = segment; self.cell = cell; self.dwell = dwell }
}
final class Segment {
    let id: String
    let start: String
    let end: String
    let length: Int
    let lanes: Int
    let limit: Int
    var cells: [[Int]]
    var junction: Junction? = nil
    var turns: [Turn] = []
    var stop: BusStop? = nil
    var entered = 0, vehicleSum = 0, speedSum = 0, maxVehicles = 0
    var greenSteps = 0, queueSum = 0, maxQueue = 0, failures = 0, passed = 0, blocked = 0
    var changes = [0, 0, 0]
    init(_ id: String, _ start: String, _ end: String, _ length: Int, _ lanes: Int, _ limit: Int) {
        self.id = id; self.start = start; self.end = end; self.length = length; self.lanes = lanes; self.limit = limit
        cells = Array(repeating: Array(repeating: 0, count: length), count: lanes)
    }
    func put(_ lane: Int, _ cell: Int, _ value: Int) { cells[lane - 1][cell] = value }
    func free(_ lane: Int, _ cell: Int, _ cap: Int) -> Int {
        var count = 0
        while count < cap && cell + count + 1 < length && cells[lane - 1][cell + count + 1] == 0 { count += 1 }
        return count
    }
    func first(_ lane: Int) -> Int { cells[lane - 1].firstIndex { $0 != 0 } ?? length }
    func safe(_ lane: Int, _ cell: Int) -> Bool { cells[lane - 1][max(0, cell - limit)...cell].allSatisfy { $0 == 0 } }
    func vehicleNumbers(_ lane: Int) -> [Int] { cells[lane - 1].filter { $0 > 0 } }
    func cellsText(_ lane: Int, _ vehicles: [Vehicle]) -> String { cells[lane - 1].map { $0 == 0 ? "." : $0 == -1 ? "#" : String(vehicles[$0 - 1].speed) }.joined() }
}
final class Incident {
    let segment: Segment
    let lane: Int
    let cell: Int
    let start: Int
    let end: Int
    var state = "planned"
    var activeStart = 0, activeEnd = 0
    init(_ segment: Segment, _ lane: Int, _ cell: Int, _ start: Int, _ end: Int) { self.segment = segment; self.lane = lane; self.cell = cell; self.start = start; self.end = end }
    func update(_ step: Int) -> String? {
        var event: String? = nil
        if state == "active" && step > end { state = "cleared"; segment.put(lane, cell, 0); event = "INCIDENT_END" }
        else if state == "planned" && step > end { state = "cancelled" }
        else if state == "planned" && step >= start && segment.cells[lane - 1][cell] == 0 { state = "active"; segment.put(lane, cell, -1); activeStart = step; event = "INCIDENT_START" }
        if state == "active" { activeEnd = step }
        return event
    }
}
