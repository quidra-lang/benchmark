import Foundation

func spaces(_ count: Int) -> String { String(repeating: " ", count: count) }

func trimRight(_ text: String) -> String {
    String(text.reversed().drop(while: { $0 == " " }).reversed())
}

func displayLine(_ pieces: [String], _ slack: Int, _ alignment: String, last: Bool) -> String {
    let pieces = pieces.map { $0.replacingOccurrences(of: "~", with: " ") }
    let text = pieces.joined(separator: " ")
    if slack <= 0 { return text }
    let gaps = pieces.count - 1
    if alignment == "justify" && !last && gaps > 0 {
        let quotient = slack / gaps
        let remainder = slack % gaps
        var result = pieces[0]
        for index in 0..<gaps { result += spaces(quotient + 1 + (index < remainder ? 1 : 0)) + pieces[index + 1] }
        return result
    }
    if alignment == "right" { return spaces(slack) + text }
    if alignment == "center" { return spaces(slack / 2) + text }
    return text
}

func formatTable(_ rows: [[String]], _ columns: String, _ caption: String, _ number: String) -> [String] {
    let alignments = Array(columns)
    let widths = alignments.indices.map { index in rows.map { $0[index].count }.max()! }
    var lines: [String] = []
    if !caption.isEmpty { lines.append("Table \(number). \(caption)") }
    for (rowIndex, row) in rows.enumerated() {
        let cells = row.indices.map { index -> String in
            let missing = widths[index] - row[index].count
            if alignments[index] == "l" { return row[index] + spaces(missing) }
            if alignments[index] == "r" { return spaces(missing) + row[index] }
            return spaces(missing / 2) + row[index] + spaces(missing - missing / 2)
        }
        lines.append(trimRight(cells.joined(separator: " | ")))
        if rowIndex == 0 { lines.append(widths.map { String(repeating: "-", count: $0) }.joined(separator: "-+-")) }
    }
    return lines
}

func runningHead(_ fields: [String], _ values: [(String, String)], _ width: Int, _ serial: Int) -> String {
    var expanded = fields.map { field -> String in
        var result = field
        for (name, value) in values { result = result.replacingOccurrences(of: "{\(name)}", with: value) }
        return result
    }
    if serial % 2 == 0 { expanded.swapAt(0, 2) }
    var line = Array(repeating: Character(" "), count: width)
    for (start, text) in [(0, expanded[0]), ((width - expanded[1].count) / 2, expanded[1]),
                          (width - expanded[2].count, expanded[2])] {
        for (offset, character) in text.enumerated() { line[start + offset] = character }
    }
    return trimRight(String(line))
}

func pagesText(_ pages: [Page]) -> String {
    var lines: [String] = []
    for page in pages {
        lines += ["--- page \(page.serial) ---", page.header, ""]
        lines += page.body
        lines += ["", page.footer]
    }
    return lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"
}
