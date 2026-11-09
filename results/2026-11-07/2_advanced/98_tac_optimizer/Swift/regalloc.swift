struct SpillCost: Comparable, CustomStringConvertible {
    var digits: [Int] = [0]
    init(_ value: Int = 0) {
        digits = [value]
    }
    static func power(_ exponent: Int) -> Self {
        var result = Self();
        result.digits = Array(repeating: 0, count: exponent / 9 + 1);
        var value = 1;
        for _ in 0..<(exponent % 9) {
            value *= 10
        };
        result.digits[exponent / 9] = value;
        return result
    }
    static func < (a: Self, b: Self) -> Bool {
        if a.digits.count != b.digits.count {
            return a.digits.count < b.digits.count
        };
        for i in a.digits.indices.reversed() where a.digits[i] != b.digits[i] {
            return a.digits[i] < b.digits[i]
        };
        return false
    }
    static func + (a: Self, b: Self) -> Self {
        var result = Self(), carry = 0;
        result.digits = [];
        for i in 0..<max(a.digits.count, b.digits.count) {
            let value = (i < a.digits.count ? a.digits[i] : 0) + (i < b.digits.count ? b.digits[i] : 0) + carry;
            result.digits.append(value % 1_000_000_000);
            carry = value / 1_000_000_000
        };
        if carry > 0 {
            result.digits.append(carry)
        };
        return result
    }
    static func * (a: Self, b: Int) -> Self {
        var result = Self(), carry = 0;
        result.digits = [];
        for digit in a.digits {
            let value = digit * b + carry;
            result.digits.append(value % 1_000_000_000);
            carry = value / 1_000_000_000
        };
        while carry > 0 {
            result.digits.append(carry % 1_000_000_000);
            carry /= 1_000_000_000
        };
        while result.digits.count > 1 && result.digits.last == 0 {
            result.digits.removeLast()
        };
        return result
    }
    var description: String {
        var text = String(digits.last!);
        for digit in digits.dropLast().reversed() {
            let part = String(digit);
            text += String(repeating: "0", count: 9 - part.count) + part
        };
        return text
    }
}
struct Allocation {
    let nodes: [String], neighbors: [String: Set<String>], costs: [String: SpillCost], order: [String], potential: [(String, Int)], registers: [String: Int], spills: Set<String>
}
enum Regalloc {
    static func allocate(_ function: Function, _ graph: Graph, _ analysis: Analysis, _ count: Int) -> Allocation {
        var nodes = Set(function.parameters)
        for i in graph.instructions.indices where graph.reachable.contains(graph.owners[i]) {
            if let x = graph.instructions[i].destination {
                nodes.insert(x)
            };
            nodes.formUnion(graph.instructions[i].used)
        }
        let sorted = nodes.sorted();
        var neighbors = Dictionary(uniqueKeysWithValues: sorted.map {
            ($0, Set<String>())
        }), costs = Dictionary(uniqueKeysWithValues: sorted.map {
            ($0, SpillCost())
        }), partners: [String: Set<String>] = [:]
        func edge(_ a: String, _ b: String) {
            if a != b {
                neighbors[a, default: []].insert(b);
                neighbors[b, default: []].insert(a)
            }
        }
        for b in graph.reachable {
            var live = analysis.live.output[b]
            for i in (graph.blocks[b].first...graph.blocks[b].last).reversed() {
                let instruction = graph.instructions[i]
                if let x = instruction.destination {
                    for v in live where v != x && !(instruction.kind == "copy" && instruction.a?.variable == v) {
                        edge(x, v)
                    }
                };
                live = Transfer.live(live, instruction)
            }
            let weight = SpillCost.power(graph.depths[b])
            for i in graph.blocks[b].first...graph.blocks[b].last {
                let instruction = graph.instructions[i];
                for v in instruction.used + (instruction.destination.map {
                    [$0]
                } ?? []) {
                    costs[v] = costs[v]! + weight
                }
            }
        }
        let initial = analysis.live.input[0].union(function.parameters)
        for p in function.parameters {
            costs[p] = costs[p]! + SpillCost(1);
            for v in initial where v != p {
                edge(p, v)
            }
        }
        for instruction in graph.instructions where instruction.kind == "copy" {
            if let x = instruction.destination, let y = instruction.a?.variable, x != y {
                partners[x, default: []].insert(y);
                partners[y, default: []].insert(x)
            }
        }
        var remaining = nodes, order: [String] = [], potential: [(String, Int)] = []
        while !remaining.isEmpty {
            let degrees = Dictionary(uniqueKeysWithValues: remaining.map {
                ($0, neighbors[$0]!.intersection(remaining).count)
            }), low = remaining.filter {
                degrees[$0]! < count
            }
            let chosen: String
            if !low.isEmpty {
                chosen = low.min {
                    degrees[$0]! == degrees[$1]! ? $0 < $1 : degrees[$0]! < degrees[$1]!
                }!
            }
            else {
                chosen = remaining.min {
                    let a = costs[$0]! * degrees[$1]!, b = costs[$1]! * degrees[$0]!;
                    return a == b ? $0 < $1 : a < b
                }!;
                potential.append((chosen, degrees[chosen]!))
            }
            order.append(chosen);
            remaining.remove(chosen)
        }
        var registers: [String: Int] = [:], spills: Set<String> = []
        for node in order.reversed() {
            let occupied = Set(neighbors[node]!.compactMap {
                registers[$0]
            }), free = (0..<count).filter {
                !occupied.contains($0)
            }
            if free.isEmpty {
                spills.insert(node);
                continue
            };
            let biased = (partners[node] ?? []).compactMap {
                registers[$0]
            }.filter {
                free.contains($0)
            };
            registers[node] = biased.min() ?? free[0]
        };
        return Allocation(nodes: sorted, neighbors: neighbors, costs: costs, order: order, potential: potential, registers: registers, spills: spills)
    }
}
