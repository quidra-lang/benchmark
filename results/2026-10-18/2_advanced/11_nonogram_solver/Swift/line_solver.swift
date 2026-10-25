let unknown = 0, filled = 1, empty = 2
func fitTable(_ cells: [Int], _ clue: [Int]) -> [[Bool]] {
    var empties = [0]
    for state in cells { empties.append(empties.last! + (state == empty ? 1 : 0)) }
    var table = Array(repeating: Array(repeating: false, count: clue.count + 1), count: cells.count + 1)
    table[0][0] = true
    for end in 1...cells.count {
        for count in 0...clue.count {
            var fits = cells[end - 1] != filled && table[end - 1][count]
            if !fits && count > 0 {
                let start = end - clue[count - 1]
                if start >= 0 && empties[end] == empties[start] { fits = start == 0 ? count == 1 : cells[start - 1] != filled && table[start - 1][count - 1] }
            }
            table[end][count] = fits
        }
    }
    return table
}
struct LinePlacements {
    let cells: [Int]
    let clue: [Int]
    let before: [[Bool]]
    let after: [[Bool]]
    init(_ cells: [Int], _ clue: [Int]) { self.cells = cells; self.clue = clue; before = fitTable(cells, clue); after = fitTable(Array(cells.reversed()), Array(clue.reversed())) }
    var consistent: Bool { before[cells.count][clue.count] }
    func canStart(_ block: Int, _ start: Int) -> Bool {
        let end = start + clue[block]
        if cells[start..<end].contains(empty) { return false }
        let left = start == 0 ? block == 0 : cells[start - 1] != filled && before[start - 1][block]
        let rest = clue.count - block - 1
        let right = end == cells.count ? rest == 0 : cells[end] != filled && after[cells.count - end - 1][rest]
        return left && right
    }
    func starts(_ block: Int) -> [Int] { (0...(cells.count - clue[block])).filter { canStart(block, $0) } }
    func canBeEmpty(_ index: Int) -> Bool { cells[index] != filled && (0...clue.count).contains { before[index][$0] && after[cells.count - index - 1][clue.count - $0] } }
}
func hasPlacement(_ cells: [Int], _ clue: [Int]) -> Bool { LinePlacements(cells, clue).consistent }
func solveLine(_ cells: [Int], _ clue: [Int], _ precise: Bool) -> [Int]? {
    let placements = LinePlacements(cells, clue)
    if !placements.consistent { return nil }
    var result = cells, fillable = Array(repeating: false, count: cells.count), covered = Array(repeating: false, count: cells.count)
    for (block, length) in clue.enumerated() {
        let starts = placements.starts(block)
        if precise { for start in starts { for index in start..<(start + length) { fillable[index] = true } } }
        else {
            let low = starts.first!, high = starts.last!
            if high < low + length { for index in high..<(low + length) where result[index] == unknown { result[index] = filled } }
            for index in low..<(high + length) { covered[index] = true }
        }
    }
    for index in cells.indices where result[index] == unknown {
        if precise { let emptiable = placements.canBeEmpty(index); if fillable[index] && !emptiable { result[index] = filled } else if emptiable && !fillable[index] { result[index] = empty } }
        else if !covered[index] { result[index] = empty }
    }
    return result
}
