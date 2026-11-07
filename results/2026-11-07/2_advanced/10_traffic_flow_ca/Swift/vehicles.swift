struct VehicleClass {
    let name: String
    let vmax: Int
    let weight: Int
    let overtakes: Bool
    let stops: Bool
}
final class Vehicle {
    let number: Int
    let vehicleClass: VehicleClass
    let source: String
    let arrival: Int
    var inserted = 0, exited = 0
    var sink = "-"
    var segment: Segment? = nil
    var lane = 0, cell = 0, speed = 0
    var turn: Turn? = nil
    var route: [String] = []
    var steps = 0, distance = 0, stoppedSteps = 0, stopCount = 0, laneChanges = 0, dwell = 0
    var completedStops: Set<String> = []
    init(_ number: Int, _ vehicleClass: VehicleClass, _ source: String, _ arrival: Int) { self.number = number; self.vehicleClass = vehicleClass; self.source = source; self.arrival = arrival }
    func maxSpeed() -> Int { min(vehicleClass.vmax, segment!.limit) }
    func place(_ destination: Segment, _ lane: Int, _ cell: Int) {
        segment?.put(self.lane, self.cell, 0)
        destination.put(lane, cell, number)
        segment = destination; self.lane = lane; self.cell = cell
    }
    func leave() { segment!.put(lane, cell, 0); segment = nil }
    func headingForStop() -> Bool {
        guard let segment, let stop = segment.stop else { return false }
        return vehicleClass.stops && !completedStops.contains(segment.id) && cell <= stop.cell
    }
    var travelTime: Int { exited - inserted + 1 }
}
func randomSlowdown(_ speed: Int, _ previous: Int, _ random: Int, _ moving: Int, _ stopped: Int) -> Int { speed > 0 && random % 1000 < (previous == 0 ? stopped : moving) ? speed - 1 : speed }
