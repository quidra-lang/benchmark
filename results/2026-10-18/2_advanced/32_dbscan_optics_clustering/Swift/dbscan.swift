func dbscan(_ neighborhoods: [[Int]], _ minPts: Int) -> ([Int], [Bool]) {
    let core = neighborhoods.map { $0.count >= minPts }
    var labels = [Int](repeating: -2, count: neighborhoods.count)
    var label = 0
    for i in labels.indices {
        if labels[i] != -2 { continue }
        if !core[i] {
            labels[i] = -1
            continue
        }
        labels[i] = label
        var queue = neighborhoods[i]
        var front = 0
        while front < queue.count {
            let j = queue[front]
            front += 1
            if labels[j] == -1 {
                labels[j] = label
            } else if labels[j] == -2 {
                labels[j] = label
                if core[j] { queue += neighborhoods[j] }
            }
        }
        label += 1
    }
    return (labels, core)
}
