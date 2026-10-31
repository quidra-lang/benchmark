enum Operand: Hashable {
    case constant(Int), variable(String)
    init(_ text: String) {
        if text.first == "-" || text.first.map({
            $0 >= "0" && $0 <= "9"
        }) ?? false {
            self = .constant(Int(text)!)
        } else {
            self = .variable(text)
        }
    }
    var text: String {
        switch self {
            case .constant(let n): return String(n);
            case .variable(let name): return name
        }
    }
    var variable: String? {
        if case .variable(let name) = self {
            return name
        };
        return nil
    }
    var constant: Int? {
        if case .constant(let n) = self {
            return n
        };
        return nil
    }
}
struct TacExpression: Hashable {
    let kind: String, operation: String, a: Operand, b: Operand?
    var text: String {
        kind == "load" ? "\(operation)[\(a.text)]" : a.text + operation + b!.text
    }
    func uses(_ name: String) -> Bool {
        a.variable == name || b?.variable == name
    }
}
struct Instruction {
    var kind: String, destination: String?, a: Operand?, b: Operand?, operation = "", target = "", array = "", function = "", count = 0
    init(_ kind: String) {
        self.kind = kind
    }
    static func copy(_ destination: String, _ a: Operand) -> Self {
        var result = Self("copy");
        result.destination = destination;
        result.a = a;
        return result
    }
    var operands: [Operand] {
        [a, b].compactMap {
            $0
        }
    }
    var used: [String] {
        operands.compactMap(\.variable)
    }
    var expression: TacExpression? {
        ["bin", "load"].contains(kind) ? TacExpression(kind: kind, operation: kind == "bin" ? operation : array, a: a!, b: b) : nil
    }
    var text: String {
        let a = a?.text ?? "", b = b?.text ?? "", d = destination ?? ""
        switch kind {
            case "copy": return "\(d) = \(a)"
            case "bin": return "\(d) = \(a) \(operation) \(b)"
            case "load": return "\(d) = \(array)[\(a)]"
            case "store": return "\(array)[\(a)] = \(b)"
            case "goto": return "goto " + target
            case "if": return "if \(a) \(operation) \(b) goto \(target)"
            case "read": return "read " + d
            case "return": return self.a == nil ? "return" : "return " + a
            case "call": return (destination == nil ? "" : d + " = ") + "call \(function) \(count)"
            default: return kind + " " + a
        }
    }
}
enum CodeLine {
    case label(String), instruction(Instruction)
}
struct Function {
    var name: String, parameters: [String], code: [CodeLine], temporary = 0, preheader = 0
    var instructions: [Instruction] {
        code.compactMap {
            if case .instruction(let instruction) = $0 {
                return instruction
            };
            return nil
        }
    }
    var text: [String] {
        ["func " + name + parameters.map {
            " " + $0
        }.joined()] + code.map {
            switch $0 {
                case .label(let label): return label + ":";
                case .instruction(let instruction): return "    " + instruction.text
            }
        } + ["end"]
    }
}
struct Program {
    var arrays: [(String, Int)], functions: [Function]
    var text: [String] {
        var lines = arrays.map {
            "array \($0.0) \($0.1)"
        };
        for function in functions {
            if !lines.isEmpty {
                lines.append("")
            };
            lines += function.text
        };
        return lines
    }
}
enum TacParser {
    static func indexed(_ text: String) -> (String, Operand) {
        let i = text.firstIndex(of: "[")!;
        return (String(text[..<i]), Operand(String(text[text.index(after: i)..<text.index(before: text.endIndex)])))
    }
    static func parse(_ text: String) -> Program {
        var program = Program(arrays: [], functions: [])
        for line in text.split(separator: "\n") {
            let w = line.split(separator: " ").map(String.init);
            if w.isEmpty || w[0].hasPrefix("#") {
                continue
            }
            if w[0] == "array" {
                program.arrays.append((w[1], Int(w[2])!));
                continue
            }
            if w[0] == "func" {
                program.functions.append(Function(name: w[1], parameters: Array(w.dropFirst(2)), code: []));
                continue
            }
            if w[0] == "end" {
                continue
            };
            let f = program.functions.count - 1
            if w.count == 1 && w[0].last == ":" {
                program.functions[f].code.append(.label(String(w[0].dropLast())));
                continue
            }
            var instruction = Instruction("copy")
            switch w[0] {
                case "goto": instruction.kind = "goto";
                instruction.target = w[1]
                case "if": instruction.kind = "if";
                instruction.a = Operand(w[1]);
                instruction.operation = w[2];
                instruction.b = Operand(w[3]);
                instruction.target = w[5]
                case "param", "return", "read", "print": instruction.kind = w[0];
                if w.count > 1 {
                    if w[0] == "read" {
                        instruction.destination = w[1]
                    } else {
                        instruction.a = Operand(w[1])
                    }
                }
                default:
                if w[0].contains("[") {
                    instruction.kind = "store";
                    let (array, index) = indexed(w[0]);
                    instruction.array = array;
                    instruction.a = index;
                    instruction.b = Operand(w[2])
                }
                else {
                    let start = w[0] == "call" ? 0 : 2;
                    if start == 2 {
                        instruction.destination = w[0]
                    }
                    if w[start] == "call" {
                        instruction.kind = "call";
                        instruction.function = w[start + 1];
                        instruction.count = Int(w[start + 2])!
                    }
                    else if w.count == 5 {
                        instruction.kind = "bin";
                        instruction.a = Operand(w[2]);
                        instruction.operation = w[3];
                        instruction.b = Operand(w[4])
                    }
                    else if w[2].contains("[") {
                        instruction.kind = "load";
                        let (array, index) = indexed(w[2]);
                        instruction.array = array;
                        instruction.a = index
                    }
                    else {
                        instruction.a = Operand(w[2])
                    }
                }
            };
            program.functions[f].code.append(.instruction(instruction))
        };
        return program
    }
    static func operation(_ op: String, _ a: Int, _ b: Int) -> Int {
        switch op {
            case "+": return a + b;
            case "-": return a - b;
            case "*": return a * b;
            case "/": return a / b;
            case "%": return a % b;
            case "<": return a < b ? 1 : 0;
            case "<=": return a <= b ? 1 : 0;
            case ">": return a > b ? 1 : 0;
            case ">=": return a >= b ? 1 : 0;
            case "==": return a == b ? 1 : 0;
            default: return a != b ? 1 : 0
        }
    }
    static func labels(_ function: Function) -> [String: Int] {
        var labels: [String: Int] = [:], index = 0;
        for line in function.code {
            switch line {
                case .label(let label): labels[label] = index;
                case .instruction: index += 1
            }
        };
        return labels
    }
}
