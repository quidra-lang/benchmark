let matches = ["Lions 0-3 Bears",
    "Tigers 2-2 Wolves",
    "Eagles 4-0 Sharks",
    "Bears 0-1 Sharks",
    "Wolves 2-1 Eagles",
    "Lions 0-1 Tigers",
    "Tigers 3-3 Bears",
    "Eagles 2-2 Lions",
    "Sharks 2-2 Wolves",
    "Bears 3-1 Wolves",
    "Lions 2-0 Sharks",
    "Tigers 2-1 Eagles",
    "Eagles 1-0 Bears",
    "Sharks 2-0 Tigers",
    "Wolves 2-1 Lions"]
let names = ["Lions","Tigers","Eagles","Sharks","Wolves","Bears"]
var stats = [[Int]](repeating: [Int](repeating: 0, count: 6), count: 6)
for match in matches {
    let parts = match.split(separator: " ").map(String.init)
    let goals = parts[1].split(separator: "-").map { Int($0)! }
    let home = names.firstIndex(of: parts[0])!, away = names.firstIndex(of: parts[2])!
    let h = goals[0], a = goals[1]
    stats[home][0] += 1
    stats[away][0] += 1
    stats[home][4] += h
    stats[home][5] += a
    stats[away][4] += a
    stats[away][5] += h
    if h == a {
        stats[home][2] += 1
        stats[away][2] += 1
    } else {
        stats[h > a ? home : away][1] += 1
        stats[h > a ? away : home][3] += 1
    }
}
let order = names.indices.sorted { a,b in
    let pa = 3 * stats[a][1] + stats[a][2], pb = 3 * stats[b][1] + stats[b][2]
    if pa != pb { return pa > pb }
    let ga = stats[a][4] - stats[a][5], gb = stats[b][4] - stats[b][5]
    if ga != gb { return ga > gb }
    if stats[a][4] != stats[b][4] { return stats[a][4] > stats[b][4] }
    return names[a] < names[b]
}
for (position,i) in order.enumerated() {
    let gd = stats[i][4] - stats[i][5], difference = (gd > 0 ? "+" : "") + String(gd)
    print("\(position + 1). \(names[i]) P=\(stats[i][0]) W=\(stats[i][1]) D=\(stats[i][2]) " +
        "L=\(stats[i][3]) GF=\(stats[i][4]) GA=\(stats[i][5]) GD=\(difference) Pts=\(3 * stats[i][1] + stats[i][2])")
}
