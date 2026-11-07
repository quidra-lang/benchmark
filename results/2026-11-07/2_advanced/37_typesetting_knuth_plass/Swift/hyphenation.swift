func isLetter(_ character: Character) -> Bool {
    (character >= "A" && character <= "Z") || (character >= "a" && character <= "z")
}

struct SplitPoint {
    let position: Int
    let appendHyphen: Bool
}

struct Hyphenation {
    var words: [String: [Int]] = [:]
    let leftMinimum: Int
    let rightMinimum: Int

    init(lines: [String], additions: [String], leftMinimum: Int, rightMinimum: Int) {
        self.leftMinimum = leftMinimum
        self.rightMinimum = rightMinimum
        for spelling in lines + additions {
            let parts = spelling.split(separator: "-").map(String.init)
            var position = 0
            var points: [Int] = []
            for part in parts.dropLast() {
                position += part.count
                points.append(position)
            }
            words[parts.joined()] = points
        }
    }

    func splitPoints(_ word: String) -> [SplitPoint] {
        let characters = Array(word)
        var first = 0
        while first < characters.count && !isLetter(characters[first]) { first += 1 }
        var last = characters.count
        while last > first && !isLetter(characters[last - 1]) { last -= 1 }
        let core = String(characters[first..<last])
        var points: [Int: Bool] = [:]
        if !core.isEmpty && core.allSatisfy(isLetter) {
            for point in words[core.lowercased(), default: []]
                where point >= leftMinimum && core.count - point >= rightMinimum {
                points[first + point] = true
            }
        }
        if characters.count >= 3 {
            for position in 1..<(characters.count - 1)
                where characters[position] == "-" && isLetter(characters[position - 1])
                    && isLetter(characters[position + 1]) {
                points[position + 1] = false
            }
        }
        return points.keys.sorted().map { SplitPoint(position: $0, appendHyphen: points[$0]!) }
    }
}
