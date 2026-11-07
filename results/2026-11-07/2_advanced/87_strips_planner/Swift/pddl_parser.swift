import Foundation
indirect enum Expr {
    case word(String), list([Expr])
    var word: String {
        if case .word(let text) = self {
            return text
        };
        preconditionFailure()
    }
    var list: [Expr] {
        if case .list(let values) = self {
            return values
        };
        preconditionFailure()
    }
}
struct Atom: Hashable {
    let predicate: String, terms: [String]
    init(_ predicate: String, _ terms: [String]) {
        self.predicate = predicate;
        self.terms = terms
    }
    init(_ expr: Expr) {
        let a = expr.list;
        predicate = a[0].word;
        terms = a.dropFirst().map(\.word)
    }
    var text: String {
        "(" + ([predicate] + terms).joined(separator: " ") + ")"
    }
    func replace(_ values: [String: String]) -> Self {
        Self(predicate, terms.map {
            values[$0]!
        })
    }
}
struct Literal {
    let atom: Atom, negative: Bool
    var text: String {
        negative ? "(not \(atom.text))" : atom.text
    }
    func replace(_ values: [String: String]) -> Self {
        Self(atom: atom.replace(values), negative: negative)
    }
}
struct Schema {
    let name: String;
    var parameters: [(String, String)] = [], pre: [Literal] = [], effects: [Literal] = [];
    var cost = 1
}
struct Predicate {
    let name: String, types: [String]
}
final class Domain {
    let name: String
    var typeOrder = ["object"], parents: [String: String] = [:], predicates: [Predicate] = [], actions: [Schema] = [], diagnostics: [String] = []
    init(_ name: String) {
        self.name = name
    }
}
final class Problem {
    let name: String
    var objects: [(String, String)] = [], initial: [Atom] = [], goals: [Atom] = [], diagnostics: [String] = []
    init(_ name: String) {
        self.name = name
    }
}
enum PDDLParser {
    static func expressions(_ path: String) -> [Expr] {
        let text = try! String(contentsOfFile: path, encoding: .ascii)
        var tokens: [String] = []
        for line in text.components(separatedBy: "\n") {
            var word = ""
            for c in line.prefix(while: {
                $0 != ";"
            }) {
                if c == "(" || c == ")" || c == " " {
                    if !word.isEmpty {
                        tokens.append(word);
                        word = ""
                    }
                    if c != " " {
                        tokens.append(String(c))
                    }
                } else {
                    word.append(c)
                }
            }
            if !word.isEmpty {
                tokens.append(word)
            }
        }
        var i = 0
        func read() -> Expr {
            let token = tokens[i];
            i += 1
            if token != "(" {
                return .word(token)
            }
            var children: [Expr] = []
            while tokens[i] != ")" {
                children.append(read())
            }
            i += 1
            return .list(children)
        }
        var result: [Expr] = []
        while i < tokens.count {
            result.append(read())
        }
        return result
    }
    static func typed(_ words: [Expr]) -> [(String, String)] {
        var result: [(String, String)] = [], pending: [String] = [], i = 0
        while i < words.count {
            if words[i].word == "-" {
                i += 1;
                result += pending.map {
                    ($0, words[i].word)
                };
                pending = []
            }
            else {
                pending.append(words[i].word)
            }
            i += 1
        }
        return result + pending.map {
            ($0, "object")
        }
    }
    static func conjunction(_ expr: Expr) -> [Expr] {
        let a = expr.list;
        return a[0].word == "and" ? Array(a.dropFirst()) : [expr]
    }
    static func literal(_ expr: Expr) -> Literal {
        let a = expr.list
        return a[0].word == "not" ? Literal(atom: Atom(a[1]), negative: true) : Literal(atom: Atom(expr), negative: false)
    }
    static func domain() -> Domain {
        let a = expressions("input/domain.txt")[0].list, domain = Domain(a[1].list[1].word)
        for expr in a.dropFirst(2) {
            let s = expr.list
            switch s[0].word {
                case ":types":
                for word in s.dropFirst() where word.word != "-" && !domain.typeOrder.contains(word.word) {
                    domain.typeOrder.append(word.word)
                    if word.word != "object" {
                        domain.parents[word.word] = "object"
                    }
                }
                for (name, type) in typed(Array(s.dropFirst())) {
                    domain.parents[name] = type
                }
                case ":predicates":
                for expr in s.dropFirst() {
                    let p = expr.list;
                    domain.predicates.append(Predicate(name: p[0].word, types: typed(Array(p.dropFirst())).map {
                        $0.1
                    }))
                }
                case ":action":
                var action = Schema(name: s[1].word), i = 2
                while i < s.count {
                    switch s[i].word {
                        case ":parameters": action.parameters = typed(s[i + 1].list)
                        case ":precondition": action.pre = conjunction(s[i + 1]).map(literal)
                        default:
                        for effect in conjunction(s[i + 1]) {
                            if effect.list[0].word == "increase" {
                                action.cost = Int(effect.list[2].word)!
                            }
                            else {
                                action.effects.append(literal(effect))
                            }
                        }
                    }
                    i += 2
                }
                domain.actions.append(action)
                default: break
            }
        }
        return domain
    }
    static func problems() -> [Problem] {
        expressions("input/problems.txt").map {
            expr in
            let a = expr.list, problem = Problem(a[1].list[1].word)
            for section in a.dropFirst(2) {
                let s = section.list
                switch s[0].word {
                    case ":objects": problem.objects = typed(Array(s.dropFirst()))
                    case ":init": problem.initial = s.dropFirst().map(Atom.init)
                    case ":goal": problem.goals = conjunction(s[1]).map(Atom.init)
                    default: break
                }
            }
            return problem
        }
    }
}
