final class Threads {
    var sequence: [(Int, Capture)] = [], marks: Set<Int> = []
}
final class Pike {
    let code: [Instruction], subject: [Int], flags: Flags, groups: Int, full: Bool;
    var steps = 0
    init(_ code: [Instruction], _ subject: [Int], _ flags: Flags, _ groups: Int, _ full: Bool) {
        self.code = code;
        self.subject = subject;
        self.flags = flags;
        self.groups = groups;
        self.full = full
    }
    func add(_ list: Threads, _ pc: Int, _ original: Capture, _ position: Int) {
        if !list.marks.insert(pc).inserted {
            return
        };
        steps += 1;
        var capture = original
        switch code[pc] {
            case .jump(let x): add(list, x, capture, position)
            case .split(let x, let y): add(list, x, capture, position);
            add(list, y, capture, position)
            case .save(let k): capture[k] = position;
            add(list, pc + 1, capture, position)
            case .assertion(let kind): if Charset.assertion(kind, subject, position, flags) {
                add(list, pc + 1, capture, position)
            }
            default: list.sequence.append((pc, capture))
        }
    }
    func search(_ start: Int) -> Capture? {
        var matched: Capture?, list = Threads(), position = start
        while true {
            if matched == nil && (!full || position == start) {
                add(list, 0, Array(repeating: nil, count: 2 * groups + 2), position)
            }
            let next = Threads()
            for (pc, capture) in list.sequence {
                steps += 1
                if case .match = code[pc] {
                    if !full || position == subject.count {
                        matched = capture;
                        break
                    }
                }
                else if consumes(code[pc], subject, position, flags) {
                    add(next, pc + 1, capture, position + 1)
                }
            }
            if position == subject.count || next.sequence.isEmpty && (matched != nil || full) {
                return matched
            };
            list = next;
            position += 1
        }
    }
}
