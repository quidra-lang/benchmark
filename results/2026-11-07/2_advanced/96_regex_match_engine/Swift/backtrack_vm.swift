struct BacktrackState {
    var pc: Int, position: Int, capture: Capture, splits: Set<Int>
}
struct StepLimit: Error {
}
final class Backtrack {
    let code: [Instruction], subject: [Int], flags: Flags, groups: Int, full: Bool;
    var steps = 0
    init(_ code: [Instruction], _ subject: [Int], _ flags: Flags, _ groups: Int, _ full: Bool) {
        self.code = code;
        self.subject = subject;
        self.flags = flags;
        self.groups = groups;
        self.full = full
    }
    func execute(_ pc: Int, _ position: Int, _ capture: Capture, _ partial: Bool) throws -> (Capture, Int)? {
        var stack = [BacktrackState(pc: pc, position: position, capture: capture, splits: [])]
        while var state = stack.popLast() {
            path: while true {
                steps += 1;
                if steps > 200000 {
                    throw StepLimit()
                }
                let instruction = code[state.pc]
                switch instruction {
                    case .char, .any, .characterClass:
                    if !consumes(instruction, subject, state.position, flags) {
                        break path
                    };
                    state.position += 1;
                    state.pc += 1;
                    state.splits = []
                    case .split(let x, let y):
                    if !state.splits.insert(state.pc).inserted {
                        break path
                    };
                    var alternate = state;
                    alternate.pc = y;
                    stack.append(alternate);
                    state.pc = x
                    case .jump(let x): state.pc = x
                    case .save(let k): state.capture[k] = state.position;
                    state.pc += 1
                    case .assertion(let kind): if !Charset.assertion(kind, subject, state.position, flags) {
                        break path
                    };
                    state.pc += 1
                    case .backref(let k):
                    guard let a = state.capture[2 * k], let b = state.capture[2 * k + 1], a <= b else {
                        break path
                    };
                    let length = b - a
                    if state.position + length > subject.count || !(0..<length).allSatisfy({
                        Charset.equal(subject[state.position + $0], subject[a + $0], flags)
                    }) {
                        break path
                    }
                    state.position += length;
                    state.pc += 1;
                    if length > 0 {
                        state.splits = []
                    }
                    case .look(let kind, let target):
                    let result = try execute(state.pc + 1, state.position, state.capture, true)
                    if kind == "NOT" {
                        if result != nil {
                            break path
                        };
                        state.pc = target
                    }
                    else {
                        guard let (capture, position) = result else {
                            break path
                        };
                        state.capture = capture
                        if kind == "ATOMIC" {
                            if position > state.position {
                                state.splits = []
                            };
                            state.position = position
                        };
                        state.pc = target
                    }
                    case .match: if partial || !full || state.position == subject.count {
                        return (state.capture, state.position)
                    };
                    break path
                }
            }
        };
        return nil
    }
    func search(_ start: Int) throws -> Capture? {
        for b in (full ? 0 : start)...(full ? 0 : subject.count) {
            if let result = try execute(0, b, Array(repeating: nil, count: 2 * groups + 2), false) {
                return result.0
            }
        };
        return nil
    }
}
