import Foundation

let ratingModels = ["elo", "colley", "massey", "bt", "od", "winpct"]
let comparisonModels = ["standings", "elo", "colley", "massey", "bt", "od", "winpct", "rpi", "pythag"]
let linkModels = ["colley", "massey", "od", "winpct"]
let predictionModels = ["base", "elo", "colley", "massey", "bt", "od", "winpct", "ensemble"]
let standingsHeader = "pos,team,name,played,won,drawn,lost,scored,conceded,diff,points,home,away,form,streak,close,longest_win,longest_unbeaten,winpct,sos,sos2,rpi,pythag,luck"
let ratingsHeader = "team,elo,elo_rank,colley,colley_rank,massey,massey_rank,bt,bt_rank,offense,defense,od,od_rank,winpct,winpct_rank,consensus,best_rank,worst_rank"
let historyHeader = "round,team,elo,change,elo_rank,points,position"
let projectionHeader = "projected,team,points_now,position_now,remaining_opponent_elo,expected_points,title,top,bottom,final_points,final_position"
func sequentialSum(_ values: [Double]) -> Double { var total = 0.0; for value in values { total += value }; return total }
func mean(_ values: [Double]) -> Double { sequentialSum(values) / Double(values.count) }
func competitionRanks(_ values: [Fraction]) -> [Int] { values.map { value in 1 + values.filter { $0 > value }.count } }
func roundedValues(_ values: [Double], _ places: Int) -> [Fraction] { values.map { Fraction(decimalValue($0, places)) } }
func joinParts(_ parts: [[String]]) -> [String] { var lines: [String] = []; for part in parts { if !lines.isEmpty { lines.append("") }; lines += part }; return lines }
struct Appearance {
    let match: Match
    let home: Bool
    let opponent: Int
    let scored: Int
    let conceded: Int
    let letter: Character
    init(_ match: Match, _ team: Int) {
        let home = match.home == team
        let scored = home ? match.homeScore : match.awayScore, conceded = home ? match.awayScore : match.homeScore
        self.match = match; self.home = home; opponent = home ? match.away : match.home; self.scored = scored; self.conceded = conceded
        letter = scored > conceded ? "W" : (scored == conceded ? "D" : "L")
    }
}
func appearancesOf(_ team: Int, _ matches: [Match]) -> [Appearance] { matches.filter { $0.home == team || $0.away == team }.map { Appearance($0, team) } }
func recordText(_ appearances: [Appearance]) -> String {
    "\(appearances.filter { $0.letter == "W" }.count)-\(appearances.filter { $0.letter == "D" }.count)-\(appearances.filter { $0.letter == "L" }.count)"
}
struct Record {
    var played = 0, won = 0, drawn = 0, lost = 0, scored = 0, conceded = 0, points = 0
    mutating func add(_ scored: Int, _ conceded: Int, _ settings: Settings) {
        played += 1; self.scored += scored; self.conceded += conceded
        if scored > conceded { won += 1; points += settings.winPoints }
        else if scored == conceded { drawn += 1; points += settings.drawPoints }
        else { lost += 1 }
    }
    var difference: Int { scored - conceded }
    var winPercentage: Fraction { Fraction(2 * won + drawn, 2 * played) }
}
func teamRecords(_ count: Int, _ matches: [Match], _ settings: Settings) -> [Record] {
    var records = Array(repeating: Record(), count: count)
    for match in matches { records[match.home].add(match.homeScore, match.awayScore, settings); records[match.away].add(match.awayScore, match.homeScore, settings) }
    return records
}
struct Standings {
    let records: [Record]
    let h2hPoints: [Int]
    let h2hDifference: [Int]
    let order: [Int]
    let positions: [Int]
    init(_ teams: [Team], _ matches: [Match], _ settings: Settings) {
        let count = teams.count
        let records = teamRecords(count, matches, settings)
        var groups: [Int: Set<Int>] = [:]
        for team in 0..<count { groups[records[team].points, default: []].insert(team) }
        var h2hPoints = Array(repeating: 0, count: count), h2hDifference = Array(repeating: 0, count: count)
        for members in groups.values {
            let inner = teamRecords(count, matches.filter { members.contains($0.home) && members.contains($0.away) }, settings)
            for team in members { h2hPoints[team] = inner[team].points; h2hDifference[team] = inner[team].difference }
        }
        let order = (0..<count).sorted { a, b in
            (-records[a].points, -h2hPoints[a], -h2hDifference[a], -records[a].difference, -records[a].scored, teams[a].code) <
                (-records[b].points, -h2hPoints[b], -h2hDifference[b], -records[b].difference, -records[b].scored, teams[b].code)
        }
        var positions = Array(repeating: 0, count: count)
        for (index, team) in order.enumerated() { positions[team] = index + 1 }
        self.records = records; self.h2hPoints = h2hPoints; self.h2hDifference = h2hDifference; self.order = order; self.positions = positions
    }
    func tiedGroups() -> [[Int]] {
        var groups: [[Int]] = []
        for team in order {
            if let previous = groups.last, records[previous[0]].points == records[team].points { groups[groups.count - 1].append(team) }
            else { groups.append([team]) }
        }
        return groups.filter { $0.count >= 2 }
    }
}
struct Streak { let length: Int; let first: Int; let last: Int }
func longestStreak(_ appearances: [Appearance], _ unbeaten: Bool) -> Streak {
    var best = Streak(length: 0, first: 0, last: 0)
    var start = 0, length = 0
    for (index, item) in appearances.enumerated() {
        if item.letter != "W" && !(unbeaten && item.letter == "D") { length = 0; continue }
        if length == 0 { start = index }
        length += 1
        if length > best.length { best = Streak(length: length, first: appearances[start].match.round, last: item.match.round) }
    }
    return best
}
func currentStreak(_ appearances: [Appearance]) -> String {
    let last = appearances.last!.letter
    let count = appearances.reversed().prefix(while: { $0.letter == last }).count
    return "\(last)\(count)"
}
struct ModelFit {
    let elo: EloRun
    let colley: [Double]
    let massey: [Double]
    let homeAdvantage: Double
    let strengths: [Double]
    let homeFactor: Double
    let offense: [Double]
    let defense: [Double]
    let od: [Double]
    let winPercentages: [Fraction]
    init(_ count: Int, _ matches: [Match], _ settings: Settings) {
        elo = runElo(count, matches, settings.eloK, settings.eloHome, settings.eloInitial)
        colley = colleyRatings(count, matches)
        let linear = masseyRatings(count, matches); massey = linear.0; homeAdvantage = linear.1
        let bt = bradleyTerry(count, matches, settings.btIterations); strengths = bt.0; homeFactor = bt.1
        let ratings = offenseDefense(count, matches, settings.odIterations); offense = ratings.0; defense = ratings.1; od = ratings.2
        winPercentages = teamRecords(count, matches, settings).map(\.winPercentage)
    }
    func feature(_ model: Int, _ match: Match) -> Double {
        switch model {
        case 0: return colley[match.home] - colley[match.away]
        case 1: return massey[match.home] - massey[match.away]
        case 2: return log(od[match.home]) - log(od[match.away])
        default: return winPercentages[match.home].real - winPercentages[match.away].real
        }
    }
    func btProbability(_ match: Match) -> Double { let home = homeFactor * strengths[match.home]; return home / (home + strengths[match.away]) }
    func predictedMargin(_ match: Match) -> Double { massey[match.home] - massey[match.away] + homeAdvantage }
}
struct Prediction {
    let match: Match
    let probabilities: [Double]
    let losses: [Double]
    let briers: [Double]
    let scores: [Int]
    let marginError: Double
    init(_ match: Match, _ probabilities: [Double], _ marginError: Double) {
        self.match = match; self.probabilities = probabilities; self.marginError = marginError
        losses = probabilities.map { logLoss($0, match.resultTwice) }; briers = probabilities.map { brierScore($0, match.resultTwice) }; scores = probabilities.map { correctnessTwice($0, match.resultTwice) }
    }
}
struct ValidationRound {
    let number: Int
    let trainingCount: Int
    let fit: ModelFit
    let base: Double
    let links: [(Double, Double)]
    let predictions: [Prediction]
    init(_ number: Int, _ count: Int, _ matches: [Match], _ settings: Settings) {
        let training = matchesBefore(matches, number)
        let fit = ModelFit(count, training, settings)
        let base = Fraction(training.reduce(0) { $0 + $1.resultTwice }, 2 * training.count).real
        let results = training.map(\.y)
        let links = (0..<4).map { model in fitLink(training.map { fit.feature(model, $0) }, results, settings.linkIterations) }
        var predictions: [Prediction] = []
        for match in matches where match.round == number {
            var probabilities = Array(repeating: 0.0, count: 8)
            probabilities[0] = base; probabilities[1] = expectedScore(fit.elo.ratings[match.home], fit.elo.ratings[match.away], settings.eloHome)
            for (model, target) in [2, 3, 5, 6].enumerated() { probabilities[target] = sigma(links[model].0 + links[model].1 * fit.feature(model, match)) }
            probabilities[4] = fit.btProbability(match)
            probabilities[7] = sequentialSum([1, 2, 3, 4, 5, 6].map { probabilities[$0] }) / 6
            predictions.append(Prediction(match, probabilities, Double(match.margin) - fit.predictedMargin(match)))
        }
        self.number = number; trainingCount = training.count; self.fit = fit; self.base = base; self.links = links; self.predictions = predictions
    }
}
struct ModelScores {
    let losses: [Double]
    let briers: [Double]
    let skills: [Double]
    let accuracies: [Fraction]
    let lossRanking: [Int]
    let brierRanking: [Int]
    let accuracyRanking: [Int]
    init(_ predictions: [Prediction]) {
        let count = predictions.count
        let losses = (0..<8).map { model in mean(predictions.map { $0.losses[model] }) }
        let briers = (0..<8).map { model in mean(predictions.map { $0.briers[model] }) }
        let accuracies = (0..<8).map { model in Fraction(predictions.reduce(0) { $0 + $1.scores[model] }, 2 * count) }
        self.losses = losses; self.briers = briers; skills = briers.map { 1 - $0 / briers[0] }; self.accuracies = accuracies
        lossRanking = (0..<8).sorted { (decimalValue(losses[$0], 4), $0) < (decimalValue(losses[$1], 4), $1) }
        brierRanking = (0..<8).sorted { (decimalValue(briers[$0], 4), $0) < (decimalValue(briers[$1], 4), $1) }
        accuracyRanking = (0..<8).sorted { accuracies[$0] == accuracies[$1] ? $0 < $1 : accuracies[$0] > accuracies[$1] }
    }
}
struct Projection {
    let current: Standings
    let ratings: [Double]
    let remaining: [Match]
    let totalPoints: [Int]
    let titles: [Int]
    let tops: [Int]
    let bottoms: [Int]
    let order: [Int]
    let ranks: [Int]
    init(_ teams: [Team], _ matches: [Match], _ settings: Settings) {
        let count = teams.count
        let currentMatches = matchesBefore(matches, settings.holdoutRound)
        let current = Standings(teams, currentMatches, settings)
        let ratings = runElo(count, currentMatches, settings.eloK, settings.eloHome, settings.eloInitial).ratings
        let remaining = matches.filter { $0.round >= settings.holdoutRound }
        let probabilities = remaining.map { expectedScore(ratings[$0.home], ratings[$0.away], settings.eloHome) }
        var totalPoints = Array(repeating: 0, count: count), titles = Array(repeating: 0, count: count), tops = Array(repeating: 0, count: count), bottoms = Array(repeating: 0, count: count)
        var state = settings.seed
        for _ in 0..<settings.simulations {
            var points = current.records.map(\.points)
            for (match, probability) in zip(remaining, probabilities) {
                state = 48271 * state % 2147483647
                let winner = Double(state) / 2147483647 < probability ? match.home : match.away
                points[winner] += settings.winPoints
            }
            let order = (0..<count).sorted { (-points[$0], current.positions[$0]) < (-points[$1], current.positions[$1]) }
            for (index, team) in order.enumerated() {
                totalPoints[team] += points[team]
                if index == 0 { titles[team] += 1 }
                if index + 1 <= settings.topPositions { tops[team] += 1 }
                if index + 1 >= count - settings.bottomPositions + 1 { bottoms[team] += 1 }
            }
        }
        let order = (0..<count).sorted { (-totalPoints[$0], current.positions[$0]) < (-totalPoints[$1], current.positions[$1]) }
        var ranks = Array(repeating: 0, count: count)
        for (index, team) in order.enumerated() { ranks[team] = index + 1 }
        self.current = current; self.ratings = ratings; self.remaining = remaining; self.totalPoints = totalPoints; self.titles = titles; self.tops = tops; self.bottoms = bottoms; self.order = order; self.ranks = ranks
    }
    func opponentStrength(_ team: Int) -> Double {
        var values: [Double] = []
        for match in remaining { if match.home == team { values.append(ratings[match.away]) } else if match.away == team { values.append(ratings[match.home]) } }
        return mean(values)
    }
}
final class LeagueAnalysis {
    let teams: [Team]
    let matches: [Match]
    let settings: Settings
    let appearances: [[Appearance]]
    let finalTable: Standings
    let fit: ModelFit
    let roundTables: [Standings]
    let winStreaks: [Streak]
    let unbeatenStreaks: [Streak]
    let sos: [Fraction]
    let sos2: [Fraction]
    let rpi: [Fraction]
    let pythag: [Double]
    let luck: [Double]
    let comparison: [[Fraction]]
    let ranks: [[Int]]
    let rounds: [ValidationRound]
    let scores: ModelScores
    let projection: Projection
    var finalRound: Int { roundTables.count }
    var predictions: [Prediction] { rounds.flatMap(\.predictions) }
    init(_ teams: [Team], _ matches: [Match], _ settings: Settings) {
        let count = teams.count
        let finalRound = matches.last!.round
        let appearances = (0..<count).map { appearancesOf($0, matches) }
        let finalTable = Standings(teams, matches, settings)
        let fit = ModelFit(count, matches, settings)
        func opponentAverage(_ values: [Fraction]) -> [Fraction] {
            appearances.map { items in var total = Fraction(0); for item in items { total = total + values[item.opponent] }; return total / Fraction(items.count) }
        }
        let sos = opponentAverage(fit.winPercentages), sos2 = opponentAverage(sos)
        let rpi = (0..<count).map { (fit.winPercentages[$0] + Fraction(2) * sos[$0] + sos2[$0]) / Fraction(4) }
        let pythag = finalTable.records.map { 1 / (1 + pow(Double($0.conceded) / Double($0.scored), settings.exponent)) }
        let comparison = [finalTable.positions.map { Fraction(-$0) }, roundedValues(fit.elo.ratings, 2), roundedValues(fit.colley, 4), roundedValues(fit.massey, 4),
            roundedValues(fit.strengths, 4), roundedValues(fit.od, 2), fit.winPercentages, rpi, roundedValues(pythag, 4)]
        let rounds = (settings.holdoutRound...finalRound).map { ValidationRound($0, count, matches, settings) }
        self.teams = teams; self.matches = matches; self.settings = settings; self.appearances = appearances; self.finalTable = finalTable; self.fit = fit
        roundTables = (1...finalRound).map { Standings(teams, matchesBefore(matches, $0 + 1), settings) }
        winStreaks = appearances.map { longestStreak($0, false) }; unbeatenStreaks = appearances.map { longestStreak($0, true) }
        self.sos = sos; self.sos2 = sos2; self.rpi = rpi; self.pythag = pythag; luck = (0..<count).map { fit.winPercentages[$0].real - pythag[$0] }
        self.comparison = comparison; ranks = (1...ratingModels.count).map { competitionRanks(comparison[$0]) }; self.rounds = rounds
        scores = ModelScores(rounds.flatMap(\.predictions)); projection = Projection(teams, matches, settings)
    }
    func code(_ team: Int) -> String { teams[team].code }
    func standingsLines() -> [String] {
        var lines = [standingsHeader]
        for (position, team) in finalTable.order.enumerated() {
            let record = finalTable.records[team], items = appearances[team]
            let home = recordText(items.filter(\.home)), away = recordText(items.filter { !$0.home }), close = recordText(items.filter { abs($0.scored - $0.conceded) <= settings.closeMargin })
            let form = String(items.suffix(settings.formLength).map(\.letter))
            lines.append([String(position + 1), code(team), teams[team].name, String(record.played), String(record.won), String(record.drawn), String(record.lost), String(record.scored), String(record.conceded),
                String(record.difference), String(record.points), home, away, form, currentStreak(items), close, String(winStreaks[team].length), String(unbeatenStreaks[team].length), fit.winPercentages[team].text,
                sos[team].fixed(), sos2[team].fixed(), rpi[team].fixed(), fixed(pythag[team]), fixed(luck[team])].joined(separator: ","))
        }
        return lines
    }
    func ratingsLines() -> [String] {
        let totals = teams.indices.map { team in ranks.reduce(0) { $0 + $1[team] } }
        let order = teams.indices.sorted { (totals[$0], code($0)) < (totals[$1], code($1)) }
        var lines = [ratingsHeader]
        for team in order {
            let rank = ranks.map { $0[team] }
            lines.append([code(team), fixed(fit.elo.ratings[team], 2), String(rank[0]), fixed(fit.colley[team]), String(rank[1]), fixed(fit.massey[team]), String(rank[2]), fixed(fit.strengths[team]), String(rank[3]),
                fixed(fit.offense[team], 2), fixed(fit.defense[team]), fixed(fit.od[team], 2), String(rank[4]), fit.winPercentages[team].fixed(), String(rank[5]), String(totals[team]), String(rank.min()!), String(rank.max()!)].joined(separator: ","))
        }
        return lines
    }
    func historyLines() -> [String] {
        var lines = [historyHeader]
        var previous = Array(repeating: Double(settings.eloInitial), count: teams.count)
        for (index, table) in roundTables.enumerated() {
            let ratings = fit.elo.roundRatings[index], ranks = competitionRanks(roundedValues(fit.elo.roundRatings[index], 2))
            for team in teams.indices { lines.append("\(index + 1),\(code(team)),\(fixed(ratings[team], 2)),\(fixed(ratings[team] - previous[team], 2)),\(ranks[team]),\(table.records[team].points),\(table.positions[team])") }
            previous = ratings
        }
        return lines
    }
}

extension LeagueAnalysis {
    func summaryLines() -> [String] {
        let won = matches.filter { $0.resultTwice == 2 }.count, drawn = matches.filter { $0.resultTwice == 1 }.count
        let rate = Fraction(2 * won + drawn, 2 * matches.count)
        return ["season teams \(teams.count) matches \(matches.count) rounds \(finalRound)", "home won \(won) drawn \(drawn) lost \(matches.count - won - drawn) rate \(rate.withReal)",
            "massey_home_advantage \(fixed(fit.homeAdvantage))", "bt_home_factor \(fixed(fit.homeFactor))"]
    }
    func upsetLines() -> [String] {
        let candidates = matches.indices.filter { matches[$0].margin != 0 }.map { index in (index, matches[index].margin > 0 ? fit.elo.expected[index] : 1 - fit.elo.expected[index]) }
            .sorted { (decimalValue($0.1, 4), $0.0) < (decimalValue($1.1, 4), $1.0) }
        var lines = ["upsets top \(settings.upsets)"]
        for (index, expected) in candidates.prefix(settings.upsets) {
            let match = matches[index]
            let home = match.margin > 0
            let winner = home ? match.home : match.away, loser = home ? match.away : match.home
            let scored = home ? match.homeScore : match.awayScore, conceded = home ? match.awayScore : match.homeScore
            lines.append("round \(match.round) \(code(winner)) beat \(code(loser)) \(scored)-\(conceded) \(home ? "home" : "away") expected \(fixed(expected)) gain \(fixed(abs(fit.elo.changes[index]), 2))")
        }
        return lines
    }
    func tiebreakLines() -> [String] {
        var lines = ["tiebreaks"]
        for group in finalTable.tiedGroups() {
            let order = group.map(code).joined(separator: " "), points = group.map { String(finalTable.h2hPoints[$0]) }.joined(separator: " "), difference = group.map { String(finalTable.h2hDifference[$0]) }.joined(separator: " ")
            lines.append("points \(finalTable.records[group[0]].points) order \(order) h2h_points \(points) h2h_diff \(difference)")
        }
        if lines.count == 1 { lines.append("none") }
        return lines
    }
    func leaderLines() -> [String] {
        var lines = ["leaders"]
        var previous: Int?
        var recorded = 0
        for (index, table) in roundTables.enumerated() {
            let leader = table.order[0]
            if leader != previous { lines.append("round \(index + 1) \(code(leader)) points \(table.records[leader].points)"); recorded += 1 }
            previous = leader
        }
        lines.append("lead_changes \(recorded - 1)")
        return lines
    }
    func streakLines() -> [String] {
        var lines: [String] = []
        for (label, streaks) in [("longest_win_streak", winStreaks), ("longest_unbeaten_streak", unbeatenStreaks)] {
            let longest = streaks.map(\.length).max()!
            for (team, streak) in streaks.enumerated() where streak.length == longest { lines.append("\(label) \(code(team)) length \(streak.length) rounds \(streak.first)-\(streak.last)") }
        }
        return lines
    }
    func crosstableLines() -> [String] {
        let top = Array(finalTable.order.prefix(settings.topPositions))
        var lines = ["crosstable top \(settings.topPositions)", "team " + top.map(code).joined(separator: " ")]
        for first in top {
            let entries = top.map { second in first == second ? "-" : recordText(appearances[first].filter { $0.opponent == second }) }
            lines.append(code(first) + " " + entries.joined(separator: " "))
        }
        return lines
    }
    func trajectoryLines() -> [String] {
        var lines = ["trajectories"]
        for team in teams.indices {
            let ratings = fit.elo.roundRatings.map { $0[team] }, rounded = fit.elo.roundRatings.map { decimalValue($0[team], 2) }, positions = roundTables.map { $0.positions[team] }
            var peak = 0, low = 0, best = 0, worst = 0
            for index in 1..<finalRound {
                if rounded[index] > rounded[peak] { peak = index }
                if rounded[index] < rounded[low] { low = index }
                if positions[index] < positions[best] { best = index }
                if positions[index] > positions[worst] { worst = index }
            }
            lines.append("\(code(team)) elo_peak \(fixed(ratings[peak], 2)) round \(peak + 1) elo_low \(fixed(ratings[low], 2)) round \(low + 1) best_position \(positions[best]) round \(best + 1) worst_position \(positions[worst]) round \(worst + 1)")
        }
        return lines
    }
    func correlationLines(_ title: String, _ measure: ([Fraction], [Fraction]) -> Fraction) -> [String] {
        var lines = [title, "model " + comparisonModels.joined(separator: " ")]
        for (first, label) in comparisonModels.enumerated() { lines.append(label + " " + comparison.map { measure(comparison[first], $0).text }.joined(separator: " ")) }
        return lines
    }
    func similarityLines() -> [String] {
        var pairs: [(Int, Int, Fraction)] = []
        for first in comparisonModels.indices { for second in (first + 1)..<comparisonModels.count { pairs.append((first, second, kendallTau(comparison[first], comparison[second]))) } }
        var most = pairs[0], least = pairs[0]
        for pair in pairs.dropFirst() { if pair.2 > most.2 { most = pair }; if pair.2 < least.2 { least = pair } }
        return [("most_similar", most), ("least_similar", least)].map { label, pair in "\(label) \(comparisonModels[pair.0]) \(comparisonModels[pair.1]) tau \(pair.2.withReal)" }
    }
    func seasonLines() -> [String] { joinParts([summaryLines(), upsetLines(), tiebreakLines(), leaderLines(), streakLines(), crosstableLines(), trajectoryLines(), correlationLines("kendall", kendallTau), correlationLines("spearman", spearmanRho), similarityLines()]) }
    func predictionLines() -> [String] {
        var lines = ["round,home,away,home_score,away_score,result," + predictionModels.joined(separator: ",")]
        for prediction in predictions {
            let match = prediction.match
            let result = match.resultTwice == 2 ? "H" : (match.resultTwice == 0 ? "A" : "D")
            let fields = [String(match.round), code(match.home), code(match.away), String(match.homeScore), String(match.awayScore), result] + prediction.probabilities.map { fixed($0) }
            lines.append(fields.joined(separator: ","))
        }
        return lines
    }
    func linkLines() -> [String] {
        var lines = ["links"]
        for validation in rounds {
            var parts = ["round \(validation.number) train \(validation.trainingCount) base \(fixed(validation.base)) bt_home \(fixed(validation.fit.homeFactor))"]
            for (model, name) in linkModels.enumerated() { parts.append("\(name) \(fixed(validation.links[model].0)) \(fixed(validation.links[model].1))") }
            lines.append(parts.joined(separator: " "))
        }
        return lines
    }
    func scoreLines() -> [String] {
        var lines = ["scores", "model log_loss brier skill accuracy"]
        for (model, name) in predictionModels.enumerated() { lines.append("\(name) \(fixed(scores.losses[model])) \(fixed(scores.briers[model])) \(fixed(scores.skills[model])) \(scores.accuracies[model].withReal)") }
        for (label, ranking) in [("ranking_log_loss", scores.lossRanking), ("ranking_brier", scores.brierRanking), ("ranking_accuracy", scores.accuracyRanking)] { lines.append(label + " " + ranking.map { predictionModels[$0] }.joined(separator: " ")) }
        return lines
    }
    func pairedLines() -> [String] {
        let reference = scores.lossRanking[0]
        let count = predictions.count
        var lines = ["paired_log_loss reference " + predictionModels[reference]]
        for (model, name) in predictionModels.enumerated() where model != reference {
            let deltas = predictions.map { $0.losses[model] - $0.losses[reference] }
            let average = mean(deltas)
            let spread = sqrt(sequentialSum(deltas.map { ($0 - average) * ($0 - average) }) / Double(count - 1))
            let statistic = average / (spread / sqrt(Double(count)))
            lines.append("\(name) mean_diff \(fixed(average)) sd \(fixed(spread)) t \(fixed(statistic, 2))")
        }
        return lines
    }
    func marginLines() -> [String] {
        let errors = predictions.map(\.marginError)
        let absolute = mean(errors.map { abs($0) }), squared = sqrt(mean(errors.map { $0 * $0 })), bias = mean(errors)
        return ["massey_margin mae \(fixed(absolute)) rmse \(fixed(squared)) bias \(fixed(bias))"]
    }
    func roundLossLines() -> [String] {
        var lines = ["round_log_loss", "round " + predictionModels.joined(separator: " ")]
        for validation in rounds { lines.append("\(validation.number) " + (0..<8).map { model in fixed(mean(validation.predictions.map { $0.losses[model] })) }.joined(separator: " ")) }
        return lines
    }
    func calibrationLines() -> [String] {
        let bins = settings.calibrationBins
        var lines = ["calibration bins \(bins)"]
        for (model, name) in predictionModels.enumerated() {
            var groups: [[Prediction]] = Array(repeating: [], count: bins)
            for prediction in predictions { let bin = min(Int(floor(Double(bins) * prediction.probabilities[model])), bins - 1); groups[bin].append(prediction) }
            for (index, group) in groups.enumerated() {
                if group.isEmpty { lines.append("\(name) bin \(index + 1) count 0 predicted - observed -"); continue }
                let predicted = mean(group.map { $0.probabilities[model] }), observed = Fraction(group.reduce(0) { $0 + $1.match.resultTwice }, 2 * group.count)
                lines.append("\(name) bin \(index + 1) count \(group.count) predicted \(fixed(predicted)) observed \(observed.text)")
            }
        }
        return lines
    }
    func gridLines() -> [String] {
        var lines = ["elo_grid", "k " + settings.gridHome.map { "h\($0)" }.joined(separator: " ")]
        var best: (Int, Int, Double)?
        for k in settings.gridK {
            var row = [String(k)]
            for home in settings.gridHome {
                let run = runElo(teams.count, matches, k, home, settings.eloInitial)
                let losses = matches.indices.filter { matches[$0].round >= settings.holdoutRound }.map { logLoss(run.expected[$0], matches[$0].resultTwice) }
                let loss = mean(losses)
                row.append(fixed(loss))
                if best == nil || decimalValue(loss, 4) < decimalValue(best!.2, 4) { best = (k, home, loss) }
            }
            lines.append(row.joined(separator: " "))
        }
        lines.append("best k \(best!.0) home \(best!.1) log_loss \(fixed(best!.2))")
        return lines
    }
    func projectionTau() -> Fraction { kendallTau(projection.ranks.map { Fraction(-$0) }, finalTable.positions.map { Fraction(-$0) }) }
    func evaluationLines() -> [String] {
        joinParts([["holdout rounds \(settings.holdoutRound)-\(finalRound) matches \(predictions.count)"], linkLines(), scoreLines(), pairedLines(), marginLines(), roundLossLines(), calibrationLines(), gridLines(),
            ["projection simulations \(settings.simulations) kendall \(projectionTau().withReal)"]])
    }
    func projectionLines() -> [String] {
        var lines = [projectionHeader]
        let simulations = settings.simulations
        for (index, team) in projection.order.enumerated() {
            lines.append([String(index + 1), code(team), String(projection.current.records[team].points), String(projection.current.positions[team]), fixed(projection.opponentStrength(team), 2),
                Fraction(projection.totalPoints[team], simulations).fixed(), Fraction(projection.titles[team], simulations).fixed(), Fraction(projection.tops[team], simulations).fixed(), Fraction(projection.bottoms[team], simulations).fixed(),
                String(finalTable.records[team].points), String(finalTable.positions[team])].joined(separator: ","))
        }
        return lines
    }
    func outputFiles() -> [(String, [String])] { [("standings.csv", standingsLines()), ("ratings.csv", ratingsLines()), ("history.csv", historyLines()), ("season.txt", seasonLines()), ("predictions.csv", predictionLines()), ("evaluation.txt", evaluationLines()), ("projection.csv", projectionLines())] }
}

let (teams, matches, settings) = try loadSeason()
let analysis = LeagueAnalysis(teams, matches, settings)
try FileManager.default.createDirectory(atPath: "output", withIntermediateDirectories: true)
for (name, lines) in analysis.outputFiles() { try writeLines("output/" + name, lines) }
