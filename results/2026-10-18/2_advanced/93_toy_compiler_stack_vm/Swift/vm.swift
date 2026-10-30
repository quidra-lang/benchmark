struct CallEdge: Hashable {
    let caller: Int, callee: Int
}
struct Frame {
    var locals: [Int];
    let returnAddress: Int
}
struct VMResult {
    let output: [String], counts: [Int], calls: [Int], edges: [CallEdge: Int], executed: Int, maxStack: Int, maxDepth: Int, errorPC: Int?, message: String?, callers: [Int]
}
enum VM {
    static func run(_ code: [Instruction], _ owners: [Int], _ starts: [Int], _ area: Int, _ input: [Int]) -> VMResult {
        let unitAt = Dictionary(uniqueKeysWithValues: starts.enumerated().map {
            ($0.element, $0.offset)
        })
        var global = Array(repeating: 0, count: area), stack: [Int] = [], frames: [Frame] = [], counts = Array(repeating: 0, count: code.count), calls = Array(repeating: 0, count: starts.count), edges: [CallEdge: Int] = [:]
        var output: [String] = []
        var pc = 0, read = 0, executed = 0, maxStack = 0, maxDepth = 0, message: String?, errorPC: Int?
        execution: while true {
            if executed == 100000 {
                message = "instruction limit exceeded";
                errorPC = pc;
                break
            }
            let instruction = code[pc], op = instruction.op, args = instruction.operands
            counts[pc] += 1;
            executed += 1;
            var next = pc + 1
            switch op {
                case "PUSH": stack.append(args[0])
                case "POP": stack.removeLast()
                case "LOADG": stack.append(global[args[0]])
                case "STOREG": global[args[0]] = stack.removeLast()
                case "LOADL": stack.append(frames.last!.locals[args[0]])
                case "STOREL": let value = stack.removeLast();
                frames[frames.count - 1].locals[args[0]] = value
                case "LOADA", "STOREA":
                let value = op == "STOREA" ? stack.removeLast() : 0, index = stack.removeLast()
                if index < 0 || index >= args[1] {
                    message = "index \(index) out of bounds for array of size \(args[1])"
                }
                else if op == "LOADA" {
                    stack.append(global[args[0] + index])
                } else {
                    global[args[0] + index] = value
                }
                case "ADD", "SUB", "MUL", "DIV", "MOD":
                let b = stack.removeLast(), a = stack.removeLast()
                if (op == "DIV" || op == "MOD") && b == 0 {
                    message = "division by zero"
                }
                else {
                    let value: Int;
                    switch op {
                        case "ADD": value = a + b;
                        case "SUB": value = a - b;
                        case "MUL": value = a * b;
                        case "DIV": value = a / b;
                        default: value = a - b * (a / b)
                    }
                    if (-2147483648...2147483647).contains(value) {
                        stack.append(value)
                    } else {
                        message = "integer overflow"
                    }
                }
                case "NEG": let value = -stack.removeLast();
                if (-2147483648...2147483647).contains(value) {
                    stack.append(value)
                } else {
                    message = "integer overflow"
                }
                case "NOT": let value = stack.removeLast();
                stack.append(value == 0 ? 1 : 0)
                case "LT", "LE", "GT", "GE", "EQ", "NE":
                let b = stack.removeLast(), a = stack.removeLast(), value: Bool
                switch op {
                    case "LT": value = a < b;
                    case "LE": value = a <= b;
                    case "GT": value = a > b;
                    case "GE": value = a >= b;
                    case "EQ": value = a == b;
                    default: value = a != b
                };
                stack.append(value ? 1 : 0)
                case "JUMP": next = args[0]
                case "JUMPF", "JUMPT": let value = stack.removeLast();
                if op == "JUMPF" ? value == 0 : value != 0 {
                    next = args[0]
                }
                case "CALL":
                if frames.count == 100 {
                    message = "call depth limit exceeded"
                }
                else {
                    let n = args[1], values = Array(stack.suffix(n));
                    stack.removeLast(n);
                    frames.append(Frame(locals: values, returnAddress: pc + 1));
                    next = args[0]
                    let unit = unitAt[args[0]]!;
                    calls[unit] += 1;
                    edges[CallEdge(caller: owners[pc], callee: unit), default: 0] += 1
                }
                case "ENTER": let k = frames.count - 1, count = args[0] - frames[k].locals.count;
                frames[k].locals += Array(repeating: 0, count: count)
                case "RET", "RETV": next = frames.removeLast().returnAddress
                case "READ": if read == input.count {
                    message = "read past end of input"
                } else {
                    stack.append(input[read]);
                    read += 1
                }
                case "PRINT": let values = Array(stack.suffix(args[0]));
                stack.removeLast(args[0]);
                output.append(values.map(String.init).joined(separator: " "))
                case "HALT": maxStack = max(maxStack, stack.count);
                maxDepth = max(maxDepth, frames.count);
                break execution
                default: preconditionFailure()
            }
            if message != nil {
                errorPC = pc;
                break
            }
            maxStack = max(maxStack, stack.count);
            maxDepth = max(maxDepth, frames.count);
            pc = next
        }
        return VMResult(output: output, counts: counts, calls: calls, edges: edges, executed: executed, maxStack: maxStack, maxDepth: maxDepth, errorPC: errorPC, message: message, callers: frames.dropFirst().reversed().map {
            $0.returnAddress - 1
        })
    }
}
