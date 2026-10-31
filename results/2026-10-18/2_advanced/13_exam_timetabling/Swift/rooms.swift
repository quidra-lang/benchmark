struct Room {
    let id: String
    let capacity: Int
}

struct Placement {
    let course: Int
    let room: Int
    let firstSeat: Int
    let lastSeat: Int
}

func loadRooms(_ path: String, _ errors: inout [String]) throws -> [Room] {
    var accepted: [String: Room] = [:]
    for record in try readRecords(path) {
        let id = record.fields[0]
        let capacity = Int(record.fields[1])!
        if accepted[id] != nil {
            errors.append("rooms.csv line \(record.line): duplicate room \(id)")
        } else if capacity < 1 {
            errors.append("rooms.csv line \(record.line): bad capacity \(capacity)")
        } else {
            accepted[id] = Room(id: id, capacity: capacity)
        }
    }
    return accepted.values.sorted {
        $0.capacity == $1.capacity ? asciiLess($0.id, $1.id) : $0.capacity < $1.capacity
    }
}

func packingOrder(_ courses: [Course], _ group: [Int]) -> [Int] {
    group.sorted {
        courses[$0].size == courses[$1].size ? $0 < $1 : courses[$0].size > courses[$1].size
    }
}

func pack(_ rooms: [Room], _ courses: [Course], _ group: [Int]) -> [Placement]? {
    var remaining = rooms.map(\.capacity)
    var durations = Array<Int?>(repeating: nil, count: rooms.count)
    var placements: [Placement] = []
    for index in packingOrder(courses, group) {
        let course = courses[index]
        guard let room = rooms.indices.first(where: {
            remaining[$0] >= course.size && (durations[$0] == nil || durations[$0] == course.duration)
        }) else { return nil }
        let firstSeat = rooms[room].capacity - remaining[room] + 1
        placements.append(Placement(course: index, room: room, firstSeat: firstSeat, lastSeat: firstSeat + course.size - 1))
        remaining[room] -= course.size
        durations[room] = course.duration
    }
    return placements
}
