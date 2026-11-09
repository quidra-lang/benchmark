struct Edge {
    let first: Int
    let second: Int
    let shared: Int
}

struct ConflictGraph {
    let vertices: [Int]
    private let shared: [[Int: Int]]

    init(_ courses: [Course], _ students: StudentCourses) {
        vertices = courses.indices.filter { courses[$0].size > 0 }
        var counts = Array(repeating: [Int: Int](), count: courses.count)
        for enrolled in students.values {
            for (index, first) in enrolled.enumerated() {
                for second in enrolled.dropFirst(index + 1) {
                    counts[first][second, default: 0] += 1
                    counts[second][first, default: 0] += 1
                }
            }
        }
        shared = counts
    }

    func neighbours(_ course: Int) -> [Int: Int] {
        shared[course]
    }

    func degree(_ course: Int) -> Int {
        shared[course].count
    }

    func sharedTotal(_ course: Int) -> Int {
        shared[course].values.reduce(0, +)
    }

    func edges() -> [Edge] {
        vertices.flatMap { first in
            shared[first].keys.sorted().filter { first < $0 }.map { second in
                Edge(first: first, second: second, shared: shared[first][second]!)
            }
        }
    }

    func components() -> [[Int]] {
        var seen: Set<Int> = []
        var result: [[Int]] = []
        for vertex in vertices {
            guard seen.insert(vertex).inserted else { continue }
            var component = [vertex]
            var index = 0
            while index < component.count {
                for neighbour in shared[component[index]].keys.sorted() {
                    if seen.insert(neighbour).inserted { component.append(neighbour) }
                }
                index += 1
            }
            result.append(component.sorted())
        }
        return result.sorted {
            $0.count == $1.count ? $0[0] < $1[0] : $0.count > $1.count
        }
    }

    func greedyClique(_ courses: [Int]) -> [Int] {
        var candidates = courses
        var clique: [Int] = []
        while let chosen = candidates.min(by: {
            degree($0) == degree($1) ? $0 < $1 : degree($0) > degree($1)
        }) {
            clique.append(chosen)
            candidates = candidates.filter { shared[chosen][$0] != nil }
        }
        return clique
    }

    func kempeChain(_ assignment: Assignment, _ start: Int, _ first: Int, _ second: Int) -> [Int] {
        var chain = [start]
        var seen: Set<Int> = [start]
        var index = 0
        while index < chain.count {
            for neighbour in shared[chain[index]].keys.sorted() {
                guard let slot = assignment[neighbour], slot == first || slot == second else { continue }
                if seen.insert(neighbour).inserted { chain.append(neighbour) }
            }
            index += 1
        }
        return chain.sorted()
    }
}

func reachable(_ arrows: [[Int]], _ source: Int, _ target: Int) -> Bool {
    var stack = [source]
    var seen: Set<Int> = [source]
    while let node = stack.popLast() {
        if node == target { return true }
        for successor in arrows[node] {
            if seen.insert(successor).inserted { stack.append(successor) }
        }
    }
    return false
}
