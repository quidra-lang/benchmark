func bradleyTerry(_ count: Int, _ matches: [Match], _ iterations: Int) -> ([Double], Double) {
    var wins = Array(repeating: 0, count: count)
    var homeWins = 0
    for match in matches { wins[match.home] += match.resultTwice; wins[match.away] += 2 - match.resultTwice; homeWins += match.resultTwice }
    var strengths = Array(repeating: 1.0, count: count)
    var theta = 1.0
    for _ in 0..<iterations {
        var zeta = Array(repeating: 0.0, count: count)
        for match in matches { let q = theta * strengths[match.home] + strengths[match.away]; zeta[match.home] += theta / q; zeta[match.away] += 1 / q }
        for team in 0..<count { strengths[team] = (Double(wins[team]) / 2) / zeta[team] }
        var total = 0.0
        for strength in strengths { total += strength }
        for team in 0..<count { strengths[team] = strengths[team] * Double(count) / total }
        var denominator = 0.0
        for match in matches { let home = strengths[match.home]; denominator += home / (theta * home + strengths[match.away]) }
        theta = (Double(homeWins) / 2) / denominator
    }
    return (strengths, theta)
}
func offenseDefense(_ count: Int, _ matches: [Match], _ iterations: Int) -> ([Double], [Double], [Double]) {
    var points = Array(repeating: Array(repeating: 0, count: count), count: count)
    for match in matches { points[match.home][match.away] += match.awayScore; points[match.away][match.home] += match.homeScore }
    var offense = Array(repeating: 0.0, count: count)
    var defense = Array(repeating: 1.0, count: count)
    for _ in 0..<iterations {
        for j in 0..<count { var total = 0.0; for i in 0..<count { total += Double(points[i][j]) / defense[i] }; offense[j] = total }
        for i in 0..<count { var total = 0.0; for j in 0..<count { total += Double(points[i][j]) / offense[j] }; defense[i] = total }
    }
    return (offense, defense, (0..<count).map { offense[$0] / defense[$0] })
}
