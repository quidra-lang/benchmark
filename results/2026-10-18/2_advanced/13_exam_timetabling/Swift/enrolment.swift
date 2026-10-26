import Foundation

struct Course {
    let id: String
    let duration: Int
    let name: String
    var students: [String] = []
    var size: Int { students.count }
}

typealias StudentCourses = [String: [Int]]

struct EnrolmentKey: Hashable {
    let student: String
    let course: Int
}

func asciiLess(_ first: String, _ second: String) -> Bool {
    first.utf8.lexicographicallyPrecedes(second.utf8)
}

func readRecords(_ path: String) throws -> [(line: Int, fields: [String])] {
    let content = try String(contentsOfFile: path, encoding: .utf8)
    return content.split(separator: "\n").enumerated().dropFirst().map { index, line in
        (index + 1, line.split(separator: ",").map(String.init))
    }
}

func loadCourses(_ path: String, _ errors: inout [String]) throws -> [Course] {
    var courses: [String: Course] = [:]
    for record in try readRecords(path) {
        let fields = record.fields
        let id = fields[0]
        if courses[id] != nil {
            errors.append("courses.csv line \(record.line): duplicate course \(id)")
        } else {
            courses[id] = Course(id: id, duration: Int(fields[1])!, name: fields[2])
        }
    }
    return courses.keys.sorted(by: asciiLess).map { courses[$0]! }
}

func loadEnrolments(_ path: String, _ courses: inout [Course], _ errors: inout [String]) throws -> StudentCourses {
    let indices = Dictionary(uniqueKeysWithValues: courses.enumerated().map { ($0.element.id, $0.offset) })
    var accepted: Set<EnrolmentKey> = []
    var students: StudentCourses = [:]
    for record in try readRecords(path) {
        let student = record.fields[0]
        let id = record.fields[1]
        guard let course = indices[id] else {
            errors.append("enrolments.csv line \(record.line): unknown course \(id)")
            continue
        }
        guard accepted.insert(EnrolmentKey(student: student, course: course)).inserted else {
            errors.append("enrolments.csv line \(record.line): duplicate enrolment \(student) \(id)")
            continue
        }
        courses[course].students.append(student)
        students[student, default: []].append(course)
    }
    for index in courses.indices {
        courses[index].students.sort(by: asciiLess)
    }
    for student in Array(students.keys) {
        students[student]!.sort()
    }
    return students
}
