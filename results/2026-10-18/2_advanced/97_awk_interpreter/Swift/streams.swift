import Foundation
enum Operand {
    case assignment(String, String), file(String, Int)
}
struct Arguments {
    var options: [(String, String)] = [], operands: [Operand] = [], files: [(String, Int)] = []
}
func validFile(_ text: String) -> Bool {
    !text.isEmpty && text.first != "." && text.utf8.allSatisfy {
        Lexer.letter($0) || Lexer.digit($0) || [UInt8(46), 95, 45].contains($0)
    }
}
func readFile(_ name: String) -> [String]? {
    guard validFile(name), let text = try? String(contentsOfFile: "input/" + name, encoding: .ascii) else {
        return nil
    };
    return text.isEmpty ? [] : Array(text.components(separatedBy: "\n").dropLast())
}
func arguments(_ text: String) -> Arguments {
    var result = Arguments()
    func assignment(_ text: String) -> (String, String)? {
        guard let i = text.firstIndex(of: "=") else {
            return nil
        };
        return (String(text[..<i]), String(text[text.index(after: i)...]))
    }
    func variable(_ text: String) -> Bool {
        guard let first = text.utf8.first, Lexer.letter(first) || first == 95 else {
            return false
        };
        return text.utf8.allSatisfy {
            Lexer.letter($0) || Lexer.digit($0) || $0 == 95
        }
    }
    for line in text.split(separator: "\n").map(String.init) {
        if line.hasPrefix("-F ") {
            result.options.append(("FS", String(line.dropFirst(3))))
        }
        else if line.hasPrefix("-v ") {
            result.options.append(assignment(String(line.dropFirst(3)))!)
        }
        else if let (name, value) = assignment(line), variable(name) {
            result.operands.append(.assignment(name, value))
        }
        else {
            result.operands.append(.file(line, result.files.count));
            result.files.append((line, 0))
        }
    };
    return result
}
final class OutputStream {
    let name: String;
    var text = "", writes = 0, open = false;
    init(_ name: String) {
        self.name = name
    }
}
final class InputStream {
    let name: String;
    var lines: [String]?, position = 0, reads = 0, opened = false, open = false;
    init(_ name: String) {
        self.name = name
    }
}
final class Streams {
    var stdout = "", writes = 0, outputs: [OutputStream] = [], inputs: [InputStream] = []
    func output(_ name: String?, _ append: Bool, _ text: String) {
        guard let name else {
            stdout += text;
            writes += 1;
            return
        }
        if !outputs.contains(where: {
            $0.name == name
        }) {
            outputs.append(OutputStream(name))
        };
        let output = outputs.first {
            $0.name == name
        }!
        if !output.open {
            output.open = true;
            if !append {
                output.text = ""
            }
        };
        output.text += text;
        output.writes += 1
    }
    func getline(_ name: String) -> (Int, String?) {
        if !inputs.contains(where: {
            $0.name == name
        }) {
            inputs.append(InputStream(name))
        };
        let input = inputs.first {
            $0.name == name
        }!
        if !input.open {
            input.lines = readFile(name);
            input.position = 0;
            if input.lines != nil {
                input.open = true;
                input.opened = true
            }
        }
        guard let lines = input.lines else {
            return (-1, nil)
        };
        if input.position == lines.count {
            return (0, nil)
        };
        let line = lines[input.position];
        input.position += 1;
        input.reads += 1;
        return (1, line)
    }
    func close(_ name: String) -> Int {
        var closed = false
        if let output = outputs.first(where: {
            $0.name == name
        }) {
            closed = closed || output.open;
            output.open = false
        }
        if let input = inputs.first(where: {
            $0.name == name
        }) {
            closed = closed || input.open;
            input.open = false
        };
        return closed ? 0 : -1
    }
    func save() {
        try! FileManager.default.createDirectory(atPath: "output", withIntermediateDirectories: true)
        try! stdout.write(toFile: "output/stdout.txt", atomically: true, encoding: .utf8)
        for output in outputs {
            try! output.text.write(toFile: "output/" + output.name, atomically: true, encoding: .utf8)
        }
    }
}
