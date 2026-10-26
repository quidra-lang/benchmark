import Foundation

private func norm(_ values: [Double], _ nodes: [Int]) -> Double {
    var squares = 0.0
    for node in nodes { squares += values[node] * values[node] }
    return sqrt(squares)
}

func hits(_ count: Int, _ nodes: [Int], _ links: [Link], _ iterations: Int) -> (authority: [Double], hub: [Double]) {
    var sources = Array(repeating: [Int](), count: count)
    var targets = Array(repeating: [Int](), count: count)
    for link in links.sorted() { sources[link.target].append(link.source); targets[link.source].append(link.target) }
    var authority = Array(repeating: 0.0, count: count)
    var hub = Array(repeating: 0.0, count: count)
    for node in nodes { authority[node] = 1; hub[node] = 1 }
    for _ in 0..<iterations {
        var incoming = Array(repeating: 0.0, count: count)
        var outgoing = Array(repeating: 0.0, count: count)
        for node in nodes { for source in sources[node] { incoming[node] += hub[source] } }
        for node in nodes { for target in targets[node] { outgoing[node] += incoming[target] } }
        let authorityNorm = norm(incoming, nodes)
        let hubNorm = norm(outgoing, nodes)
        for node in nodes { authority[node] = incoming[node] / authorityNorm; hub[node] = outgoing[node] / hubNorm }
    }
    return (authority, hub)
}
