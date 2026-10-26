struct GridState {
    var letters: [UInt8]
    var words: [Int?]
    var used: Set<Int> = []
    init(_ letters: [UInt8], _ count: Int) { self.letters = letters; words = Array(repeating: nil, count: count) }
    func pattern(_ slot: Slot) -> [UInt8] { slot.cells.map { letters[$0] } }
    mutating func assign(_ slot: Slot, _ id: Int, _ index: WordIndex) -> [Int] {
        var filled: [Int] = []
        for (cell, letter) in zip(slot.cells, index.words[id].letters) {
            if letters[cell] == 46 { letters[cell] = letter; filled.append(cell) }
        }
        words[slot.index] = id
        used.insert(id)
        return filled
    }
    mutating func unassign(_ slot: Slot, _ filled: [Int]) {
        for cell in filled { letters[cell] = 46 }
        used.remove(words[slot.index]!)
        words[slot.index] = nil
    }
}
private enum SearchResult: Equatable { case complete, fail, abort }
final class Attempt {
    var state: GridState
    let minimum: Int
    let budget: Int
    var nodes = 0
    var backtracks = 0
    var prunes = 0
    var deadEnds = 0
    var sequence: [Int] = []
    var maxDepth = 0
    var best: GridState
    var failures: [Int]
    var trace: [String] = []
    var outcome = ""
    init(_ initial: GridState, _ minimum: Int, _ budget: Int) {
        state = initial
        self.minimum = minimum
        self.budget = budget
        best = initial
        failures = Array(repeating: 0, count: initial.words.count)
    }
    func run(_ layout: Layout, _ index: WordIndex) {
        switch search(layout, index) {
        case .complete: outcome = "filled"
        case .fail: outcome = "unfillable"
        case .abort: outcome = "budget"
        }
    }
    var finalState: GridState { outcome == "filled" ? state : best }
    private func candidates(_ slot: Slot, _ index: WordIndex) -> [Int] { index.candidates(state.pattern(slot), minimum, state.used) }
    private func search(_ layout: Layout, _ index: WordIndex) -> SearchResult {
        var chosen: (number: Int, words: [Int])? = nil
        for slot in layout.slots {
            if state.words[slot.index] != nil { continue }
            let words = candidates(slot, index)
            if chosen == nil || words.count < chosen!.words.count { chosen = (slot.index, words) }
        }
        guard let chosen else { return .complete }
        if chosen.words.isEmpty { deadEnds += 1; failures[chosen.number] += 1; return .fail }
        let slot = layout.slots[chosen.number]
        for word in chosen.words {
            if nodes == budget { return .abort }
            nodes += 1
            let filled = state.assign(slot, word, index)
            sequence.append(chosen.number)
            let wiped = slot.crossings.first { state.words[$0] == nil && candidates(layout.slots[$0], index).isEmpty }
            if nodes <= 10 { trace.append(slot.label + "=" + index.words[word].text + (wiped == nil ? "" : "!")) }
            let result: SearchResult
            if let wiped { prunes += 1; failures[wiped] += 1; result = .fail }
            else {
                if sequence.count > maxDepth { maxDepth = sequence.count; best = state }
                result = search(layout, index)
            }
            if result != .fail { return result }
            state.unassign(slot, filled)
            sequence.removeLast()
            backtracks += 1
        }
        return .fail
    }
}
