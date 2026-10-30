func position(_ path: Path, _ time: Int) -> Cell {
    path[min(time, path.count - 1)]
}
struct Conflict {
    let time: Int, a: Int, b: Int, vertex: Bool, source: Cell, destination: Cell
    func constrain(_ agent: Int, _ constraints: inout Constraints) {
        if vertex {
            constraints.states.insert(State(cell: destination, time: time))
        }
        else {
            constraints.moves.insert(Move(source: agent == a ? source : destination, destination: agent == a ? destination : source, time: time))
        }
    }
}
enum CBS {
    static func conflicts(_ paths: [Path]) -> [Conflict] {
        let maximum = paths.map {
            $0.count - 1
        }.max() ?? 0
        var conflicts: [Conflict] = []
        if maximum == 0 {
            return conflicts
        }
        for time in 1...maximum {
            for a in paths.indices {
                for b in (a + 1)..<paths.count {
                    let u = position(paths[a], time - 1), v = position(paths[a], time), x = position(paths[b], time - 1), y = position(paths[b], time)
                    if v == y {
                        conflicts.append(Conflict(time: time, a: a, b: b, vertex: true, source: v, destination: v))
                    }
                    else if u == y && v == x {
                        conflicts.append(Conflict(time: time, a: a, b: b, vertex: false, source: u, destination: v))
                    }
                }
            }
        }
        return conflicts
    }
}
struct Node {
    let id: Int, parent: Int?, depth: Int, constraints: [Constraints], paths: [Path], cost: Int, conflicts: [Conflict]
    init(id: Int, parent: Int?, depth: Int, constraints: [Constraints], paths: [Path], soc: Bool) {
        self.id = id;
        self.parent = parent;
        self.depth = depth;
        self.constraints = constraints;
        self.paths = paths;
        cost = soc ? paths.reduce(0) {
            $0 + $1.count - 1
        } : paths.map {
            $0.count - 1
        }.max()!;
        conflicts = CBS.conflicts(paths)
    }
    static func before(_ a: Self, _ b: Self) -> Bool {
        if a.cost != b.cost {
            return a.cost < b.cost
        }
        if a.conflicts.count != b.conflicts.count {
            return a.conflicts.count < b.conflicts.count
        }
        return a.id < b.id
    }
}
