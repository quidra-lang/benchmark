import Foundation

struct EloRun { var ratings: [Double]; var expected: [Double] = []; var changes: [Double] = []; var roundRatings: [[Double]] = [] }
func expectedScore(_ home: Double, _ away: Double, _ advantage: Int) -> Double { 1 / (1 + pow(10, (away - home - Double(advantage)) / 400)) }
private func multiplier(_ match: Match, _ home: Double, _ away: Double, _ advantage: Int) -> Double {
    let goals = abs(match.margin)
    if goals == 0 { return 1 }
    let difference = match.margin > 0 ? home + Double(advantage) - away : away - home - Double(advantage)
    return log(Double(goals + 1)) * 2.2 / (0.001 * difference + 2.2)
}
func runElo(_ count: Int, _ matches: [Match], _ k: Int, _ advantage: Int, _ initial: Int) -> EloRun {
    var run = EloRun(ratings: Array(repeating: Double(initial), count: count))
    for (index, match) in matches.enumerated() {
        let home = run.ratings[match.home], away = run.ratings[match.away]
        let expected = expectedScore(home, away, advantage)
        let change = Double(k) * multiplier(match, home, away, advantage) * (match.y - expected)
        run.ratings[match.home] = home + change; run.ratings[match.away] = away - change
        run.expected.append(expected); run.changes.append(change)
        if index + 1 == matches.count || matches[index + 1].round != match.round { run.roundRatings.append(run.ratings) }
    }
    return run
}
