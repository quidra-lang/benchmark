import Foundation

func curveLines(_ groups: [String], _ collections: [String: [Subject]], _ estimates: [String: [KMRow]],
                _ width: Int, _ height: Int, _ timeLimit: Int) -> [String] {
    var cells = Array(repeating: Array(repeating: Set<Int>(), count: width), count: height)
    let step = timeLimit / width
    for (index, group) in groups.enumerated() {
        let maximum = collections[group]!.map { $0.time }.max()!
        var previous: Int?
        for column in 0..<width {
            let time = column * step
            if time > maximum { break }
            let survival = rowAt(estimates[group]!, time).survival
            let band = min(height - 1, Int(floor(survival * Double(height))))
            cells[band][column].insert(index)
            if let previous, previous - 1 > band {
                for vertical in (band + 1)..<previous { cells[vertical][column].insert(index) }
            }
            previous = band
        }
    }
    let border = "   +" + String(repeating: "-", count: width) + "+"
    var lines = [border]
    for band in (0..<height).reversed() {
        let characters = cells[band].map { cell -> String in
            if cell.isEmpty { return " " }
            return cell.count == 1 ? String(UnicodeScalar(65 + cell.first!)!) : "*"
        }.joined()
        let label = String(100 * band / height)
        lines.append(String(repeating: " ", count: 3 - label.count) + label + "|" + characters + "|")
    }
    lines.append(border)
    return lines
}
