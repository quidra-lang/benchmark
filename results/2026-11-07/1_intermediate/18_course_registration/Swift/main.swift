import Foundation

private let days = ["MO", "TU", "WE", "TH", "FR", "SA", "SU"]
private let gradePoints = ["A": 4, "B": 3, "C": 2, "D": 1, "F": 0]

private struct CommandError: Error {
    let message: String
}

private func fail(_ message: String) throws -> Never {
    throw CommandError(message: message)
}

private func clock(_ minutes: Int) -> String {
    String(format: "%02d:%02d", minutes / 60, minutes % 60)
}

private func rate(_ count: Int, _ capacity: Int) -> String {
    capacity == 0 ? "n/a" : "\(count * 100 / capacity)%"
}

private func courseWord(_ word: String) -> Bool {
    let characters = Array(word.utf8)
    guard (5...7).contains(characters.count) else { return false }
    let prefix = characters.count - 3
    return (2...4).contains(prefix)
        && characters[..<prefix].allSatisfy { (65...90).contains(Int($0)) }
        && characters[prefix...].allSatisfy { (48...57).contains(Int($0)) }
}

private func yearWord(_ word: String) -> Bool {
    let characters = Array(word.utf8)
    return characters.count == 2 && characters[0] == 89 && (49...57).contains(Int(characters[1]))
}

private indirect enum Expression {
    case unconditional
    case word(String)
    case and([Expression])
    case or([Expression])

    var canonical: String {
        switch self {
        case .unconditional:
            return "-"
        case .word(let value):
            return value
        case .and(let children):
            return children.map { child in
                if case .or = child {
                    return "(\(child.canonical))"
                }
                return child.canonical
            }.joined(separator: "&")
        case .or(let children):
            return children.map(\.canonical).joined(separator: "|")
        }
    }

    var references: Set<String> {
        switch self {
        case .unconditional:
            return []
        case .word(let value):
            return yearWord(value) ? [] : [value]
        case .and(let children), .or(let children):
            return children.reduce(into: Set<String>()) { $0.formUnion($1.references) }
        }
    }

    func evaluates(_ student: Student) -> Bool {
        switch self {
        case .unconditional:
            return true
        case .word(let value):
            if yearWord(value) {
                return student.year >= Int(String(value.suffix(1)))!
            }
            return student.passed[value] != nil
        case .and(let children):
            return children.allSatisfy { $0.evaluates(student) }
        case .or(let children):
            return children.contains { $0.evaluates(student) }
        }
    }

    static func combined(_ conjunction: Bool, _ children: [Expression]) -> Expression {
        var flattened: [Expression] = []
        for child in children {
            switch child {
            case .and(let values) where conjunction:
                flattened.append(contentsOf: values)
            case .or(let values) where !conjunction:
                flattened.append(contentsOf: values)
            default:
                flattened.append(child)
            }
        }
        if flattened.count == 1 { return flattened[0] }
        return conjunction ? .and(flattened) : .or(flattened)
    }
}

private final class PrerequisiteParser {
    private var tokens: [String] = []
    private var position = 0

    init(_ source: String) throws {
        let bytes = Array(source.utf8)
        var index = 0
        while index < bytes.count {
            let character = bytes[index]
            if character == 38 || character == 124 || character == 40 || character == 41 {
                tokens.append(String(UnicodeScalar(character)))
                index += 1
                continue
            }
            let start = index
            while index < bytes.count
                && ((48...57).contains(Int(bytes[index])) || (65...90).contains(Int(bytes[index]))) {
                index += 1
            }
            guard index > start else { try fail("parse") }
            let word = String(decoding: bytes[start..<index], as: UTF8.self)
            guard courseWord(word) || yearWord(word) else { try fail("parse") }
            tokens.append(word)
        }
    }

    private var next: String? {
        position < tokens.count ? tokens[position] : nil
    }

    private func factor() throws -> Expression {
        guard let token = next, !["&", "|", ")"].contains(token) else {
            try fail("parse")
        }
        position += 1
        if token == "(" {
            let value = try expression()
            guard next == ")" else { try fail("parse") }
            position += 1
            return value
        }
        return .word(token)
    }

    private func term() throws -> Expression {
        var children = [try factor()]
        while next == "&" {
            position += 1
            children.append(try factor())
        }
        return .combined(true, children)
    }

    private func expression() throws -> Expression {
        var children = [try term()]
        while next == "|" {
            position += 1
            children.append(try term())
        }
        return .combined(false, children)
    }

    func parse() throws -> Expression {
        let result = try expression()
        guard position == tokens.count else { try fail("parse") }
        return result
    }
}

private func prerequisite(_ code: String, _ source: String) throws -> Expression {
    if source == "-" { return .unconditional }
    let result: Expression
    do {
        result = try PrerequisiteParser(source).parse()
    } catch {
        try fail("invalid prereq \(code)")
    }
    guard !result.references.contains(code) else { try fail("self prereq \(code)") }
    return result
}

private struct Slot {
    let day: Int
    let start: Int
    let end: Int
    let original: String

    init(_ source: String) throws {
        let bytes = Array(source.utf8)
        guard bytes.count == 11 else { try fail("invalid slot \(source)") }
        let dayText = String(decoding: bytes[0...1], as: UTF8.self)
        guard let day = days.firstIndex(of: dayText) else { try fail("invalid slot \(source)") }
        let startHour = Int(String(decoding: bytes[2...3], as: UTF8.self))!
        let startMinute = Int(String(decoding: bytes[4...5], as: UTF8.self))!
        let endHour = Int(String(decoding: bytes[7...8], as: UTF8.self))!
        let endMinute = Int(String(decoding: bytes[9...10], as: UTF8.self))!
        guard startHour <= 23, endHour <= 23, startMinute <= 59, endMinute <= 59 else {
            try fail("invalid slot \(source)")
        }
        let start = startHour * 60 + startMinute
        let end = endHour * 60 + endMinute
        guard start < end else { try fail("invalid slot \(source)") }
        self.day = day
        self.start = start
        self.end = end
        self.original = source
    }

    func overlaps(_ other: Slot) -> Bool {
        day == other.day && start < other.end && other.start < end
    }

    var display: String {
        "\(clock(start))-\(clock(end))"
    }
}

private final class Course {
    let code: String
    let credits: Int
    var capacity: Int
    let slots: [Slot]
    var prerequisite: Expression
    var isOpen = true
    var enrolled: Set<String> = []
    var waitlist: [String] = []
    var conflicts: Set<String> = []

    init(_ code: String, _ credits: Int, _ capacity: Int,
         _ slots: [Slot], _ prerequisite: Expression) {
        self.code = code
        self.credits = credits
        self.capacity = capacity
        self.slots = slots
        self.prerequisite = prerequisite
    }

    var status: String { isOpen ? "open" : "closed" }
    var weekly: Int { slots.reduce(0) { $0 + $1.end - $1.start } }
    var department: String { String(code.dropLast(3)) }
}

private final class Student {
    let identifier: String
    let year: Int
    var limit: Int
    let records: [String: (grade: String, credits: Int)]
    let passed: [String: String]
    var enrolled: Set<String> = []
    var waiting: Set<String> = []
    var credits = 0
    var history: [(number: Int, event: String)] = []

    init(_ identifier: String, _ year: Int, _ limit: Int,
         _ records: [String: (grade: String, credits: Int)]) {
        self.identifier = identifier
        self.year = year
        self.limit = limit
        self.records = records
        var passed: [String: String] = [:]
        for (code, record) in records where ["A", "B", "C"].contains(record.grade) {
            passed[code] = record.grade
        }
        self.passed = passed
    }

    var earned: Int {
        records.values.reduce(0) { $0 + ($1.grade == "F" ? 0 : $1.credits) }
    }

    var gpa: String {
        guard !records.isEmpty else { return "n/a" }
        let weighted = records.values.reduce(0) { $0 + gradePoints[$1.grade]! * $1.credits }
        let credits = records.values.reduce(0) { $0 + $1.credits }
        let value = (200 * weighted + credits) / (2 * credits)
        return "\(value / 100).\(String(format: "%02d", value % 100))"
    }
}

private struct Decision {
    let kind: String
    let extra: [String]

    var text: String {
        ([kind] + extra).joined(separator: " ")
    }
}

private final class Registrar {
    private var courses: [String: Course] = [:]
    private var students: [String: Student] = [:]
    private var commandNumber = 0
    private(set) var output: [String] = []

    private func emit(_ line: String, indented: Bool = false) {
        output.append((indented ? "  " : "") + line)
    }

    private func student(_ identifier: String) throws -> Student {
        guard let value = students[identifier] else {
            try fail("unknown student \(identifier)")
        }
        return value
    }

    private func course(_ code: String) throws -> Course {
        guard let value = courses[code] else {
            try fail("unknown course \(code)")
        }
        return value
    }

    private func record(_ student: Student, _ event: String) {
        student.history.append((commandNumber, event))
    }

    private func conflict(_ student: Student, _ course: Course, excluding: String? = nil) -> String? {
        student.enrolled.intersection(course.conflicts)
            .filter { $0 != excluding }.sorted().first
    }

    private func eligibility(_ student: Student, _ course: Course,
                             excluding: String? = nil) -> Decision? {
        let code = course.code
        if !course.isOpen { return Decision(kind: "course closed", extra: []) }
        if student.enrolled.contains(code) { return Decision(kind: "already enrolled", extra: []) }
        if student.waiting.contains(code) { return Decision(kind: "already waitlisted", extra: []) }
        if let grade = student.passed[code] {
            return Decision(kind: "already completed", extra: [grade])
        }
        if !course.prerequisite.evaluates(student) {
            return Decision(kind: "prereq not met", extra: [])
        }
        if let conflict = conflict(student, course, excluding: excluding) {
            return Decision(kind: "time conflict", extra: [conflict])
        }
        let excludedCredits = excluding.flatMap { courses[$0]?.credits } ?? 0
        let total = student.credits - excludedCredits + course.credits
        if total > student.limit {
            return Decision(kind: "credit limit", extra: [String(total), String(student.limit)])
        }
        return nil
    }

    private func waitPosition(_ student: Student, _ course: Course) -> Int {
        1 + course.waitlist.filter { students[$0]!.year >= student.year }.count
    }

    private func request(_ student: Student, _ course: Course) -> Decision {
        if let denied = eligibility(student, course) { return denied }
        if course.enrolled.count < course.capacity {
            return Decision(kind: "enroll", extra: [])
        }
        if student.waiting.count >= 3 {
            return Decision(kind: "waitlist limit", extra: [])
        }
        return Decision(kind: "waitlist", extra: [String(waitPosition(student, course))])
    }

    private func failRequest(_ decision: Decision, _ student: Student,
                             _ course: Course) throws -> Never {
        try fail((["\(decision.kind) \(student.identifier) \(course.code)"] + decision.extra)
            .joined(separator: " "))
    }

    private func enroll(_ student: Student, _ course: Course) {
        course.enrolled.insert(student.identifier)
        student.enrolled.insert(course.code)
        student.credits += course.credits
    }

    private func withdraw(_ student: Student, _ course: Course) {
        course.enrolled.remove(student.identifier)
        student.enrolled.remove(course.code)
        student.credits -= course.credits
    }

    private func unlist(_ student: Student, _ course: Course) {
        course.waitlist.removeAll { $0 == student.identifier }
        student.waiting.remove(course.code)
    }

    private func promotion() {
        for code in courses.keys.sorted() {
            guard let course = courses[code], course.isOpen else { continue }
            for identifier in course.waitlist {
                if course.enrolled.count >= course.capacity { break }
                let student = students[identifier]!
                if conflict(student, course) != nil
                    || student.credits + course.credits > student.limit { continue }
                unlist(student, course)
                enroll(student, course)
                record(student, "promote \(code)")
                emit("PROMOTE \(identifier) \(code) enrolled \(course.enrolled.count)/\(course.capacity) credits \(student.credits)/\(student.limit)", indented: true)
            }
        }
    }

    private func cmdCourse(_ a: [String]) throws {
        let code = a[0]
        if courses[code] != nil { try fail("duplicate course \(code)") }
        let slots = try a[3] == "-" ? [] : a[3].split(separator: ",").map { try Slot(String($0)) }
        for i in slots.indices {
            for j in (i + 1)..<slots.count where slots[i].overlaps(slots[j]) {
                try fail("overlapping slots \(slots[i].original) \(slots[j].original)")
            }
        }
        let expression = try prerequisite(code, a[4])
        let course = Course(code, Int(a[1])!, Int(a[2])!, slots, expression)
        for other in courses.values {
            if slots.contains(where: { first in other.slots.contains { first.overlaps($0) } }) {
                course.conflicts.insert(other.code)
                other.conflicts.insert(code)
            }
        }
        courses[code] = course
        emit("COURSE \(code) credits \(a[1]) capacity \(a[2]) meetings \(slots.count) weekly \(clock(course.weekly)) prereq \(expression.canonical)")
    }

    private func cmdStudent(_ a: [String]) throws {
        let identifier = a[0]
        if students[identifier] != nil { try fail("duplicate student \(identifier)") }
        var records: [String: (grade: String, credits: Int)] = [:]
        if a[3] != "-" {
            for raw in a[3].split(separator: ",") {
                let pieces = String(raw).split(separator: ":").map(String.init)
                let code = pieces[0], grade = pieces[1]
                if gradePoints[grade] == nil {
                    try fail("invalid grade \(identifier) \(code) \(grade)")
                }
                if records[code] != nil {
                    try fail("duplicate record \(identifier) \(code)")
                }
                records[code] = (grade, Int(pieces[2])!)
            }
        }
        let student = Student(identifier, Int(a[1])!, Int(a[2])!, records)
        students[identifier] = student
        emit("STUDENT \(identifier) year \(a[1]) limit \(a[2]) records \(records.count) earned \(student.earned) gpa \(student.gpa)")
    }

    private func cmdEnroll(_ a: [String]) throws {
        let student = try student(a[0])
        let course = try course(a[1])
        let decision = request(student, course)
        if decision.kind != "enroll" && decision.kind != "waitlist" {
            try failRequest(decision, student, course)
        }
        if decision.kind == "enroll" {
            enroll(student, course)
            record(student, "enroll \(course.code)")
            emit("ENROLL \(student.identifier) \(course.code) enrolled \(course.enrolled.count)/\(course.capacity) credits \(student.credits)/\(student.limit)")
        } else {
            let position = Int(decision.extra[0])!
            course.waitlist.insert(student.identifier, at: position - 1)
            student.waiting.insert(course.code)
            record(student, "waitlist \(course.code) \(position)")
            emit("ENROLL \(student.identifier) \(course.code) waitlist \(position)")
        }
    }

    private func cmdCheck(_ a: [String]) throws {
        let student = try student(a[0])
        let course = try course(a[1])
        emit("CHECK \(a[0]) \(a[1]) \(request(student, course).text)")
    }

    private func cmdOptions(_ a: [String]) throws {
        let student = try student(a[0])
        emit("OPTIONS \(a[0]) courses \(courses.count)")
        for code in courses.keys.sorted() {
            emit("\(code) \(request(student, courses[code]!).text)", indented: true)
        }
    }

    private func cmdDrop(_ a: [String]) throws {
        let student = try student(a[0])
        let course = try course(a[1])
        if student.enrolled.contains(course.code) {
            withdraw(student, course)
            record(student, "drop \(course.code)")
            emit("DROP \(a[0]) \(a[1]) enrolled \(course.enrolled.count)/\(course.capacity) credits \(student.credits)/\(student.limit)")
        } else if student.waiting.contains(course.code) {
            unlist(student, course)
            record(student, "drop \(course.code) waitlist")
            emit("DROP \(a[0]) \(a[1]) waitlist removed")
        } else {
            try fail("not registered \(a[0]) \(a[1])")
        }
        promotion()
    }

    private func cmdSwap(_ a: [String]) throws {
        let student = try student(a[0])
        let source = try course(a[1])
        let destination = try course(a[2])
        if !student.enrolled.contains(source.code) { try fail("not enrolled \(a[0]) \(a[1])") }
        if source.code == destination.code { try fail("same course \(a[1])") }
        if let denied = eligibility(student, destination, excluding: source.code) {
            try failRequest(denied, student, destination)
        }
        if destination.enrolled.count >= destination.capacity { try fail("course full \(a[2])") }
        withdraw(student, source)
        enroll(student, destination)
        record(student, "swap \(a[1]) \(a[2])")
        emit("SWAP \(a[0]) \(a[1]) -> \(a[2]) credits \(student.credits)/\(student.limit)")
        promotion()
    }

    private func cmdClose(_ a: [String]) throws {
        let course = try course(a[0])
        if !course.isOpen { try fail("already closed \(a[0])") }
        course.isOpen = false
        emit("CLOSE \(a[0]) enrolled \(course.enrolled.count)/\(course.capacity) waitlist \(course.waitlist.count)")
    }

    private func cmdOpen(_ a: [String]) throws {
        let course = try course(a[0])
        if course.isOpen { try fail("already open \(a[0])") }
        course.isOpen = true
        emit("OPEN \(a[0]) enrolled \(course.enrolled.count)/\(course.capacity) waitlist \(course.waitlist.count)")
        promotion()
    }

    private func cmdCapacity(_ a: [String]) throws {
        let course = try course(a[0])
        let capacity = Int(a[1])!
        if capacity < course.enrolled.count {
            try fail("capacity below enrollment \(a[0]) \(course.enrolled.count)")
        }
        let previous = course.capacity
        course.capacity = capacity
        emit("CAPACITY \(a[0]) \(previous) -> \(capacity)")
        promotion()
    }

    private func cmdLimit(_ a: [String]) throws {
        let student = try student(a[0])
        let limit = Int(a[1])!
        if limit < student.credits { try fail("limit below enrolled \(a[0]) \(student.credits)") }
        let previous = student.limit
        student.limit = limit
        emit("LIMIT \(a[0]) \(previous) -> \(limit)")
        promotion()
    }

    private func cmdPrereq(_ a: [String]) throws {
        let course = try course(a[0])
        let expression = try prerequisite(course.code, a[1])
        course.prerequisite = expression
        emit("PREREQ \(course.code) \(expression.canonical)")
        for identifier in course.waitlist {
            let student = students[identifier]!
            if !expression.evaluates(student) {
                unlist(student, course)
                record(student, "unlist \(course.code)")
                emit("UNLIST \(identifier) \(course.code)", indented: true)
            }
        }
    }

    private func cmdCancel(_ a: [String]) throws {
        let course = try course(a[0])
        emit("CANCEL \(course.code) enrolled \(course.enrolled.count) waitlist \(course.waitlist.count)")
        for identifier in course.enrolled.sorted() {
            let student = students[identifier]!
            student.enrolled.remove(course.code)
            student.credits -= course.credits
            record(student, "cancel \(course.code)")
        }
        for identifier in course.waitlist {
            let student = students[identifier]!
            student.waiting.remove(course.code)
            record(student, "cancel \(course.code) waitlist")
        }
        for other in course.conflicts {
            courses[other]?.conflicts.remove(course.code)
        }
        courses.removeValue(forKey: course.code)
        promotion()
    }

    private func cmdRoster(_ a: [String]) throws {
        let course = try course(a[0])
        emit("ROSTER \(course.code) \(course.status) enrolled \(course.enrolled.count)/\(course.capacity) waitlist \(course.waitlist.count)")
        for identifier in course.enrolled.sorted() {
            emit("enrolled \(identifier) year \(students[identifier]!.year)", indented: true)
        }
        for (index, identifier) in course.waitlist.enumerated() {
            emit("waitlist \(index + 1) \(identifier) year \(students[identifier]!.year)", indented: true)
        }
    }

    private func studentSlots(_ student: Student, day: Int) -> [(start: Int, end: Int, course: String)] {
        var result: [(start: Int, end: Int, course: String)] = []
        for code in student.enrolled {
            for slot in courses[code]!.slots where slot.day == day {
                result.append((slot.start, slot.end, code))
            }
        }
        result.sort { ($0.start, $0.end, $0.course) < ($1.start, $1.end, $1.course) }
        return result
    }

    private func cmdSchedule(_ a: [String]) throws {
        let student = try student(a[0])
        let weekly = student.enrolled.reduce(0) { $0 + courses[$1]!.weekly }
        emit("SCHEDULE \(a[0]) courses \(student.enrolled.count) credits \(student.credits) weekly \(clock(weekly))")
        for (index, day) in days.enumerated() {
            let slots = studentSlots(student, day: index)
            if !slots.isEmpty {
                let values = slots.map { "\(clock($0.start))-\(clock($0.end)) \($0.course)" }
                emit(([day] + values).joined(separator: " "), indented: true)
            }
        }
        let unplaced = student.enrolled.filter { courses[$0]!.slots.isEmpty }.sorted()
        if !unplaced.isEmpty {
            emit((["TBA"] + unplaced).joined(separator: " "), indented: true)
        }
    }

    private func cmdFree(_ a: [String]) throws {
        let student = try student(a[0])
        guard let day = days.firstIndex(of: a[1]) else { try fail("invalid day \(a[1])") }
        let slots = studentSlots(student, day: day)
        var free: [(Int, Int)] = []
        var cursor = 480
        for slot in slots {
            let start = max(480, slot.start), end = min(1320, slot.end)
            if start < end {
                if cursor < start { free.append((cursor, start)) }
                cursor = max(cursor, end)
            }
        }
        if cursor < 1320 { free.append((cursor, 1320)) }
        let total = free.reduce(0) { $0 + $1.1 - $1.0 }
        let values = free.map { "\(clock($0.0))-\(clock($0.1))" }
        emit((["FREE \(a[0]) \(a[1]) total \(clock(total))"] + values).joined(separator: " "))
    }

    private func cmdInfo(_ a: [String]) throws {
        let course = try course(a[0])
        emit("INFO \(course.code) \(course.status) credits \(course.credits) capacity \(course.capacity) prereq \(course.prerequisite.canonical)")
        let slots = course.slots.sorted { ($0.day, $0.start) < ($1.day, $1.start) }
        if slots.isEmpty {
            emit("meet TBA", indented: true)
        } else {
            for slot in slots {
                emit("meet \(days[slot.day]) \(slot.display)", indented: true)
            }
        }
        let requiredBy = courses.values.filter { $0.prerequisite.references.contains(course.code) }
            .map(\.code).sorted()
        emit((["required by"] + (requiredBy.isEmpty ? ["none"] : requiredBy))
            .joined(separator: " "), indented: true)
    }

    private func cmdAudit(_ a: [String]) throws {
        let student = try student(a[0])
        emit("AUDIT \(a[0]) year \(student.year) limit \(student.limit)")
        for code in student.records.keys.sorted() {
            let value = student.records[code]!
            emit("record \(code) \(value.grade) \(value.credits)", indented: true)
        }
        emit("earned \(student.earned) gpa \(student.gpa)", indented: true)
        for code in student.enrolled.sorted() {
            emit("enrolled \(code) \(courses[code]!.credits)", indented: true)
        }
        emit("credits \(student.credits) remaining \(student.limit - student.credits)", indented: true)
        for code in student.waiting.sorted() {
            let position = courses[code]!.waitlist.firstIndex(of: student.identifier)! + 1
            emit("waitlist \(code) \(position)", indented: true)
        }
    }

    private func cmdHistory(_ a: [String]) throws {
        let student = try student(a[0])
        emit("HISTORY \(a[0]) events \(student.history.count)")
        for event in student.history {
            emit("\(event.number) \(event.event)", indented: true)
        }
    }

    private func cmdStudents() {
        emit("STUDENTS \(students.count)")
        for identifier in students.keys.sorted() {
            let student = students[identifier]!
            emit("\(identifier) year \(student.year) credits \(student.credits)/\(student.limit) courses \(student.enrolled.count) waitlists \(student.waiting.count)", indented: true)
        }
    }

    private func groupCounts(_ courses: [Course]) -> String {
        let enrolled = courses.reduce(0) { $0 + $1.enrolled.count }
        let capacity = courses.reduce(0) { $0 + $1.capacity }
        let waitlisted = courses.reduce(0) { $0 + $1.waitlist.count }
        return "enrolled \(enrolled)/\(capacity) rate \(rate(enrolled, capacity)) waitlisted \(waitlisted)"
    }

    private func cmdReport() {
        emit("REPORT courses \(courses.count) \(groupCounts(Array(courses.values)))")
        var departments: [String: [Course]] = [:]
        for code in courses.keys.sorted() {
            let course = courses[code]!
            emit("\(code) \(course.status) \(course.enrolled.count)/\(course.capacity) \(rate(course.enrolled.count, course.capacity)) waitlist \(course.waitlist.count)", indented: true)
            departments[course.department, default: []].append(course)
        }
        for department in departments.keys.sorted() {
            let group = departments[department]!
            emit("dept \(department) courses \(group.count) \(groupCounts(group))", indented: true)
        }
    }

    func execute(_ line: String) {
        commandNumber += 1
        let parts = line.split(separator: " ").map(String.init)
        guard let command = parts.first else { return }
        let a = Array(parts.dropFirst())
        do {
            switch command {
            case "COURSE": try cmdCourse(a)
            case "STUDENT": try cmdStudent(a)
            case "ENROLL": try cmdEnroll(a)
            case "CHECK": try cmdCheck(a)
            case "OPTIONS": try cmdOptions(a)
            case "DROP": try cmdDrop(a)
            case "SWAP": try cmdSwap(a)
            case "CLOSE": try cmdClose(a)
            case "OPEN": try cmdOpen(a)
            case "CAPACITY": try cmdCapacity(a)
            case "LIMIT": try cmdLimit(a)
            case "PREREQ": try cmdPrereq(a)
            case "CANCEL": try cmdCancel(a)
            case "ROSTER": try cmdRoster(a)
            case "SCHEDULE": try cmdSchedule(a)
            case "FREE": try cmdFree(a)
            case "INFO": try cmdInfo(a)
            case "AUDIT": try cmdAudit(a)
            case "HISTORY": try cmdHistory(a)
            case "STUDENTS": cmdStudents()
            case "REPORT": cmdReport()
            default: break
            }
        } catch let error as CommandError {
            emit("ERROR \(error.message)")
        } catch {
            fatalError("Unexpected error: \(error)")
        }
    }
}

let commandCount = Int(readLine()!)!
let registrar = Registrar()
for _ in 0..<commandCount {
    registrar.execute(readLine()!)
}
print(registrar.output.joined(separator: "\n"))
