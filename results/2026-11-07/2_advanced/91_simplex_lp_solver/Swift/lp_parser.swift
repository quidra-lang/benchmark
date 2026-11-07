import Foundation
typealias F = Fraction
typealias Terms = [(String, F)]
struct ModelError: Error {
    let line: Int, message: String
}
struct Constraint {
    let line: Int, name: String, terms: Terms, comparison: String, rhs: F
}
enum BoundChange {
    case unchanged, infinite, finite(F)
}
struct Bound {
    let line: Int, name: String;
    var lower: BoundChange = .unchanged, upper: BoundChange = .unchanged
}
struct Parsed {
    var maximize = false, objective: Terms = [], constraints: [Constraint] = [], bounds: [Bound] = []
    var integers: [(Int, [String])] = [], binaries: [(Int, [String])] = []
}
struct Block {
    let name: String, parsed: Parsed?, error: ModelError?
}
struct Params {
    let level: Int, limit: Int;
    var levels: [String: Int] = [:], limits: [String: Int] = [:]
}
enum LPParser {
    static func name(_ text: String) -> Bool {
        guard let first = text.utf8.first, (97...122).contains(first) else {
            return false
        }
        return text.utf8.allSatisfy {
            (97...122).contains($0) || (48...57).contains($0) || $0 == 95
        } && !["bounds", "integer", "binary", "free", "inf"].contains(text)
    }
    static func expression(_ items: [String]) -> Terms? {
        var i = 0, sign = F(1), result: Terms = []
        if items.first == "-" {
            sign = -sign;
            i += 1
        }
        while true {
            if i >= items.count {
                return nil
            }
            let word = items[i], coefficient: F, variable: String
            if word.first == "-" {
                return nil
            }
            if let number = F.parse(word) {
                if i + 1 >= items.count || !name(items[i + 1]) {
                    return nil
                }
                coefficient = number;
                variable = items[i + 1];
                i += 2
            } else if name(word) {
                coefficient = F(1);
                variable = word;
                i += 1
            }
            else {
                return nil
            }
            result.append((variable, coefficient * sign))
            if i == items.count {
                return result
            }
            if items[i] == "+" {
                sign = F(1)
            } else if items[i] == "-" {
                sign = F(-1)
            } else {
                return nil
            }
            i += 1
        }
    }
    static func constraint(_ items: [String], _ line: Int) -> Constraint? {
        guard items.count >= 4, items[0].last == ":", name(String(items[0].dropLast())), ["<=", ">=", "="].contains(items[items.count - 2]), let terms = expression(Array(items[1..<(items.count - 2)])), let rhs = F.parse(items.last!) else {
            return nil
        }
        return Constraint(line: line, name: String(items[0].dropLast()), terms: terms, comparison: items[items.count - 2], rhs: rhs)
    }
    static func bound(_ items: [String], _ line: Int) -> Bound? {
        func lower(_ text: String) -> BoundChange? {
            text == "-inf" ? .infinite : F.parse(text).map {
                .finite($0)
            }
        }
        func upper(_ text: String) -> BoundChange? {
            text == "inf" ? .infinite : F.parse(text).map {
                .finite($0)
            }
        }
        if items.count == 2 && name(items[0]) && items[1] == "free" {
            return Bound(line: line, name: items[0], lower: .infinite, upper: .infinite)
        }
        if items.count == 3 && name(items[0]) {
            var bound = Bound(line: line, name: items[0])
            switch items[1] {
                case ">=": guard let value = lower(items[2]) else {
                    return nil
                };
                bound.lower = value
                case "<=": guard let value = upper(items[2]) else {
                    return nil
                };
                bound.upper = value
                case "=": guard let value = F.parse(items[2]) else {
                    return nil
                };
                bound.lower = .finite(value);
                bound.upper = .finite(value)
                default: return nil
            }
            return bound
        }
        if items.count == 5 && items[1] == "<=" && items[3] == "<=" && name(items[2]), let lo = lower(items[0]), let hi = upper(items[4]) {
            return Bound(line: line, name: items[2], lower: lo, upper: hi)
        }
        return nil
    }
    static func body(_ body: [(Int, String)], _ end: Int) throws -> Parsed {
        var result = Parsed(), state = 0
        for (line, text) in body {
            let items = text.split(separator: " ").map(String.init)
            var valid = false
            switch state {
                case 0: if text == "maximize" || text == "minimize" {
                    result.maximize = text == "maximize";
                    state = 1;
                    valid = true
                }
                case 1: if items.count >= 2 && items[0].last == ":" && name(String(items[0].dropLast())), let terms = expression(Array(items.dropFirst())) {
                    result.objective = terms;
                    state = 2;
                    valid = true
                }
                case 2: if text == "subject to" {
                    state = 3;
                    valid = true
                }
                case 3, 4:
                if state == 4 && ["bounds", "integer", "binary"].contains(text) {
                    state = text == "bounds" ? 5 : text == "integer" ? 6 : 7;
                    valid = true
                }
                else if let constraint = constraint(items, line) {
                    result.constraints.append(constraint);
                    state = 4;
                    valid = true
                }
                case 5:
                if text == "integer" || text == "binary" {
                    state = text == "integer" ? 6 : 7;
                    valid = true
                }
                else if let bound = bound(items, line) {
                    result.bounds.append(bound);
                    valid = true
                }
                case 6, 7:
                if state == 6 && text == "binary" {
                    state = 7;
                    valid = true
                }
                else if items.allSatisfy(name) {
                    if state == 6 {
                        result.integers.append((line, items))
                    } else {
                        result.binaries.append((line, items))
                    };
                    valid = true
                }
                default: break
            }
            if !valid {
                throw ModelError(line: line, message: "syntax error")
            }
        }
        if state < 4 {
            throw ModelError(line: end, message: "syntax error")
        }
        return result
    }
    static func read() -> [Block] {
        var result: [Block] = [], model = "", body: [(Int, String)] = []
        let lines = try! String(contentsOfFile: "input/models.lp", encoding: .ascii).components(separatedBy: "\n")
        for (i, line) in lines.enumerated() where !line.isEmpty && line.first != "#" {
            if line.hasPrefix("model ") {
                model = String(line.dropFirst(6));
                body = []
            }
            else if line == "end" {
                do {
                    result.append(Block(name: model, parsed: try self.body(body, i + 1), error: nil))
                }
                catch let error as ModelError {
                    result.append(Block(name: model, parsed: nil, error: error))
                }
                catch {
                    preconditionFailure()
                }
            } else {
                body.append((i + 1, line))
            }
        }
        return result
    }
    static func params() -> Params {
        let items = try! String(contentsOfFile: "input/params.txt", encoding: .ascii).split(separator: "\n").map {
            $0.split(separator: " ").map(String.init)
        }
        var result = Params(level: Int(items[0][1])!, limit: Int(items[1][1])!)
        for row in items.dropFirst(2) {
            if row[0] == "log" {
                result.levels[row[1]] = Int(row[2])!
            } else {
                result.limits[row[1]] = Int(row[2])!
            }
        }
        return result
    }
}
