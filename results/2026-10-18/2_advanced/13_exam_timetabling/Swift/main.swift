import Foundation

typealias Assignment = [Int?]

let relationNames = ["BACK_TO_BACK", "SAME_DAY", "OVERNIGHT"]

struct ExamCalendar {
    let days: Int
    let periods: Int
    let lengths: [Int]
    let limit: Int
    let weights: [Int]
    let frontCount: Int
    let deadline: Int
    let ratio: Int
    let slotCount: Int
    var closed: Set<Int> = []
    var unavailable: [String: Set<Int>] = [:]
    var fixed: Assignment
    var orders: [(later: Int, earlier: Int)] = []
    var arrows: [[Int]]

    init(_ lines: [String], _ courseCount: Int) {
        let settings = lines.prefix(6).map { line in
            line.split(separator: " ").dropFirst().map { Int($0)! }
        }
        days = settings[0][0]
        lengths = settings[1]
        periods = settings[1].count
        limit = settings[2][0]
        weights = settings[3]
        frontCount = settings[4][0]
        deadline = settings[4][1]
        ratio = settings[5][0]
        slotCount = settings[0][0] * settings[1].count
        fixed = Array(repeating: nil, count: courseCount)
        arrows = Array(repeating: [], count: courseCount)
    }

    var slots: ClosedRange<Int> { 1...slotCount }

    func slotAt(_ dayText: String, _ periodText: String) -> Int? {
        let day = Int(dayText)!
        let period = Int(periodText)!
        guard (1...days).contains(day), (1...periods).contains(period) else { return nil }
        return (day - 1) * periods + period
    }

    func dayOf(_ slot: Int) -> Int {
        (slot - 1) / periods + 1
    }

    func name(_ slot: Int) -> String {
        "D\(dayOf(slot))P\((slot - 1) % periods + 1)"
    }

    func length(_ slot: Int) -> Int {
        lengths[(slot - 1) % periods]
    }

    func relation(_ first: Int, _ second: Int) -> Int? {
        let low = min(first, second)
        let high = max(first, second)
        if dayOf(low) == dayOf(high) {
            if high - low == 1 { return 0 }
            if high - low >= 2 { return 1 }
        } else if high - low == 1 {
            return 2
        }
        return nil
    }
}

struct Breakdown {
    let counts: [Int]
    let late: Int
    let total: Int

    init(_ counts: [Int], _ late: Int, _ weights: [Int]) {
        self.counts = counts
        self.late = late
        total = zip(counts, weights).reduce(weights[3] * late) { $0 + $1.0 * $1.1 }
    }

    var text: String {
        "back_to_back \(counts[0]) same_day \(counts[1]) overnight \(counts[2]) front_load \(late) penalty \(total)"
    }
}

struct AttemptRecord {
    let courses: Int
    let deadEnds: Int
    let failed: Int?
}

struct Choice {
    let course: Int
    let slot: Int
    let saturation: Int
}

struct Insertion {
    let course: Int
    let slot: Int
    let increase: Int
}

struct PenaltyPair {
    let first: Int
    let second: Int
    let relation: Int
    let shared: Int
}

struct StudentPair {
    let relation: Int
    let lowSlot: Int
    let lowCourse: Int
    let highSlot: Int
    let highCourse: Int
}

enum Judgement {
    case fixed
    case invalid
    case rooms
    case worse
    case applied(Assignment, Int)
}

final class Scheduler {
    let courses: [Course]
    let indices: [String: Int]
    let studentCourses: StudentCourses
    let rooms: [Room]
    var calendar: ExamCalendar
    var errors: [String]
    let largestRoom: Int
    let empty: [Int]
    let oversized: [Int]
    let schedulable: [Int]
    let graph: ConflictGraph
    let edges: [Edge]
    let frontLoad: [Int]
    var openSlots: [Int] = []
    var fixedSlots: Set<Int> = []
    var assignment: Assignment
    var penalty = 0
    var attempts: [AttemptRecord] = []
    var assignmentOrder: [Choice] = []
    var excluded: [Int] = []
    var insertions: [Insertion] = []
    var reasons: [Int: [String]] = [:]
    var initial: Breakdown?
    var exchanged: Breakdown?
    var exchangeLog: [String] = []
    var swapLog: [String] = []
    var placements: [Placement?]
    var slotPlacements: [[Placement]]

    init(_ courses: [Course], _ students: StudentCourses, _ rooms: [Room], _ calendar: ExamCalendar, _ errors: [String]) {
        let largest = rooms.map(\.capacity).max()!
        let possible = courses.indices.filter { courses[$0].size > 0 && courses[$0].size <= largest }
        let conflicts = ConflictGraph(courses, students)
        self.courses = courses
        indices = Dictionary(uniqueKeysWithValues: courses.enumerated().map { ($0.element.id, $0.offset) })
        studentCourses = students
        self.rooms = rooms
        self.calendar = calendar
        self.errors = errors
        largestRoom = largest
        empty = courses.indices.filter { courses[$0].size == 0 }
        oversized = courses.indices.filter { courses[$0].size > largest }
        schedulable = possible
        graph = conflicts
        edges = conflicts.edges()
        frontLoad = Array(packingOrder(courses, possible).prefix(calendar.frontCount))
        assignment = Array(repeating: nil, count: courses.count)
        placements = Array(repeating: nil, count: courses.count)
        slotPlacements = Array(repeating: [], count: calendar.slotCount + 1)
    }

    func bySize(_ group: [Int]) -> [Int] {
        packingOrder(courses, group)
    }

    func byDegree(_ group: [Int]) -> [Int] {
        group.sorted { graph.degree($0) == graph.degree($1) ? $0 < $1 : graph.degree($0) > graph.degree($1) }
    }

    func blockedStudents(_ course: Int, _ slot: Int) -> [String] {
        courses[course].students.filter { calendar.unavailable[$0]?.contains(slot) == true }
    }

    func suitable(_ course: Int, _ slot: Int) -> Bool {
        calendar.length(slot) >= courses[course].duration && blockedStudents(course, slot).isEmpty
    }

    func packs(_ group: [Int]) -> Bool {
        pack(rooms, courses, group) != nil
    }

    func outside(_ day: String, _ period: String) -> String {
        "slot \(day) \(period) outside calendar"
    }

    func validateCalendar(_ lines: [String]) {
        for (index, line) in lines.enumerated().dropFirst(6) {
            let tokens = line.split(separator: " ").map(String.init)
            let fields = Array(tokens.dropFirst())
            let message: String?
            switch tokens[0] {
            case "closed": message = acceptClosed(fields)
            case "unavailable": message = acceptUnavailable(fields)
            case "fixed": message = acceptFixed(fields)
            case "after": message = acceptAfter(fields)
            default: preconditionFailure()
            }
            if let message { errors.append("calendar.txt line \(index + 1): \(message)") }
        }
        openSlots = calendar.slots.filter { !calendar.closed.contains($0) }
        fixedSlots = Set(calendar.fixed.compactMap { $0 })
    }

    func acceptClosed(_ fields: [String]) -> String? {
        guard let slot = calendar.slotAt(fields[0], fields[1]) else { return outside(fields[0], fields[1]) }
        if !calendar.closed.insert(slot).inserted { return "duplicate closed \(calendar.name(slot))" }
        return nil
    }

    func acceptUnavailable(_ fields: [String]) -> String? {
        let student = fields[0]
        guard studentCourses[student] != nil else { return "unknown student \(student)" }
        guard let slot = calendar.slotAt(fields[1], fields[2]) else { return outside(fields[1], fields[2]) }
        if !calendar.unavailable[student, default: []].insert(slot).inserted {
            return "duplicate unavailable \(student) \(calendar.name(slot))"
        }
        return nil
    }

    func acceptFixed(_ fields: [String]) -> String? {
        let id = fields[0]
        guard let course = indices[id] else { return "unknown course \(id)" }
        guard schedulable.contains(course) else { return "course \(id) not schedulable" }
        guard let slot = calendar.slotAt(fields[1], fields[2]) else { return outside(fields[1], fields[2]) }
        let name = calendar.name(slot)
        if calendar.closed.contains(slot) { return "slot \(name) closed" }
        if !suitable(course, slot) { return "slot \(name) unsuitable for \(id)" }
        if calendar.fixed[course] != nil { return "duplicate fixed \(id)" }
        var group = coursesAt(calendar.fixed, slot)
        if let other = group.first(where: { graph.neighbours(course)[$0] != nil }) {
            return "conflict \(id) \(courses[other].id)"
        }
        group.append(course)
        if !packs(group) { return "rooms full \(name)" }
        calendar.fixed[course] = slot
        return nil
    }

    func acceptAfter(_ fields: [String]) -> String? {
        for id in fields where indices[id] == nil { return "unknown course \(id)" }
        let later = indices[fields[0]]!
        let earlier = indices[fields[1]]!
        for course in [later, earlier] where !schedulable.contains(course) {
            return "course \(courses[course].id) not schedulable"
        }
        let pair = "\(fields[0]) \(fields[1])"
        if later == earlier { return "bad order \(pair)" }
        if calendar.orders.contains(where: { $0.later == later && $0.earlier == earlier }) { return "duplicate order \(pair)" }
        if reachable(calendar.arrows, earlier, later) { return "cycle \(pair)" }
        if let first = calendar.fixed[later], let second = calendar.fixed[earlier], first <= second {
            return "fixed order \(pair)"
        }
        calendar.orders.append((later, earlier))
        calendar.arrows[later].append(earlier)
        return nil
    }

    func coursesAt(_ current: Assignment, _ slot: Int) -> [Int] {
        courses.indices.filter { current[$0] == slot }
    }

    func orderConflicts(_ course: Int, _ slot: Int, _ current: Assignment) -> [Int] {
        var conflicts: [Int] = []
        for (later, earlier) in calendar.orders {
            if later == course, let other = current[earlier], slot <= other {
                conflicts.append(earlier)
            } else if earlier == course, let other = current[later], slot >= other {
                conflicts.append(later)
            }
        }
        return conflicts
    }

    func ordersSatisfied(_ current: Assignment) -> Bool {
        calendar.orders.allSatisfy { later, earlier in
            guard let first = current[later], let second = current[earlier] else { return true }
            return first > second
        }
    }

    func candidateSlots(_ course: Int, _ current: Assignment) -> [Int] {
        openSlots.filter { slot in
            if !suitable(course, slot) { return false }
            if graph.neighbours(course).keys.contains(where: { current[$0] == slot }) { return false }
            if !orderConflicts(course, slot, current).isEmpty { return false }
            return packs(coursesAt(current, slot) + [course])
        }
    }

    func buildTimetable() {
        while true {
            let pending = schedulable.filter { calendar.fixed[$0] == nil && !excluded.contains($0) }
            var current = calendar.fixed
            let attempt = Attempt(pending, graph, calendar.limit) { course, assigned in
                self.candidateSlots(course, assigned)
            }
            let success = attempt.search(&current)
            attempts.append(AttemptRecord(courses: pending.count, deadEnds: attempt.deadEnds,
                failed: success ? nil : attempt.deadEndCourse))
            if success {
                assignmentOrder = attempt.chosen.map {
                    Choice(course: $0.course, slot: current[$0.course]!, saturation: $0.saturation)
                }
                assignment = current
                break
            }
            excluded.append(attempt.deadEndCourse!)
        }
    }

    func penaltyPairs(_ current: Assignment) -> [PenaltyPair] {
        edges.compactMap { edge in
            guard let first = current[edge.first], let second = current[edge.second],
                let relation = calendar.relation(first, second) else { return nil }
            return PenaltyPair(first: edge.first, second: edge.second, relation: relation, shared: edge.shared)
        }
    }

    func lateCourses(_ current: Assignment) -> [Int] {
        frontLoad.filter { course in
            guard let slot = current[course] else { return false }
            return slot > calendar.deadline
        }
    }

    func breakdown(_ current: Assignment) -> Breakdown {
        var counts = [0, 0, 0]
        for pair in penaltyPairs(current) { counts[pair.relation] += pair.shared }
        return Breakdown(counts, lateCourses(current).count, calendar.weights)
    }

    func contributions() -> [Int] {
        var result = Array(repeating: 0, count: courses.count)
        for pair in penaltyPairs(assignment) {
            let value = calendar.weights[pair.relation] * pair.shared
            result[pair.first] += value
            result[pair.second] += value
        }
        for course in lateCourses(assignment) { result[course] += calendar.weights[3] }
        return result
    }

    func blockingReason(_ course: Int, _ slot: Int) -> String {
        if calendar.closed.contains(slot) { return "closed" }
        if calendar.length(slot) < courses[course].duration { return "too_short" }
        if let student = blockedStudents(course, slot).first { return "unavailable \(student)" }
        let clashes = graph.neighbours(course).filter { assignment[$0.key] == slot }.sorted {
            $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value
        }
        if let clash = clashes.first { return "conflict \(courses[clash.key].id) shared \(clash.value)" }
        if let other = orderConflicts(course, slot, assignment).min() { return "order \(courses[other].id)" }
        return "rooms"
    }

    func insertExcluded() {
        for course in excluded.sorted() {
            let slots = candidateSlots(course, assignment)
            if slots.isEmpty {
                reasons[course] = calendar.slots.map { blockingReason(course, $0) }
                continue
            }
            let before = breakdown(assignment).total
            var bestSlot = slots[0]
            var bestTotal = Int.max
            for slot in slots {
                var trial = assignment
                trial[course] = slot
                let total = breakdown(trial).total
                if total < bestTotal {
                    bestSlot = slot
                    bestTotal = total
                }
            }
            assignment[course] = bestSlot
            insertions.append(Insertion(course: course, slot: bestSlot, increase: bestTotal - before))
        }
        let value = breakdown(assignment)
        initial = value
        penalty = value.total
    }

    func unscheduled() -> [Int] {
        (oversized + excluded.filter { assignment[$0] == nil }).sorted()
    }

    func validTrial(_ trial: Assignment, _ moved: [Int]) -> Bool {
        moved.allSatisfy { suitable($0, trial[$0]!) } && ordersSatisfied(trial)
    }

    func movedCourses(_ trial: Assignment) -> [Int] {
        courses.indices.filter { trial[$0] != assignment[$0] }
    }

    func exchangeTrial(_ first: Int, _ second: Int) -> Judgement {
        if fixedSlots.contains(first) || fixedSlots.contains(second) { return .fixed }
        var trial = assignment
        for course in courses.indices {
            if assignment[course] == first { trial[course] = second }
            else if assignment[course] == second { trial[course] = first }
        }
        if !validTrial(trial, movedCourses(trial)) { return .invalid }
        let total = breakdown(trial).total
        if total >= penalty { return .worse }
        return .applied(trial, total)
    }

    func exchangeSlots() {
        var round = 0
        var serial = 0
        while true {
            round += 1
            var tally = [0, 0, 0, 0]
            var pairs = 0
            var records: [String] = []
            for (index, first) in openSlots.enumerated() {
                for second in openSlots.dropFirst(index + 1) {
                    pairs += 1
                    switch exchangeTrial(first, second) {
                    case .fixed: tally[0] += 1
                    case .invalid: tally[1] += 1
                    case .worse: tally[2] += 1
                    case .rooms: preconditionFailure()
                    case .applied(let trial, let total):
                        tally[3] += 1
                        serial += 1
                        records.append("EXCHANGE \(serial) \(calendar.name(first)) \(calendar.name(second)) penalty \(penalty) -> \(total)")
                        assignment = trial
                        penalty = total
                    }
                }
            }
            exchangeLog.append("ROUND \(round) pairs \(pairs) fixed \(tally[0]) invalid \(tally[1]) worse \(tally[2]) applied \(tally[3])")
            exchangeLog += records
            if tally[3] == 0 { break }
        }
        exchanged = breakdown(assignment)
    }

    func swapTrial(_ course: Int, _ home: Int, _ target: Int) -> Judgement {
        let chain = graph.kempeChain(assignment, course, home, target)
        if chain.contains(where: { calendar.fixed[$0] != nil }) { return .fixed }
        var trial = assignment
        for member in chain { trial[member] = assignment[member] == home ? target : home }
        if !validTrial(trial, chain) { return .invalid }
        if !packs(coursesAt(trial, home)) || !packs(coursesAt(trial, target)) { return .rooms }
        let total = breakdown(trial).total
        if total >= penalty { return .worse }
        return .applied(trial, total)
    }

    func swapChains() {
        var pass = 0
        var serial = 0
        while true {
            pass += 1
            var tally = [0, 0, 0, 0, 0]
            var candidates = 0
            var records: [String] = []
            let movable = courses.indices.filter { assignment[$0] != nil && calendar.fixed[$0] == nil }
            for course in movable {
                let home = assignment[course]!
                targets: for target in openSlots {
                    if home == target { continue }
                    candidates += 1
                    switch swapTrial(course, home, target) {
                    case .fixed: tally[0] += 1
                    case .invalid: tally[1] += 1
                    case .rooms: tally[2] += 1
                    case .worse: tally[3] += 1
                    case .applied(let trial, let total):
                        tally[4] += 1
                        serial += 1
                        let chain = movedCourses(trial)
                        records.append("SWAP \(serial) \(courses[course].id) \(calendar.name(home)) \(calendar.name(target)) chain \(chain.count) penalty \(penalty) -> \(total)")
                        for member in chain {
                            records.append("  MOVE \(courses[member].id) \(calendar.name(assignment[member]!)) -> \(calendar.name(trial[member]!))")
                        }
                        assignment = trial
                        penalty = total
                        break targets
                    }
                }
            }
            swapLog.append("PASS \(pass) candidates \(candidates) fixed \(tally[0]) invalid \(tally[1]) rooms \(tally[2]) worse \(tally[3]) applied \(tally[4])")
            swapLog += records
            if tally[4] == 0 { break }
        }
    }

    func assignRooms() {
        for slot in openSlots {
            let placed = pack(rooms, courses, coursesAt(assignment, slot))!
            slotPlacements[slot] = placed
            for placement in placed { placements[placement.course] = placement }
        }
    }

    func roomGroups(_ slot: Int) -> [(room: Int, placements: [Placement])] {
        rooms.indices.compactMap { room in
            let placed = slotPlacements[slot].filter { $0.room == room }
            return placed.isEmpty ? nil : (room, placed)
        }
    }

    func invigilators(_ slot: Int) -> Int {
        roomGroups(slot).reduce(0) { total, group in
            let seated = group.placements.reduce(0) { $0 + courses[$1.course].size }
            return total + ceilDiv(seated, calendar.ratio)
        }
    }

    func slotLoad(_ slot: Int) -> (exams: Int, students: Int) {
        let group = coursesAt(assignment, slot)
        return (group.count, group.reduce(0) { $0 + courses[$1].size })
    }

    func studentPairs(_ student: String) -> [StudentPair] {
        let assigned = assignedCourses(student)
        var pairs: [StudentPair] = []
        for (index, low) in assigned.enumerated() {
            for high in assigned.dropFirst(index + 1) {
                if let relation = calendar.relation(low.slot, high.slot) {
                    pairs.append(StudentPair(relation: relation, lowSlot: low.slot, lowCourse: low.course,
                        highSlot: high.slot, highCourse: high.course))
                }
            }
        }
        return pairs
    }

    func studentPenalty(_ student: String) -> (counts: [Int], total: Int) {
        var counts = [0, 0, 0]
        for pair in studentPairs(student) { counts[pair.relation] += 1 }
        let total = zip(counts, calendar.weights).reduce(0) { $0 + $1.0 * $1.1 }
        return (counts, total)
    }

    func assignedCourses(_ student: String) -> [(slot: Int, course: Int)] {
        let assigned: [(slot: Int, course: Int)] = studentCourses[student]!.compactMap { course in
            assignment[course].map { ($0, course) }
        }
        return assigned.sorted { $0.slot == $1.slot ? $0.course < $1.course : $0.slot < $1.slot }
    }

    func assignedSlots(_ student: String) -> [Int] {
        assignedCourses(student).map { $0.slot }
    }

    var assignedCount: Int { assignment.compactMap { $0 }.count }

    func timetableLines() -> [String] {
        var lines = ["TIMETABLE days \(calendar.days) periods \(calendar.periods) open \(openSlots.count) courses \(courses.count) scheduled \(assignedCount) unscheduled \(unscheduled().count) empty \(empty.count)"]
        let header = (1...calendar.periods).map { "P\($0)" } + ["TOTAL"]
        lines.append(fixedWidthLine("DAY", header, 4, 10))
        for day in 1...calendar.days {
            var cells: [String] = []
            var dayExams = 0
            var dayStudents = 0
            for period in 1...calendar.periods {
                let slot = (day - 1) * calendar.periods + period
                if calendar.closed.contains(slot) {
                    cells.append("closed")
                } else {
                    let load = slotLoad(slot)
                    cells.append("\(load.exams)/\(load.students)")
                    dayExams += load.exams
                    dayStudents += load.students
                }
            }
            cells.append("\(dayExams)/\(dayStudents)")
            lines.append(fixedWidthLine("D\(day)", cells, 4, 10))
        }
        for slot in calendar.slots {
            let prefix = "SLOT \(slot) \(calendar.name(slot)) minutes \(calendar.length(slot))"
            if calendar.closed.contains(slot) {
                lines.append(prefix + " closed")
                continue
            }
            let load = slotLoad(slot)
            let groups = roomGroups(slot)
            let seats = groups.reduce(0) { $0 + rooms[$1.room].capacity }
            lines.append("\(prefix) exams \(load.exams) students \(load.students) rooms \(groups.count) seats \(seats) invigilators \(invigilators(slot))")
            for placement in slotPlacements[slot] {
                let course = courses[placement.course]
                let marker = calendar.fixed[placement.course] == nil ? "" : " fixed"
                lines.append("  \(course.id) \(course.duration)min students \(course.size) room \(rooms[placement.room].id) seats \(placement.firstSeat)-\(placement.lastSeat)\(marker) \(course.name)")
            }
        }
        for (roomIndex, room) in rooms.enumerated() {
            var slotsUsed = 0
            var exams = 0
            var seated = 0
            for slot in openSlots {
                let placed = slotPlacements[slot].filter { $0.room == roomIndex }
                if !placed.isEmpty {
                    slotsUsed += 1
                    exams += placed.count
                    seated += placed.reduce(0) { $0 + courses[$1.course].size }
                }
            }
            let utilization = roundedPercent(seated, room.capacity * openSlots.count)
            lines.append("ROOM \(room.id) capacity \(room.capacity) slots \(slotsUsed) exams \(exams) seated \(seated) utilization \(utilization)")
        }
        let total = openSlots.reduce(0) { $0 + invigilators($1) }
        lines.append("INVIGILATORS total \(total) ratio \(calendar.ratio)")
        return lines
    }

    func roomLines() -> [String] {
        var lines = ["slot,room,course,students,first_seat,last_seat"]
        for slot in openSlots {
            for group in roomGroups(slot) {
                for placement in group.placements {
                    let course = courses[placement.course]
                    lines.append("\(calendar.name(slot)),\(rooms[group.room].id),\(course.id),\(course.size),\(placement.firstSeat),\(placement.lastSeat)")
                }
            }
        }
        return lines
    }

    func penaltyLines() -> [String] {
        let weights = calendar.weights
        let final = breakdown(assignment)
        let initial = self.initial!
        var lines = [
            "WEIGHTS back_to_back \(weights[0]) same_day \(weights[1]) overnight \(weights[2]) front_load \(weights[3])",
            "FRONT_LOAD courses \(frontLoad.count) last_slot \(calendar.name(calendar.deadline))",
            "INITIAL \(initial.text)"
        ]
        lines += exchangeLog
        lines.append("EXCHANGED \(exchanged!.text)")
        lines += swapLog
        lines.append("FINAL \(final.text)")
        lines.append("SAVED \(initial.total - final.total)")
        var daily = Array(repeating: [0, 0, 0], count: calendar.days + 1)
        for pair in penaltyPairs(assignment) {
            let day = calendar.dayOf(min(assignment[pair.first]!, assignment[pair.second]!))
            daily[day][pair.relation] += pair.shared
        }
        for day in 1...calendar.days {
            let counts = daily[day]
            lines.append("DAY D\(day) back_to_back \(counts[0]) same_day \(counts[1]) overnight \(counts[2])")
        }
        for course in lateCourses(assignment) {
            lines.append("LATE \(courses[course].id) \(calendar.name(assignment[course]!)) students \(courses[course].size)")
        }
        let contribution = contributions()
        let ranked = courses.indices.filter { assignment[$0] != nil }.sorted {
            contribution[$0] == contribution[$1] ? $0 < $1 : contribution[$0] > contribution[$1]
        }
        for course in ranked.prefix(10) where contribution[course] > 0 {
            lines.append("COURSE \(courses[course].id) \(calendar.name(assignment[course]!)) penalty \(contribution[course])")
        }
        lines += studentStatistics()
        return lines
    }

    func studentStatistics() -> [String] {
        var histogram: [Int: Int] = [:]
        var gaps: [Int: Int] = [:]
        var dayLoads: [Int: Int] = [:]
        var ranking: [(penalty: Int, student: String, counts: [Int])] = []
        for student in studentCourses.keys.sorted(by: asciiLess) {
            let value = studentPenalty(student)
            histogram[value.total, default: 0] += 1
            ranking.append((value.total, student, value.counts))
            let slots = assignedSlots(student)
            for (low, high) in zip(slots, slots.dropFirst()) { gaps[high - low, default: 0] += 1 }
            if !slots.isEmpty {
                var perDay: [Int: Int] = [:]
                for slot in slots { perDay[calendar.dayOf(slot), default: 0] += 1 }
                dayLoads[perDay.values.max()!, default: 0] += 1
            }
        }
        var lines = histogram.keys.sorted().map { "HISTOGRAM \($0) \(histogram[$0]!)" }
        lines += gaps.keys.sorted().map { "GAP \($0) \(gaps[$0]!)" }
        lines += dayLoads.keys.sorted().map { "DAYLOAD \($0) \(dayLoads[$0]!)" }
        ranking.sort {
            $0.penalty == $1.penalty ? asciiLess($0.student, $1.student) : $0.penalty > $1.penalty
        }
        for value in ranking.prefix(5) where value.penalty > 0 {
            lines.append("WORST \(value.student) penalty \(value.penalty) back_to_back \(value.counts[0]) same_day \(value.counts[1]) overnight \(value.counts[2])")
        }
        return lines
    }

    func scheduleLines(_ queries: [String]) -> [String] {
        var lines: [String] = []
        for student in queries {
            guard let enrolled = studentCourses[student] else {
                lines.append("STUDENT \(student) not found")
                continue
            }
            let assigned = assignedCourses(student)
            let value = studentPenalty(student)
            lines.append("STUDENT \(student) exams \(enrolled.count) scheduled \(assigned.count) penalty \(value.total)")
            for (slot, index) in assigned {
                let placement = placements[index]!
                let course = courses[index]
                let seat = placement.firstSeat + course.students.firstIndex(of: student)!
                lines.append("  \(calendar.name(slot)) \(course.id) room \(rooms[placement.room].id) seat \(seat) \(course.name)")
            }
            for course in enrolled where assignment[course] == nil {
                lines.append("  UNSCHEDULED \(courses[course].id) \(courses[course].name)")
            }
            for pair in studentPairs(student) {
                lines.append("  \(relationNames[pair.relation]) \(calendar.name(pair.lowSlot)) \(courses[pair.lowCourse].id) \(calendar.name(pair.highSlot)) \(courses[pair.highCourse].id)")
            }
            for slot in (calendar.unavailable[student] ?? []).sorted() {
                lines.append("  UNAVAILABLE \(calendar.name(slot))")
            }
        }
        return lines
    }

    func statusLines() -> [String] {
        let contribution = contributions()
        var lines = ["course,status,slot,students,minutes,degree,penalty"]
        for (index, course) in courses.enumerated() {
            let status: String
            if calendar.fixed[index] != nil { status = "fixed" }
            else if assignment[index] != nil { status = "scheduled" }
            else if oversized.contains(index) { status = "too_large" }
            else if empty.contains(index) { status = "empty" }
            else { status = "no_slot" }
            let slot = assignment[index].map { calendar.name($0) } ?? "-"
            lines.append("\(course.id),\(status),\(slot),\(course.size),\(course.duration),\(graph.degree(index)),\(contribution[index])")
        }
        return lines
    }

    func graphLines() -> [String] {
        let vertexCount = graph.vertices.count
        let edgeCount = edges.count
        let shared = edges.reduce(0) { $0 + $1.shared }
        let density = vertexCount >= 2 ? 2000 * edgeCount / (vertexCount * (vertexCount - 1)) : 0
        var lines = ["GRAPH courses \(vertexCount) edges \(edgeCount) shared \(shared) density \(density)"]
        for course in byDegree(graph.vertices).prefix(5) {
            lines.append("DEGREE \(courses[course].id) neighbours \(graph.degree(course)) shared \(graph.sharedTotal(course)) students \(courses[course].size)")
        }
        let components = graph.components()
        lines.append("COMPONENTS \(components.count)")
        for (index, component) in components.enumerated() {
            lines.append("COMPONENT \(index + 1) size \(component.count) first \(courses[component[0]].id)")
        }
        let clique = graph.greedyClique(schedulable)
        lines.append((["CLIQUE", "size", String(clique.count)] + clique.map { courses[$0].id }).joined(separator: " "))
        return lines
    }

    func capacityLines() -> [String] {
        let loads = studentCourses.values.map { $0.count }
        let most = loads.max()!
        let demand = schedulable.reduce(0) { $0 + courses[$1].size }
        let capacity = rooms.reduce(0) { $0 + $1.capacity }
        let degreeSlots = greedyNumbering(byDegree(schedulable), graph, courses.count)
        let sizeSlots = greedyNumbering(bySize(schedulable), graph, courses.count)
        var lines = [
            "LOAD max_exams \(most) students \(loads.filter { $0 == most }.count)",
            "SEATS demand \(demand) capacity \(capacity) min_slots \(ceilDiv(demand, capacity))",
            "HEURISTIC largest_degree slots \(degreeSlots)",
            "HEURISTIC largest_enrolment slots \(sizeSlots)"
        ]
        let table = Array(bySize(graph.vertices).prefix(8))
        lines.append(fixedWidthLine("MATRIX", table.map { courses[$0].id }, 9, 9))
        for row in table {
            let neighbours = graph.neighbours(row)
            let cells = table.map { column in row == column ? "-" : String(neighbours[column, default: 0]) }
            lines.append(fixedWidthLine(courses[row].id, cells, 9, 9))
        }
        return lines
    }

    func reportLines() -> [String] {
        let enrolments = studentCourses.values.reduce(0) { $0 + $1.count }
        var lines = ["INPUT courses \(courses.count) enrolments \(enrolments) rooms \(rooms.count) students \(studentCourses.count) errors \(errors.count)"]
        lines += errors.map { "ERROR \($0)" }
        lines += graphLines()
        lines += capacityLines()
        lines += empty.map { "EMPTY \(courses[$0].id)" }
        for course in oversized {
            lines.append("TOO_LARGE \(courses[course].id) students \(courses[course].size) largest_room \(largestRoom)")
        }
        lines += calendar.closed.sorted().map { "CLOSED \(calendar.name($0))" }
        for course in courses.indices {
            if let slot = calendar.fixed[course] { lines.append("FIXED \(courses[course].id) \(calendar.name(slot))") }
        }
        for (later, earlier) in calendar.orders {
            lines.append("AFTER \(courses[later].id) \(courses[earlier].id)")
        }
        for (index, attempt) in attempts.enumerated() {
            let result = attempt.failed.map { "failed \(courses[$0].id)" } ?? "success"
            lines.append("ATTEMPT \(index + 1) courses \(attempt.courses) backtracks \(attempt.deadEnds) \(result)")
        }
        for (index, choice) in assignmentOrder.enumerated() {
            lines.append("ORDER \(index + 1) \(courses[choice.course].id) \(calendar.name(choice.slot)) saturation \(choice.saturation) degree \(graph.degree(choice.course))")
        }
        for insertion in insertions {
            lines.append("INSERTED \(courses[insertion.course].id) \(calendar.name(insertion.slot)) penalty \(insertion.increase)")
        }
        let missing = unscheduled()
        for course in missing {
            let reason = oversized.contains(course) ? "too_large" : "no_slot"
            lines.append("UNSCHEDULED \(courses[course].id) reason \(reason) students \(courses[course].size)")
            for (index, reason) in (reasons[course] ?? []).enumerated() {
                lines.append("  \(calendar.name(index + 1)) \(reason)")
            }
        }
        let slotsUsed = Set(assignment.compactMap { $0 }).count
        lines.append("SUMMARY scheduled \(assignedCount) unscheduled \(missing.count) slots_used \(slotsUsed) penalty \(penalty)")
        return lines
    }
}

func ceilDiv(_ numerator: Int, _ denominator: Int) -> Int {
    (numerator + denominator - 1) / denominator
}

func readLines(_ name: String) throws -> [String] {
    try String(contentsOfFile: "input/\(name)", encoding: .utf8).split(separator: "\n").map(String.init)
}

func main() throws {
    var errors: [String] = []
    var courses = try loadCourses("input/courses.csv", &errors)
    let students = try loadEnrolments("input/enrolments.csv", &courses, &errors)
    let rooms = try loadRooms("input/rooms.csv", &errors)
    let calendarLines = try readLines("calendar.txt")
    let calendar = ExamCalendar(calendarLines, courses.count)
    let scheduler = Scheduler(courses, students, rooms, calendar, errors)
    scheduler.validateCalendar(calendarLines)
    scheduler.buildTimetable()
    scheduler.insertExcluded()
    scheduler.exchangeSlots()
    scheduler.swapChains()
    scheduler.assignRooms()
    let queries = try readLines("queries.txt")
    try writeFiles("output", [
        ("timetable.txt", scheduler.timetableLines()),
        ("rooms.csv", scheduler.roomLines()),
        ("penalties.txt", scheduler.penaltyLines()),
        ("student_schedules.txt", scheduler.scheduleLines(queries)),
        ("course_status.csv", scheduler.statusLines()),
        ("report.txt", scheduler.reportLines())
    ])
}

try main()
