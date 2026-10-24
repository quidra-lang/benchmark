func courses(_ original: [String], _ edges: [(String,String)], _ showCycle: Bool) {
    let names = original.sorted(), n = names.count
    var degree = [Int](repeating: 0, count: n)
    var graph = [[Bool]](repeating: [Bool](repeating: false, count: n), count: n)
    for (source,target) in edges {
        let a = names.firstIndex(of: source)!, b = names.firstIndex(of: target)!
        graph[a][b] = true
        degree[b] += 1
    }
    var taken = [Bool](repeating: false, count: n), order = [String]()
    while let next = names.indices.first(where: { !taken[$0] && degree[$0] == 0 }) {
        taken[next] = true
        order.append(names[next])
        for i in names.indices where graph[next][i] { degree[i] -= 1 }
    }
    print("order: \(order.joined(separator: " -> "))")
    if showCycle {
        let remaining = names.indices.filter { !taken[$0] }.map { names[$0] }
        print("cycle: \(remaining.joined(separator: " "))")
    }
}
courses(["physics","algebra","graphics","programming","statistics","calculus","databases","algorithms"], [("calculus","physics"),
    ("algebra","calculus"),
    ("programming","algorithms"),
    ("algebra","statistics"),
    ("algorithms","databases"),
    ("statistics","databases"),
    ("calculus","graphics"),
    ("algorithms","graphics"),
    ("physics","graphics")],false)
courses(["music","ecology","art","geology","biology","chemistry"], [("music","art"),
    ("art","ecology"),
    ("biology","chemistry"),
    ("chemistry","ecology"),
    ("ecology","geology"),
    ("geology","chemistry")],true)
