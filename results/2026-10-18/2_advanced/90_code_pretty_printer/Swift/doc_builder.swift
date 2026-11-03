indirect enum Document {
    case text(String), line, softline, hardline, breakParent, suffix(String), ifBreak(String, String)
    case group(Int, Document), nest(Int, Document), align(Document), concat([Document])
    var forced: Bool {
        switch self {
            case .hardline, .breakParent: return true;
            case .concat(let parts): return parts.contains {
                $0.forced
            };
            case .group(_, let child), .nest(_, let child), .align(let child): return child.forced;
            default: return false
        }
    }
    var groupCount: Int {
        switch self {
            case .group(_, let child): return 1 + child.groupCount;
            case .nest(_, let child), .align(let child): return child.groupCount;
            case .concat(let parts): return parts.reduce(0) {
                $0 + $1.groupCount
            };
            default: return 0
        }
    }
}
func text(_ value: String) -> Document {
    .text(value)
}
func concat(_ parts: [Document]) -> Document {
    var result: [Document] = []
    func flatten(_ document: Document) {
        if case .concat(let children) = document {
            for child in children {
                flatten(child)
            }
        }
        else if case .text(let string) = document {
            if string.isEmpty {
                return
            }
            if let last = result.last, case .text(let previous) = last {
                result[result.count - 1] = .text(previous + string)
            }
            else {
                result.append(document)
            }
        } else {
            result.append(document)
        }
    }
    for part in parts {
        flatten(part)
    }
    return result.isEmpty ? .text("") : result.count == 1 ? result[0] : .concat(result)
}
func nest(_ n: Int, _ child: Document) -> Document {
    .nest(n, child)
}
func align(_ child: Document) -> Document {
    .align(child)
}
func line() -> Document {
    .line
}
func softline() -> Document {
    .softline
}
func hardline() -> Document {
    .hardline
}
func suffix(_ value: String) -> Document {
    .suffix(value)
}
func breakParent() -> Document {
    .breakParent
}
func ifBreak(_ broken: String, _ flat: String) -> Document {
    .ifBreak(broken, flat)
}
final class DocBuilder {
    var next = 0
    func group(_ child: Document) -> Document {
        let id = next;
        next += 1;
        return .group(id, child)
    }
}
