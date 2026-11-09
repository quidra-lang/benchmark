struct Block {
    let first: Int, last: Int, labels: [String]
    var successors: [Int] = [], predecessors: [Int] = []
}
struct NaturalLoop {
    let header: Int, latches: [Int], blocks: Set<Int>, exits: Set<Int>, outside: Set<Int>;
    var depth = 0
}
final class Graph {
    let instructions: [Instruction]
    var blocks: [Block] = [], owners: [Int] = [], positions: [Int] = [], reachable: Set<Int> = [], postorder: [Int] = [], order: [Int] = [], dominators: [Set<Int>] = [], idom: [Int?] = [], loops: [NaturalLoop] = [], depths: [Int] = []
    init(_ function: Function) {
        instructions = function.instructions;
        var labels: [Int: [String]] = [:], leaders: Set<Int> = [0], index = 0
        for (lineIndex, line) in function.code.enumerated() {
            switch line {
                case .label(let label): labels[index, default: []].append(label);
                leaders.insert(index);
                case .instruction(let instruction): positions.append(lineIndex);
                index += 1;
                if ["goto", "if", "return"].contains(instruction.kind) && index < instructions.count {
                    leaders.insert(index)
                }
            }
        }
        let starts = leaders.sorted();
        owners = Array(repeating: 0, count: instructions.count)
        for (i, first) in starts.enumerated() {
            let last = i + 1 < starts.count ? starts[i + 1] - 1 : instructions.count - 1;
            blocks.append(Block(first: first, last: last, labels: labels[first] ?? []));
            for j in first...last {
                owners[j] = i
            }
        }
        var labelBlocks: [String: Int] = [:];
        for (i, block) in blocks.enumerated() {
            for label in block.labels {
                labelBlocks[label] = i
            }
        }
        for i in blocks.indices {
            let instruction = instructions[blocks[i].last]
            if instruction.kind == "goto" {
                blocks[i].successors = [labelBlocks[instruction.target]!]
            }
            else if instruction.kind == "if" {
                blocks[i].successors = [i + 1];
                let target = labelBlocks[instruction.target]!;
                if target != i + 1 {
                    blocks[i].successors.append(target)
                }
            }
            else if instruction.kind != "return" {
                blocks[i].successors = [i + 1]
            }
        }
        for i in blocks.indices {
            for j in blocks[i].successors {
                blocks[j].predecessors.append(i)
            }
        };
        visit(0);
        order = Array(postorder.reversed())
        dominators = blocks.indices.map {
            $0 == 0 ? [0] : reachable
        };
        idom = Array(repeating: nil, count: blocks.count)
        while true {
            var changed = false
            for b in order.dropFirst() {
                let predecessors = blocks[b].predecessors.filter {
                    reachable.contains($0)
                };
                var set = reachable;
                for p in predecessors {
                    set.formIntersection(dominators[p])
                };
                set.insert(b);
                if set != dominators[b] {
                    dominators[b] = set;
                    changed = true
                }
            };
            if !changed {
                break
            }
        }
        for b in order.dropFirst() {
            idom[b] = dominators[b].filter {
                $0 != b
            }.max {
                dominators[$0].count == dominators[$1].count ? $0 > $1 : dominators[$0].count < dominators[$1].count
            }
        }
        for h in reachable.sorted() {
            let latches = reachable.filter {
                blocks[$0].successors.contains(h) && dominators[$0].contains(h)
            }.sorted();
            if latches.isEmpty {
                continue
            }
            var members: Set<Int> = [h], pending = latches
            while let b = pending.popLast() {
                if b == h || !members.insert(b).inserted {
                    continue
                };
                pending += blocks[b].predecessors.filter {
                    reachable.contains($0)
                }
            }
            var exits: Set<Int> = [], outside: Set<Int> = []
            for b in members {
                if instructions[blocks[b].last].kind == "return" {
                    exits.insert(b)
                };
                for s in blocks[b].successors where !members.contains(s) {
                    exits.insert(b);
                    outside.insert(s)
                }
            }
            loops.append(NaturalLoop(header: h, latches: latches, blocks: members, exits: exits, outside: outside))
        }
        depths = blocks.indices.map {
            b in loops.filter {
                $0.blocks.contains(b)
            }.count
        }
        for i in loops.indices {
            let header = loops[i].header;
            loops[i].depth = loops.filter {
                $0.blocks.contains(header)
            }.count
        }
    }
    func visit(_ b: Int) {
        reachable.insert(b);
        for s in blocks[b].successors where !reachable.contains(s) {
            visit(s)
        };
        postorder.append(b)
    }
}
