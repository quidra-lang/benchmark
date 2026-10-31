import Foundation
final class SourceFile {
    let lines: [LogicalLine], physicalLines: Int, guardName: String?
    var entered = 0, skipped = 0, output = 0, skippedLines = 0, once = false
    init(_ source: String) {
        lines = Lexer.lex(source);
        physicalLines = source.utf8.filter {
            $0 == 10
        }.count;
        guardName = IncludeManager.guardName(lines)
    }
}
final class IncludeManager {
    var files: [String: SourceFile] = [:], order: [String] = []
    static func search(_ name: String, _ quoted: Bool) -> String? {
        if quoted && FileManager.default.fileExists(atPath: "input/" + name) {
            return name
        }
        let path = "include/" + name;
        return FileManager.default.fileExists(atPath: "input/" + path) ? path : nil
    }
    static func guardName(_ original: [LogicalLine]) -> String? {
        let lines = original.filter {
            !$0.tokens.isEmpty
        };
        guard let first = lines.first?.tokens, let last = lines.last?.tokens, first.count == 3, first[0].text == "#", first[1].text == "ifndef", first[2].kind == "identifier", last.count == 2, last[0].text == "#", last[1].text == "endif" else {
            return nil
        }
        var depth = 0
        for (i, line) in lines.enumerated() {
            let tokens = line.tokens, directive = tokens.count >= 2 && tokens[0].text == "#" && tokens[1].kind == "identifier" ? tokens[1].text : ""
            if depth == 1 && ["elif", "elifdef", "elifndef", "else"].contains(directive) {
                return nil
            }
            if ["if", "ifdef", "ifndef"].contains(directive) {
                depth += 1
            } else if directive == "endif" {
                depth -= 1
            }
            if depth == 0 && i + 1 != lines.count {
                return nil
            }
        };
        return depth == 0 ? first[2].text : nil
    }
    func enter(_ path: String) -> SourceFile {
        if files[path] == nil {
            files[path] = SourceFile(try! String(contentsOfFile: "input/" + path, encoding: .ascii));
            order.append(path)
        };
        let file = files[path]!;
        file.entered += 1;
        return file
    }
}
