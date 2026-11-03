struct State: Hashable {
    let cell: Cell;
    let time: Int
}
struct Move: Hashable {
    let source: Cell;
    let destination: Cell;
    let time: Int
}
struct Constraints {
    var states: Set<State> = [], moves: Set<Move> = [], permanent: Set<State> = []
    func allowed(_ source: Cell, _ destination: Cell, _ time: Int) -> Bool {
        !states.contains(State(cell: destination, time: time)) && !permanent.contains(where: {
            $0.cell == destination && $0.time <= time
        }) && (source == destination || !moves.contains(Move(source: source, destination: destination, time: time)))
    }
    func arrival(_ goal: Cell) -> Int {
        states.filter {
            $0.cell == goal
        }.map {
            $0.time + 1
        }.max() ?? 0
    }
    mutating func reserve(_ path: Path, start: Int, permanent: Bool) {
        for (i, cell) in path.enumerated() {
            states.insert(State(cell: cell, time: start + i));
            if i > 0 && cell != path[i - 1] {
                moves.insert(Move(source: cell, destination: path[i - 1], time: start + i))
            }
        }
        if permanent {
            self.permanent.insert(State(cell: path.last!, time: start + path.count - 1))
        }
    }
}
final class SearchCounts {
    var searches = 0, expansions = 0;
    let budget: Int;
    init(_ budget: Int) {
        self.budget = budget
    }
}
enum SearchAbort: Error {
    case budget
}
struct OpenState: Comparable {
    let state: State, f: Int, g: Int, serial: Int
    static func < (a: Self, b: Self) -> Bool {
        if a.f != b.f {
            return a.f < b.f
        }
        if a.g != b.g {
            return a.g > b.g
        }
        return a.serial < b.serial
    }
    static func == (a: Self, b: Self) -> Bool {
        a.serial == b.serial
    }
}
struct SearchHeap {
    var values: [OpenState] = []
    mutating func push(_ value: OpenState) {
        values.append(value);
        var i = values.count - 1
        while i > 0 {
            let p = (i - 1) / 2;
            if !(values[i] < values[p]) {
                break
            }
            values.swapAt(i, p);
            i = p
        }
    }
    mutating func pop() -> OpenState? {
        guard !values.isEmpty else {
            return nil
        }
        if values.count == 1 {
            return values.removeLast()
        }
        let first = values[0], last = values.removeLast();
        values[0] = last;
        var i = 0
        while 2 * i + 1 < values.count {
            var child = 2 * i + 1;
            if child + 1 < values.count && values[child + 1] < values[child] {
                child += 1
            }
            if !(values[child] < values[i]) {
                break
            }
            values.swapAt(i, child);
            i = child
        }
        return first
    }
}
enum LowLevel {
    static func search(_ grid: Grid, agent: Int, start: Cell, time: Int, maximum: Int, window: Bool, constraints: Constraints, counts: SearchCounts) throws -> Path? {
        counts.searches += 1
        let goal = grid.agents[agent].goal, distances = grid.distances[agent], arrival = constraints.arrival(goal), initial = State(cell: start, time: time)
        var open = SearchHeap(), generated: Set<State> = [initial], parents: [State: State] = [:], serial = 0
        open.push(OpenState(state: initial, f: distances[start]!, g: 0, serial: 0))
        while let current = open.pop() {
            counts.expansions += 1
            if counts.expansions > counts.budget {
                throw SearchAbort.budget
            }
            let state = current.state
            if (state.cell == goal && state.time >= arrival) || (window && state.time == maximum) {
                var path = [state.cell], state = state
                while let previous = parents[state] {
                    path.append(previous.cell);
                    state = previous
                }
                return Array(path.reversed())
            }
            if state.time == maximum {
                continue
            }
            for next in grid.destinations(state.cell) {
                guard let h = distances[next] else {
                    continue
                }
                let child = State(cell: next, time: state.time + 1)
                if constraints.allowed(state.cell, next, child.time) && generated.insert(child).inserted {
                    serial += 1;
                    parents[child] = state;
                    let g = child.time - time;
                    open.push(OpenState(state: child, f: g + h, g: g, serial: serial))
                }
            }
        }
        return nil
    }
}
