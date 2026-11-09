func isWildcard(_ element: String) -> Bool {
    element == "*" || element == "#" || element.hasPrefix("@")
}

func matchPattern(_ pattern: [String], words: [String], groups: [String: Set<String>]) -> [[String]]? {
    var ends: [Int] = []
    func search(_ position: Int, _ start: Int) -> Bool {
        if position == pattern.count { return start == words.count }
        let element = pattern[position]
        let candidates: ClosedRange<Int>
        if element == "*" { candidates = start...words.count }
        else if start < words.count && (element == "#" || (element.hasPrefix("@") ? groups[String(element.dropFirst()), default: []].contains(words[start]) : element == words[start])) { candidates = (start + 1)...(start + 1) }
        else { return false }
        for end in candidates {
            ends.append(end)
            if search(position + 1, end) { return true }
            ends.removeLast()
        }
        return false
    }
    guard search(0, 0) else { return nil }
    var start = 0
    var bindings: [[String]] = []
    for index in pattern.indices {
        if isWildcard(pattern[index]) { bindings.append(Array(words[start..<ends[index]])) }
        start = ends[index]
    }
    return bindings
}

func patternCovers(_ earlier: [String], later: [String], groups: [String: Set<String>]) -> Bool {
    func elementCovers(_ element: String, _ other: String) -> Bool {
        if element == "#" { return other != "*" }
        if element.hasPrefix("@") {
            let members = groups[String(element.dropFirst())]!
            return other.hasPrefix("@") ? groups[String(other.dropFirst())]!.isSubset(of: members) : members.contains(other)
        }
        return element == other
    }
    func search(_ position: Int, _ start: Int) -> Bool {
        if position == earlier.count { return start == later.count }
        if earlier[position] == "*" { return (start...later.count).contains { search(position + 1, $0) } }
        return start < later.count && elementCovers(earlier[position], later[start]) && search(position + 1, start + 1)
    }
    return search(0, 0)
}
