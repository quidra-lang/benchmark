struct Command {
    let indent: Int, flat: Bool, document: Document
}
struct Printed {
    let lines: [String], modes: [Int: String]
}
enum Printer {
    static func fits(_ remaining: Int, _ first: Command, _ stack: [Command]) -> Bool {
        if remaining < 0 {
            return false
        }
        var remaining = remaining, check = stack + [first]
        while let command = check.popLast() {
            let i = command.indent, flat = command.flat, document = command.document
            switch document {
                case .text(let string): remaining -= string.count
                case .ifBreak(let a, let b): remaining -= flat ? b.count : a.count
                case .line: if flat {
                    remaining -= 1
                } else {
                    return true
                }
                case .softline: if !flat {
                    return true
                }
                case .hardline: return true
                case .concat(let parts): for part in parts.reversed() {
                    check.append(Command(indent: i, flat: flat, document: part))
                }
                case .group(_, let child): check.append(Command(indent: i, flat: document.forced ? false : flat, document: child))
                case .nest(_, let child), .align(let child): check.append(Command(indent: i, flat: flat, document: child))
                default: break
            }
            if remaining < 0 {
                return false
            }
        }
        return true
    }
    static func print(_ document: Document, _ width: Int, _ column: Int) -> Printed {
        var stack = [Command(indent: 0, flat: false, document: document)], lines: [String] = [], modes: [Int: String] = [:], current = "", col = 0, pending: [String] = []
        func finalize() {
            var line = Lexer.trim(current)
            if !pending.isEmpty {
                let comment = pending.joined(separator: " ")
                if column > 0 && line.count < column - 1 && column - 1 + comment.count <= width {
                    line += String(repeating: " ", count: column - 1 - line.count)
                }
                else {
                    line += " "
                }
                line += comment;
                pending = []
            }
            lines.append(line)
        }
        while let command = stack.popLast() {
            let i = command.indent, flat = command.flat, document = command.document
            switch document {
                case .text(let string): current += string;
                col += string.count
                case .ifBreak(let a, let b): let string = flat ? b : a;
                current += string;
                col += string.count
                case .line, .softline, .hardline:
                let newline: Bool
                if case .hardline = document {
                    newline = true
                } else {
                    newline = !flat
                }
                if newline {
                    finalize();
                    current = String(repeating: " ", count: i);
                    col = i
                }
                else if case .line = document {
                    current += " ";
                    col += 1
                }
                case .concat(let parts): for part in parts.reversed() {
                    stack.append(Command(indent: i, flat: flat, document: part))
                }
                case .nest(let n, let child): stack.append(Command(indent: i + n, flat: flat, document: child))
                case .align(let child): stack.append(Command(indent: col, flat: flat, document: child))
                case .suffix(let string): pending.append(string)
                case .breakParent: break
                case .group(let id, let child):
                let mode = flat ? "flat" : document.forced ? "forced" : fits(width - col, Command(indent: i, flat: true, document: child), stack) ? "flat" : "break"
                modes[id] = mode;
                stack.append(Command(indent: i, flat: mode == "flat", document: child))
            }
        }
        finalize()
        return Printed(lines: lines, modes: modes)
    }
}
