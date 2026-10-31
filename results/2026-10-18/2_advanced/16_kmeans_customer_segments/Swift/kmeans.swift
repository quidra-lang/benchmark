func squaredDistance(_ first: [Double], _ second: [Double]) -> Double {
    var total = 0.0
    for (a, b) in zip(first, second) {
        let difference = a - b
        total += difference * difference
    }
    return total
}

func assign(_ points: [Point], _ centers: [Point]) -> (labels: [Int], errors: [Double]) {
    var labels: [Int] = []
    var errors: [Double] = []
    for point in points {
        var best = 0
        var bestDistance = squaredDistance(point, centers[0])
        for index in centers.indices.dropFirst() {
            let distance = squaredDistance(point, centers[index])
            if distance < bestDistance { best = index; bestDistance = distance }
        }
        labels.append(best)
        errors.append(bestDistance)
    }
    return (labels, errors)
}

func meanPoint(_ points: [Point]) -> Point {
    var totals = Array(repeating: 0.0, count: points[0].count)
    for point in points { for (index, value) in point.enumerated() { totals[index] += value } }
    return totals.map { $0 / Double(points.count) }
}

func clusterSizes(_ labels: [Int], _ k: Int) -> [Int] {
    var sizes = Array(repeating: 0, count: k)
    for label in labels { sizes[label] += 1 }
    return sizes
}

func clusterCenter(_ points: [Point], _ labels: [Int], _ cluster: Int) -> Point {
    meanPoint(points.indices.filter { labels[$0] == cluster }.map { points[$0] })
}

func clusterCenters(_ points: [Point], _ labels: [Int], _ k: Int) -> [Point] {
    (0..<k).map { clusterCenter(points, labels, $0) }
}

func refill(_ labels: inout [Int], _ errors: inout [Double], _ k: Int) -> Int {
    var sizes = clusterSizes(labels, k)
    var reseeds = 0
    for cluster in 0..<k {
        if sizes[cluster] > 0 { continue }
        var chosen: Int?
        for (index, label) in labels.enumerated() {
            if sizes[label] >= 2 && (chosen == nil || errors[index] > errors[chosen!]) { chosen = index }
        }
        let index = chosen!
        sizes[labels[index]] -= 1
        sizes[cluster] += 1
        labels[index] = cluster
        errors[index] = 0
        reseeds += 1
    }
    return reseeds
}

struct LloydResult {
    let labels: [Int]
    let centers: [Point]
    let iterations: Int
    let converged: Bool
    let reseeds: Int
}

func runLloyd(_ points: [Point], _ initial: [Point], _ maximum: Int) -> LloydResult {
    let k = initial.count
    let assigned = assign(points, initial)
    var labels = assigned.labels
    var errors = assigned.errors
    var iterations = 0
    var reseeds = 0
    var converged = false
    while iterations < maximum && !converged {
        reseeds += refill(&labels, &errors, k)
        let centers = clusterCenters(points, labels, k)
        iterations += 1
        let next = assign(points, centers)
        converged = next.labels == labels
        labels = next.labels
        errors = next.errors
    }
    reseeds += refill(&labels, &errors, k)
    return LloydResult(labels: labels, centers: clusterCenters(points, labels, k), iterations: iterations,
        converged: converged, reseeds: reseeds)
}

func withinSSE(_ points: [Point], _ labels: [Int], _ centers: [Point]) -> Double {
    var total = 0.0
    for (point, label) in zip(points, labels) { total += squaredDistance(point, centers[label]) }
    return total
}
