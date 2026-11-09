import Foundation

func orderedChildren(_ merges: [Merge], _ n: Int) -> [(Int, Int)] {
    var minimum = Array(0..<n)
    var children: [(Int, Int)] = []
    for merge in merges {
        children.append(minimum[merge.a] < minimum[merge.b] ? (merge.a, merge.b) : (merge.b, merge.a))
        minimum.append(min(minimum[merge.a], minimum[merge.b]))
    }
    return children
}

func leafOrder(_ children: [(Int, Int)], _ n: Int) -> [Int] {
    var order: [Int] = [], pending = [n + children.count - 1]
    while let node = pending.popLast() {
        if node < n { order.append(node) }
        else { pending.append(children[node - n].1); pending.append(children[node - n].0) }
    }
    return order
}

func column(_ height: Double, _ maximum: Double, _ width: Int) -> Int {
    let position = floor(height / maximum * Double(width))
    return position > Double(width) ? width + 1 : Int(position)
}

func dendrogramRows(_ merges: [Merge], _ children: [(Int, Int)], _ order: [Int], _ ids: [String], _ labels: [String], _ maximum: Double, _ cuts: [Int], _ width: Int) -> [String] {
    let n = order.count
    var grid = Array(repeating: Array(repeating: 0, count: width + 1), count: n)
    var anchors = Array(repeating: 0, count: 2 * n - 1)
    for (row, leaf) in order.enumerated() { anchors[leaf] = row }
    for x in cuts where x <= width { for row in 0..<n { grid[row][x] = max(grid[row][x], 1) } }
    let columns = merges.map { column($0.height, maximum, width) }
    for (step, pair) in children.enumerated() {
        let (upper, lower) = pair, x = columns[step]
        grid[anchors[upper]][x] = 4
        grid[anchors[lower]][x] = 4
        if anchors[upper] + 1 < anchors[lower] {
            for row in (anchors[upper] + 1)..<anchors[lower] { grid[row][x] = max(grid[row][x], 3) }
        }
        for child in [upper, lower] {
            let start = child < n ? 0 : columns[child - n] + 1
            if start < x { for position in start..<x { grid[anchors[child]][position] = max(grid[anchors[child]][position], 2) } }
        }
        anchors[n + step] = (anchors[upper] + anchors[lower]) / 2
    }
    let idWidth = ids.map(\.count).max()!, labelWidth = labels.map(\.count).max()!
    let marks = Array(" :-|+")
    var rows: [String] = []
    for (row, leaf) in order.enumerated() {
        let cells = String(grid[row].map { marks[$0] })
        var line = ids[leaf].padding(toLength: idWidth, withPad: " ", startingAt: 0) + " " + labels[leaf].padding(toLength: labelWidth, withPad: " ", startingAt: 0) + " " + cells
        while line.last == " " { line.removeLast() }
        rows.append(line)
    }
    rows.append(String(repeating: " ", count: idWidth + labelWidth + 2) + String((0...width).map { $0 % 10 == 0 ? Character("+") : Character("-") }))
    return rows
}
