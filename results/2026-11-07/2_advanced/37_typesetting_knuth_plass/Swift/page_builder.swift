enum LayoutKind {
    case heading, solid, flow
}

struct LayoutBlock {
    let kind: LayoutKind
    let lines: [LayoutLine]
    let list: Bool
    let pageBreak: Bool
}

struct PageBoundary {
    let end: Int
    let nextStart: Int
    let forced: Bool
}

func buildSequence(_ blocks: [LayoutBlock], _ orphanLines: Int,
                   _ widowLines: Int) -> (lines: [LayoutLine], boundaries: [PageBoundary]) {
    var lines: [LayoutLine] = []
    var boundaries: [PageBoundary] = []
    for (index, block) in blocks.enumerated() {
        let start = lines.count
        lines += block.lines
        if block.kind == .flow && block.lines.count > 1 {
            for kept in 1..<block.lines.count
                where kept >= orphanLines && block.lines.count - kept >= widowLines {
                boundaries.append(PageBoundary(end: start + kept, nextStart: start + kept, forced: false))
            }
        }
        if index + 1 == blocks.count {
            boundaries.append(PageBoundary(end: lines.count, nextStart: lines.count, forced: true))
            continue
        }
        let following = blocks[index + 1]
        let end = lines.count
        if !(block.list && following.list) { lines.append(LayoutLine("")) }
        if following.pageBreak || block.kind != .heading {
            boundaries.append(PageBoundary(end: end, nextStart: lines.count, forced: following.pageBreak))
        }
    }
    return (lines, boundaries)
}

func choosePages(_ blocks: [LayoutBlock], _ footnoteHeights: [Int: Int], _ height: Int,
                 _ orphanLines: Int, _ widowLines: Int) -> [Page] {
    let sequence = buildSequence(blocks, orphanLines, widowLines)
    var pages: [Page] = []
    var start = 0
    var firstBoundary = 0
    while start < sequence.lines.count {
        var notes: Set<Int> = []
        var noteHeight = 0
        var scanned = start
        var chosen: (index: Int, boundary: PageBoundary, used: Int, notes: [Int])?
        for index in firstBoundary..<sequence.boundaries.count {
            let boundary = sequence.boundaries[index]
            while scanned < boundary.end {
                for number in sequence.lines[scanned].footnotes where !notes.contains(number) {
                    notes.insert(number)
                    noteHeight += footnoteHeights[number]!
                }
                scanned += 1
            }
            let used = boundary.end - start + noteHeight + (notes.isEmpty ? 0 : 1)
            if used > height { break }
            chosen = (index, boundary, used, notes.sorted())
            if boundary.forced { break }
        }
        let selection = chosen!
        pages.append(Page(content: Array(sequence.lines[start..<selection.boundary.end]),
                          footnotes: selection.notes, height: selection.used, endsByForce: selection.boundary.forced))
        start = selection.boundary.nextStart
        firstBoundary = selection.index + 1
    }
    return pages
}
