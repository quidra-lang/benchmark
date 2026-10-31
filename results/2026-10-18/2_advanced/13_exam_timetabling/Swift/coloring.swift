final class Attempt {
    private let courses: [Int]
    private let graph: ConflictGraph
    private let limit: Int
    private let candidateSlots: (Int, Assignment) -> [Int]
    private(set) var deadEnds = 0
    private(set) var deadEndCourse: Int?
    private(set) var aborted = false
    private(set) var chosen: [(course: Int, saturation: Int)] = []

    init(_ courses: [Int], _ graph: ConflictGraph, _ limit: Int, _ candidateSlots: @escaping (Int, Assignment) -> [Int]) {
        self.courses = courses
        self.graph = graph
        self.limit = limit
        self.candidateSlots = candidateSlots
    }

    private func saturation(_ course: Int, _ assignment: Assignment) -> Int {
        Set(graph.neighbours(course).keys.compactMap { assignment[$0] }).count
    }

    func search(_ assignment: inout Assignment) -> Bool {
        let remaining = courses.filter { assignment[$0] == nil }
        guard let course = remaining.min(by: { first, second in
            let firstSaturation = saturation(first, assignment)
            let secondSaturation = saturation(second, assignment)
            if firstSaturation != secondSaturation { return firstSaturation > secondSaturation }
            if graph.degree(first) != graph.degree(second) { return graph.degree(first) > graph.degree(second) }
            return first < second
        }) else { return true }
        chosen.append((course, saturation(course, assignment)))
        for slot in candidateSlots(course, assignment) {
            assignment[course] = slot
            if search(&assignment) { return true }
            assignment[course] = nil
            if aborted { return false }
        }
        chosen.removeLast()
        deadEnds += 1
        deadEndCourse = course
        aborted = deadEnds > limit
        return false
    }
}

func greedyNumbering(_ order: [Int], _ graph: ConflictGraph, _ courseCount: Int) -> Int {
    var numbers = Array<Int?>(repeating: nil, count: courseCount)
    var maximum = 0
    for course in order {
        let taken = Set(graph.neighbours(course).keys.compactMap { numbers[$0] })
        var number = 1
        while taken.contains(number) { number += 1 }
        numbers[course] = number
        maximum = max(maximum, number)
    }
    return maximum
}
