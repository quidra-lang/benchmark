import Foundation
let commandNames = ["ALLOC", "PUSH", "LOAD", "POP", "SET", "OVERWRITE", "CHECKPOINT"]
struct Collector {
    let name: String,
    algorithm: String,
    young: Int,
    age: Int
}
struct Config {
    var size = 0,
    collectors = [Collector](),
    maps = [String](),
    windows = [Int](),
    width = 0
    init() throws {
        for line in try String(contentsOfFile: "input/config.txt", encoding: .utf8).split(separator: "\n") {
            let p = line.split(separator: " ").map(String.init);
            switch p[0] {
                case "HEAP": size = Int(p[1])!;
                case "COLLECTOR": collectors.append(Collector(name: p[1], algorithm: p[2], young: p.count>3 ? Int(p[3])! : 0, age: p.count>4 ? Int(p[4])! : 0));
                case "MAPS": maps = Array(p.dropFirst());
                case "MMU": windows = p.dropFirst().map {
                    Int($0)!
                };
                default: width = Int(p[1])!
            }
        }
    }
}
enum Kind {
    case alloc(Int, Int), push(Int?), load(Int, Int), pop(Int), set(Int, Int, Int?), overwrite(Int, Int?), checkpoint(String)
}
struct Command {
    let line: Int,
    kind: Kind
    var name: Int {
        switch kind {
            case .alloc: return 0;
            case .push: return 1;
            case .load: return 2;
            case .pop: return 3;
            case .set: return 4;
            case .overwrite: return 5;
            case .checkpoint: return 6
        }
    }
}
struct ParsedLine {
    let command: Command?,
    reason: String?
}
func number(_ s: String) -> Bool {
    !s.isEmpty && s.count <= 4 && (s.count == 1 || !s.hasPrefix("0")) && s.utf8.allSatisfy {
        $0 >= 48 && $0 <= 57
    }
}
func label(_ s: String) -> Bool {
    !s.isEmpty && s.count <= 16 && s.utf8.allSatisfy {
        ($0 >= 97 && $0 <= 122) || ($0 >= 48 && $0 <= 57) || $0 == 95
    }
}
func parse(_ line: Int, _ text: String) -> ParsedLine {
    let p = text.components(separatedBy: " "), forms = ["ALLOC": "nn", "PUSH": "r", "LOAD": "nn", "POP": "n", "SET": "nnr", "OVERWRITE": "nr", "CHECKPOINT": "l"]
    guard let form = forms[p[0]], p.count == form.count+1 else {
        return ParsedLine(command: nil, reason: "syntax")
    }
    for(k, s)in zip(form, p.dropFirst()) {
        if k == "n" ? !number(s) : k == "r" ? s != "-" && !number(s) : !label(s) {
            return ParsedLine(command: nil, reason: "syntax")
        }
    }
    func n(_ i: Int) -> Int {
        Int(p[i])!
    };
    func r(_ i: Int) -> Int? {
        p[i] == "-" ? nil : n(i)
    };
    let kind: Kind
    switch p[0] {
        case "ALLOC": if n(1)>6 || n(2)>24 {
            return ParsedLine(command: nil, reason: "range")
        };
        kind = .alloc(n(1), n(2));
        case "PUSH": kind = .push(r(1));
        case "LOAD": kind = .load(n(1), n(2));
        case "POP": if n(1) == 0 {
            return ParsedLine(command: nil, reason: "range")
        };
        kind = .pop(n(1));
        case "SET": kind = .set(n(1), n(2), r(3));
        case "OVERWRITE": kind = .overwrite(n(1), r(2));
        default: kind = .checkpoint(p[1])
    };
    return ParsedLine(command: Command(line: line, kind: kind), reason: nil)
}
func readScript() throws -> [ParsedLine] {
    var lines = try String(contentsOfFile: "input/mutator.txt", encoding: .utf8).components(separatedBy: "\n");
    lines.removeLast();
    return lines.enumerated().map {
        parse($0.offset+1, $0.element)
    }
}
