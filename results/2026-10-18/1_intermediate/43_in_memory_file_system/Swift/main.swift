import Foundation

enum Kind: String { case directory = "d", file = "f", link = "l" }
enum Content { case directory([String: Node]), file([String]), link(String) }
final class Node {
    let inode: Int
    var modified: Int
    weak var parent: Node?
    var name = ""
    var content: Content
    init(_ inode: Int, _ modified: Int, _ content: Content) {
        self.inode = inode; self.modified = modified; self.content = content
    }
    var kind: Kind {
        switch content { case .directory: return .directory; case .file: return .file; case .link: return .link }
    }
    var entries: [String: Node] {
        get { guard case .directory(let entries) = content else { preconditionFailure("Expected directory") }; return entries }
        set { content = .directory(newValue) }
    }
    var lines: [String] {
        get { guard case .file(let lines) = content else { preconditionFailure("Expected file") }; return lines }
        set { content = .file(newValue) }
    }
    var target: String {
        guard case .link(let target) = content else { preconditionFailure("Expected link") }; return target
    }
    var size: Int {
        switch content {
        case .directory(let entries): return entries.count
        case .file(let lines): return lines.reduce(0) { $0 + $1.utf8.count + 1 }
        case .link(let target): return target.utf8.count
        }
    }
    var linkCount: Int { kind == .directory ? 2 + entries.values.filter { $0.kind == .directory }.count : 1 }
}
enum Reason: String {
    case missing = "No such file or directory", notDirectory = "Not a directory", tooManyLinks = "Too many levels of symbolic links"
}
enum Resolution {
    case found(Node), absent(Node, String), failure(Reason)
    var node: Node? { if case .found(let node) = self { return node }; return nil }
    var creation: (parent: Node, name: String)? { if case .absent(let parent, let name) = self { return (parent, name) }; return nil }
    var reason: String {
        switch self { case .found: return ""; case .absent: return Reason.missing.rawValue; case .failure(let reason): return reason.rawValue }
    }
}
struct Options { let flags: Set<Character>; let paths: [String] }
func options(_ arguments: [String]) -> Options {
    var flags = Set<Character>(), position = 0
    while position < arguments.count && arguments[position].hasPrefix("-") {
        flags.formUnion(arguments[position].dropFirst()); position += 1
    }
    return Options(flags: flags, paths: Array(arguments.dropFirst(position)))
}
func join(_ path: String, _ name: String) -> String { path == "/" ? "/" + name : path + "/" + name }
func lastComponent(_ path: String) -> String { String(path.split(separator: "/", omittingEmptySubsequences: false).last!) }
func invalidSource(_ name: String) -> Bool { name.isEmpty || name == "." || name == ".." }
func lower(_ text: String) -> String { String(decoding: text.utf8.map { 65 <= $0 && $0 <= 90 ? $0 + 32 : $0 }, as: UTF8.self) }
func globMatches(_ pattern: String, _ name: String) -> Bool {
    let bytes = Array(name.utf8)
    var previous = [Bool](repeating: false, count: bytes.count + 1)
    previous[0] = true
    for character in pattern.utf8 {
        var current = [Bool](repeating: false, count: previous.count)
        if character == 42 {
            current[0] = previous[0]
            for index in bytes.indices { current[index + 1] = previous[index + 1] || current[index] }
        } else {
            for index in bytes.indices { current[index + 1] = previous[index] && (character == 63 || character == bytes[index]) }
        }
        previous = current
    }
    return previous.last!
}

final class Shell {
    private let root: Node
    private var current: Node
    private var previous: String?
    private var clock = 0, nextInode = 2
    private let terminal: (String) -> Void
    init(_ terminal: @escaping (String) -> Void) {
        let root = Node(1, 0, .directory([:]))
        self.root = root; self.current = root; self.terminal = terminal
        root.parent = root
    }
    private func absolute(_ start: Node) -> String {
        var node = start, names = [String]()
        while node !== root { names.append(node.name); node = node.parent! }
        return "/" + names.reversed().joined(separator: "/")
    }
    private func descendant(_ start: Node, of ancestor: Node) -> Bool {
        var node = start
        while true {
            if node === ancestor { return true }
            if node === root { return false }
            node = node.parent!
        }
    }
    private func add(_ node: Node, to parent: Node, as name: String) {
        parent.entries[name] = node; parent.modified = clock
        node.parent = parent; node.name = name
    }
    @discardableResult private func create(_ content: Content, in parent: Node, as name: String) -> Node {
        let node = Node(nextInode, clock, content)
        nextInode += 1; add(node, to: parent, as: name)
        return node
    }
    private func detach(_ node: Node) {
        let parent = node.parent!
        parent.entries.removeValue(forKey: node.name); parent.modified = clock
    }
    private func write(_ node: Node, _ lines: [String], append: Bool = false) {
        node.lines = append ? node.lines + lines : lines
        node.modified = clock
    }
    private func resolve(_ path: String, follow: Bool = true, makeParents: Bool = false) -> Resolution {
        var expansions = 0
        func walk(_ text: String, from base: Node, finalLink: Bool, original: Bool) -> Resolution {
            var node = text.hasPrefix("/") ? root : base
            let components = text.split(separator: "/").map(String.init)
            for (index, name) in components.enumerated() {
                guard node.kind == .directory else { return .failure(.notDirectory) }
                if name == "." { continue }
                if name == ".." { node = node.parent!; continue }
                var child: Node
                if let found = node.entries[name] { child = found }
                else if original && makeParents && index + 1 < components.count { child = create(.directory([:]), in: node, as: name) }
                else { return original && index + 1 == components.count ? .absent(node, name) : .failure(.missing) }
                if child.kind == .link && (index + 1 < components.count || finalLink) {
                    expansions += 1
                    if expansions > 8 { return .failure(.tooManyLinks) }
                    let expanded = walk(child.target, from: node, finalLink: true, original: false)
                    guard let target = expanded.node else { return expanded }
                    child = target
                }
                node = child
            }
            return .found(node)
        }
        return walk(path, from: current, finalLink: follow, original: true)
    }
    private func clone(_ source: Node, into parent: Node, as name: String) {
        let content: Content = source.kind == .directory ? .directory([:]) : source.content
        let copy = create(content, in: parent, as: name)
        if source.kind == .directory {
            for name in source.entries.keys.sorted() { clone(source.entries[name]!, into: copy, as: name) }
        }
    }
    private func walkNodes(_ node: Node, _ path: String, depth: Int = 0, limit: Int = 1000, _ visit: (Node, String, Int) -> Void) {
        visit(node, path, depth)
        if node.kind == .directory && depth < limit {
            for name in node.entries.keys.sorted() { walkNodes(node.entries[name]!, join(path, name), depth: depth + 1, limit: limit, visit) }
        }
    }
    private func inputs(_ command: String, _ paths: [String], _ input: [String], _ consume: ([String], String?) -> Void) {
        if paths.isEmpty { consume(input, nil); return }
        for path in paths {
            let result = resolve(path)
            guard let node = result.node else { terminal(command + ": " + path + ": " + result.reason); continue }
            if node.kind == .directory { terminal(command + ": " + path + ": Is a directory") }
            else { consume(node.lines, path) }
        }
    }
    private func move(_ paths: [String]) {
        let destination = paths.last!
        if paths.count > 2 {
            guard resolve(destination).node?.kind == .directory else {
                terminal("mv: target '\(destination)' is not a directory"); return
            }
        }
        for sourcePath in paths.dropLast() {
            let basename = lastComponent(sourcePath)
            func problem(_ target: String, _ reason: String) { terminal("mv: cannot move '\(sourcePath)' to '\(target)': \(reason)") }
            if invalidSource(basename) { problem(destination, "Invalid argument"); continue }
            let sourceResult = resolve(sourcePath, follow: false)
            guard let source = sourceResult.node else { terminal("mv: cannot stat '\(sourcePath)': \(sourceResult.reason)"); continue }
            let parent: Node, name: String, target: String
            if let directory = resolve(destination).node, directory.kind == .directory {
                parent = directory; name = basename; target = join(destination, basename)
            } else {
                let result = resolve(destination, follow: false)
                if let node = result.node { parent = node.parent!; name = node.name }
                else if let creation = result.creation { parent = creation.parent; name = creation.name }
                else { problem(destination, result.reason); continue }
                target = destination
            }
            let existing = parent.entries[name]
            if source.kind == .directory && descendant(parent, of: source) {
                terminal("mv: cannot move '\(sourcePath)' to a subdirectory of itself, '\(target)'")
            } else if existing === source {
                terminal("mv: '\(sourcePath)' and '\(target)' are the same file")
            } else if let existing, source.kind == .directory && existing.kind != .directory {
                terminal("mv: cannot overwrite non-directory '\(target)' with directory '\(sourcePath)'")
            } else if existing?.kind == .directory && source.kind != .directory {
                terminal("mv: cannot overwrite directory '\(target)' with non-directory '\(sourcePath)'")
            } else if let existing, existing.kind == .directory && !existing.entries.isEmpty {
                problem(target, "Directory not empty")
            } else if existing === current {
                problem(target, "Device or resource busy")
            } else {
                if let existing { detach(existing) }
                detach(source); add(source, to: parent, as: name)
            }
        }
    }
    private func copy(_ parsed: Options) {
        let destination = parsed.paths.last!
        if parsed.paths.count > 2 {
            guard resolve(destination).node?.kind == .directory else {
                terminal("cp: target '\(destination)' is not a directory"); return
            }
        }
        for sourcePath in parsed.paths.dropLast() {
            let basename = lastComponent(sourcePath)
            func problem(_ target: String, _ reason: String) { terminal("cp: cannot copy '\(sourcePath)' to '\(target)': \(reason)") }
            if invalidSource(basename) { problem(destination, "Invalid argument"); continue }
            let sourceResult = resolve(sourcePath)
            guard let source = sourceResult.node else { terminal("cp: cannot stat '\(sourcePath)': \(sourceResult.reason)"); continue }
            if source.kind == .directory && !parsed.flags.contains("r") {
                terminal("cp: -r not specified; omitting directory '\(sourcePath)'"); continue
            }
            let destinationResult = resolve(destination)
            if destinationResult.node == nil && destinationResult.creation == nil { problem(destination, destinationResult.reason); continue }
            let target = destinationResult.node?.kind == .directory ? join(destination, basename) : destination
            let result = resolve(target, follow: source.kind != .directory)
            if source.kind == .directory {
                if result.node != nil { problem(target, "File exists") }
                else if let creation = result.creation {
                    if descendant(creation.parent, of: source) { terminal("cp: cannot copy a directory, '\(sourcePath)', into itself, '\(target)'") }
                    else { clone(source, into: creation.parent, as: creation.name) }
                } else { problem(target, result.reason) }
            } else if let creation = result.creation {
                create(.file(source.lines), in: creation.parent, as: creation.name)
            } else if let node = result.node {
                if node === source { terminal("cp: '\(sourcePath)' and '\(target)' are the same file") }
                else if node.kind == .directory { terminal("cp: cannot overwrite directory '\(target)' with non-directory '\(sourcePath)'") }
                else { write(node, source.lines) }
            } else { problem(target, result.reason) }
        }
    }
    private func listing(_ parsed: Options, _ output: (String) -> Void) {
        let paths = parsed.paths.isEmpty ? ["."] : parsed.paths
        for path in paths {
            let result = resolve(path, follow: !parsed.flags.contains("l"))
            guard let node = result.node else { terminal("ls: cannot access '\(path)': \(result.reason)"); continue }
            var list: [(name: String, node: Node)] = []
            if node.kind != .directory { list = [(path, node)] }
            else {
                if paths.count > 1 { output(path + ":") }
                if parsed.flags.contains("a") { list = [(".", node), ("..", node.parent!)] }
                for name in node.entries.keys.sorted() where parsed.flags.contains("a") || !name.hasPrefix(".") { list.append((name, node.entries[name]!)) }
                if parsed.flags.contains("t") {
                    list = list.enumerated().sorted {
                        $0.element.node.modified != $1.element.node.modified ? $0.element.node.modified > $1.element.node.modified : $0.offset < $1.offset
                    }.map { $0.element }
                }
                if parsed.flags.contains("r") { list.reverse() }
            }
            func numbers(_ item: Node) -> [String] { [item.linkCount, item.size, item.modified].map { String($0) } }
            var widths = [0, 0, 0]
            for entry in list {
                for (index, value) in numbers(entry.node).enumerated() { widths[index] = max(widths[index], value.count) }
            }
            for (name, item) in list {
                if !parsed.flags.contains("l") { output(name); continue }
                var row = item.kind == .file ? "-" : item.kind.rawValue
                for (index, value) in numbers(item).enumerated() { row += " " + String(repeating: " ", count: widths[index] - value.count) + value }
                row += " " + name
                if item.kind == .link { row += " -> " + item.target }
                output(row)
            }
        }
    }
    private func find(_ arguments: [String], _ output: (String) -> Void) {
        var position = arguments.first.map { !$0.hasPrefix("-") } == true ? 1 : 0
        let path = position == 1 ? arguments[0] : "."
        var pattern: String?, type: String?, limit = 1000
        while position < arguments.count {
            switch arguments[position] {
            case "-name": pattern = arguments[position + 1]
            case "-type": type = arguments[position + 1]
            default: limit = Int(arguments[position + 1])!
            }
            position += 2
        }
        let result = resolve(path)
        guard let node = result.node else { terminal("find: '\(path)': \(result.reason)"); return }
        walkNodes(node, path, limit: limit) { item, display, depth in
            let name = depth == 0 ? (path == "/" ? "/" : lastComponent(path)) : item.name
            if let pattern, !globMatches(pattern, name) { return }
            if let type, type != item.kind.rawValue { return }
            output(display)
        }
    }
    private func diskUsage(_ parsed: Options, _ output: (String) -> Void) {
        let paths = parsed.paths.isEmpty ? ["."] : parsed.paths
        func report(_ node: Node, _ path: String, show: Bool) -> Int {
            var usage = node.kind == .directory ? 0 : node.size
            if node.kind == .directory {
                for name in node.entries.keys.sorted() {
                    let child = node.entries[name]!
                    usage += report(child, join(path, name), show: show && !parsed.flags.contains("s") && (child.kind == .directory || parsed.flags.contains("a")))
                }
            }
            if show { output("\(usage) \(path)") }
            return usage
        }
        for path in paths {
            let result = resolve(path)
            if let node = result.node { _ = report(node, path, show: true) }
            else { terminal("du: cannot access '\(path)': \(result.reason)") }
        }
    }
    private func tree(_ parsed: Options, _ output: (String) -> Void) {
        let path = parsed.paths.first ?? "."
        let result = resolve(path)
        guard let node = result.node else { terminal("tree: \(path): \(result.reason)"); return }
        guard node.kind == .directory else { terminal("tree: \(path): Not a directory"); return }
        var directories = 0, files = 0
        func draw(_ node: Node, _ prefix: String) {
            let names = node.entries.keys.filter { parsed.flags.contains("a") || !$0.hasPrefix(".") }.sorted()
            for (index, name) in names.enumerated() {
                let child = node.entries[name]!, last = index + 1 == names.count
                output(prefix + (last ? "`-- " : "|-- ") + name + (child.kind == .link ? " -> " + child.target : ""))
                if child.kind == .directory { directories += 1; draw(child, prefix + (last ? "    " : "|   ")) }
                else { files += 1 }
            }
        }
        output(path); draw(node, "")
        output("\(directories) " + (directories == 1 ? "directory" : "directories") + ", \(files) " + (files == 1 ? "file" : "files"))
    }
    private func execute(_ text: String, _ input: [String], _ output: (String) -> Void) {
        let words = text.split(separator: " ").map(String.init)
        let command = words[0], arguments = Array(words.dropFirst()), parsed = options(arguments)
        switch command {
        case "pwd": output(absolute(current))
        case "echo": output(String(text.dropFirst(5)))
        case "cd":
            var path = arguments.first ?? "/"
            let old = path == "-"
            if old {
                guard let previous else { terminal("cd: OLDPWD not set"); return }
                path = previous
            }
            let result = resolve(path)
            if let node = result.node {
                if node.kind != .directory { terminal("cd: \(path): Not a directory") }
                else {
                    previous = absolute(current); current = node
                    if old { output(absolute(current)) }
                }
            } else { terminal("cd: \(path): \(result.reason)") }
        case "mkdir":
            for path in parsed.paths {
                let result = resolve(path, follow: false, makeParents: parsed.flags.contains("p"))
                if let creation = result.creation { create(.directory([:]), in: creation.parent, as: creation.name) }
                else if result.node == nil { terminal("mkdir: cannot create directory '\(path)': \(result.reason)") }
                else if !parsed.flags.contains("p") || resolve(path).node?.kind != .directory { terminal("mkdir: cannot create directory '\(path)': File exists") }
            }
        case "touch":
            for path in arguments {
                let result = resolve(path)
                if let creation = result.creation { create(.file([]), in: creation.parent, as: creation.name) }
                else if let node = result.node { node.modified = clock }
                else { terminal("touch: cannot touch '\(path)': \(result.reason)") }
            }
        case "ls": listing(parsed, output)
        case "stat":
            for path in arguments {
                let result = resolve(path, follow: false)
                guard let node = result.node else { terminal("stat: cannot stat '\(path)': \(result.reason)"); continue }
                let type = node.kind == .directory ? "directory" : node.kind == .link ? "symbolic link" : node.lines.isEmpty ? "regular empty file" : "regular file"
                output("\(path): \(type), size \(node.size), inode \(node.inode), links \(node.linkCount), modified \(node.modified)")
            }
        case "rm":
            for path in parsed.paths {
                func problem(_ reason: String) { terminal("rm: cannot remove '\(path)': \(reason)") }
                let name = lastComponent(path)
                if name == "." || name == ".." { terminal("rm: refusing to remove '.' or '..' directory: skipping '\(path)'"); continue }
                let result = resolve(path, follow: false)
                guard let node = result.node else {
                    if !(parsed.flags.contains("f") && result.reason == Reason.missing.rawValue) { problem(result.reason) }
                    continue
                }
                if node.kind == .directory && !parsed.flags.contains("r") { problem("Is a directory") }
                else if descendant(current, of: node) { problem("Device or resource busy") }
                else { detach(node) }
            }
        case "rmdir":
            for path in arguments {
                func problem(_ reason: String) { terminal("rmdir: failed to remove '\(path)': \(reason)") }
                let name = lastComponent(path)
                if name == "." || name == ".." { problem("Invalid argument"); continue }
                let result = resolve(path, follow: false)
                guard let node = result.node else { problem(result.reason); continue }
                if node.kind != .directory { problem("Not a directory") }
                else if descendant(current, of: node) { problem("Device or resource busy") }
                else if !node.entries.isEmpty { problem("Directory not empty") }
                else { detach(node) }
            }
        case "mv": move(arguments)
        case "cp": copy(parsed)
        case "ln":
            let path = arguments[2], result = resolve(path, follow: false)
            if let creation = result.creation { create(.link(arguments[1]), in: creation.parent, as: creation.name) }
            else { terminal("ln: failed to create symbolic link '\(path)': " + (result.node == nil ? result.reason : "File exists")) }
        case "readlink", "realpath":
            let path = arguments[0], result = resolve(path, follow: command == "realpath")
            guard let node = result.node else { terminal("\(command): \(path): \(result.reason)"); return }
            if command == "realpath" { output(absolute(node)) }
            else if node.kind == .link { output(node.target) }
            else { terminal("readlink: \(path): Invalid argument") }
        case "find": find(arguments, output)
        case "du": diskUsage(parsed, output)
        case "tree": tree(parsed, output)
        case "cat", "wc", "head", "tail", "grep", "sort", "uniq": textCommand(command, arguments, input, output)
        default: terminal(command + ": command not found")
        }
    }
    private func numericValue(_ text: String) -> Int {
        var iterator = text.utf8.makeIterator(), byte = iterator.next()
        let negative = byte == 45
        if negative { byte = iterator.next() }
        var value = 0
        while let digit = byte, 48 <= digit && digit <= 57 {
            value = value * 10 + Int(digit - 48); byte = iterator.next()
        }
        return negative ? -value : value
    }
    private func textCommand(_ command: String, _ arguments: [String], _ input: [String], _ output: (String) -> Void) {
        let parsed = options(arguments), flags = parsed.flags
        var paths = parsed.paths
        if command == "grep" {
            var pattern = paths.removeFirst()
            if flags.contains("i") { pattern = lower(pattern) }
            let named = paths.count > 1 || flags.contains("r")
            func consume(_ lines: [String], _ name: String?) {
                let prefix = named ? name! + ":" : ""
                var count = 0
                for (index, line) in lines.enumerated() {
                    let comparison = flags.contains("i") ? lower(line) : line
                    if comparison.contains(pattern) != flags.contains("v") {
                        count += 1
                        if !flags.contains("c") { output(prefix + (flags.contains("n") ? "\(index + 1):" : "") + line) }
                    }
                }
                if flags.contains("c") { output(prefix + String(count)) }
            }
            if !flags.contains("r") { inputs(command, paths, input, consume) }
            else {
                if paths.isEmpty { paths = ["."] }
                for path in paths {
                    let result = resolve(path)
                    guard let node = result.node else { terminal("grep: \(path): \(result.reason)"); continue }
                    walkNodes(node, path) { item, display, _ in
                        if item.kind == .file { consume(item.lines, display) }
                    }
                }
            }
            return
        }
        if command == "sort" {
            var lines: [String] = []
            inputs(command, paths, input) { part, _ in lines.append(contentsOf: part) }
            lines.sort { left, right in
                if flags.contains("n") {
                    let a = numericValue(left), b = numericValue(right)
                    if a != b { return a < b }
                }
                return left < right
            }
            if flags.contains("r") { lines.reverse() }
            for line in lines { output(line) }
            return
        }
        var countText = "10"
        if command == "head" || command == "tail" {
            let offset = arguments.first == "-n" ? 2 : 0
            if offset != 0 { countText = arguments[1] }
            paths = Array(arguments.dropFirst(offset))
        }
        var totals = [0, 0, 0]
        let selected = Array("lwc").map { flags.isEmpty || flags.contains($0) }
        func reportCounts(_ counts: [Int], _ name: String?) {
            let values = counts.indices.filter { selected[$0] }.map { String(counts[$0]) }.joined(separator: " ")
            output(values + (name.map { " " + $0 } ?? ""))
        }
        inputs(command, paths, input) { lines, name in
            switch command {
            case "cat":
                for line in lines { output(line) }
            case "wc":
                var counts = [lines.count, 0, 0]
                for line in lines {
                    counts[1] += line.split(separator: " ").count; counts[2] += line.utf8.count + 1
                }
                for index in counts.indices { totals[index] += counts[index] }
                reportCounts(counts, name)
            case "head", "tail":
                let signed = countText.hasPrefix("-") || countText.hasPrefix("+")
                let count = Int(signed ? String(countText.dropFirst()) : countText)!
                var begin = 0, end = lines.count
                if command == "head" { end = countText.hasPrefix("-") ? max(0, end - count) : min(end, count) }
                else { begin = countText.hasPrefix("+") ? min(end, max(0, count - 1)) : max(0, end - count) }
                for index in begin..<end { output(lines[index]) }
            default:
                var begin = 0
                while begin < lines.count {
                    var end = begin + 1
                    while end < lines.count && lines[end] == lines[begin] { end += 1 }
                    output((flags.contains("c") ? "\(end - begin) " : "") + lines[begin]); begin = end
                }
            }
        }
        if command == "wc" && paths.count > 1 { reportCounts(totals, "total") }
    }
    func process(_ line: String) {
        clock += 1; terminal(absolute(current) + "$ " + line)
        let appendRange = line.range(of: " >> ")
        let redirect = appendRange ?? line.range(of: " > ")
        var redirectFile: Node?
        var pipeline = line
        if let redirect {
            let path = String(line[redirect.upperBound...])
            pipeline = String(line[..<redirect.lowerBound])
            let result = resolve(path)
            if let creation = result.creation { redirectFile = create(.file([]), in: creation.parent, as: creation.name) }
            else if let node = result.node {
                if node.kind == .directory { terminal("sh: \(path): Is a directory"); return }
                redirectFile = node
                if appendRange == nil { write(node, []) }
            } else { terminal("sh: \(path): \(result.reason)"); return }
        }
        let commands = pipeline.components(separatedBy: " | ")
        var input: [String] = []
        for (index, command) in commands.enumerated() {
            var output: [String] = []
            execute(command, input) { text in
                if index + 1 == commands.count && redirectFile == nil { terminal(text) }
                else { output.append(text) }
            }
            input = output
        }
        if let redirectFile, !input.isEmpty { write(redirectFile, input, append: true) }
    }
}

let shell = Shell { print($0) }
while let line = readLine(), line != "exit" { shell.process(line) }
