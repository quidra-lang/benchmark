import Foundation

struct Team { let code: String; let name: String }
struct Match {
    let round: Int
    let home: Int
    let away: Int
    let homeScore: Int
    let awayScore: Int
    let fileOrder: Int
    var margin: Int { homeScore - awayScore }
    var resultTwice: Int { homeScore > awayScore ? 2 : (homeScore == awayScore ? 1 : 0) }
    var result: Fraction { Fraction(resultTwice, 2) }
    var y: Double { Double(resultTwice) / 2 }
}
struct Settings {
    let winPoints: Int
    let drawPoints: Int
    let formLength: Int
    let closeMargin: Int
    let exponent: Double
    let eloK: Int
    let eloHome: Int
    let eloInitial: Int
    let gridK: [Int]
    let gridHome: [Int]
    let btIterations: Int
    let odIterations: Int
    let linkIterations: Int
    let holdoutRound: Int
    let upsets: Int
    let calibrationBins: Int
    let simulations: Int
    let seed: Int
    let topPositions: Int
    let bottomPositions: Int
    init(_ lines: [String]) {
        let values = Dictionary(uniqueKeysWithValues: lines.map { line -> (String, [String]) in let words = line.split(separator: " ").map(String.init); return (words[0], Array(words.dropFirst())) })
        func integer(_ key: String) -> Int { Int(values[key]![0])! }
        winPoints = integer("WIN_POINTS"); drawPoints = integer("DRAW_POINTS"); formLength = integer("FORM_LENGTH"); closeMargin = integer("CLOSE_MARGIN")
        exponent = Double(values["PYTHAGOREAN_EXPONENT"]![0])!; eloK = integer("ELO_K"); eloHome = integer("ELO_HOME"); eloInitial = integer("ELO_INITIAL")
        gridK = values["ELO_GRID_K"]!.map { Int($0)! }; gridHome = values["ELO_GRID_HOME"]!.map { Int($0)! }
        btIterations = integer("BT_ITERATIONS"); odIterations = integer("OD_ITERATIONS"); linkIterations = integer("LINK_ITERATIONS"); holdoutRound = integer("HOLDOUT_ROUND")
        upsets = integer("UPSETS"); calibrationBins = integer("CALIBRATION_BINS"); simulations = integer("SIMULATIONS"); seed = integer("SIM_SEED")
        topPositions = integer("TOP_POSITIONS"); bottomPositions = integer("BOTTOM_POSITIONS")
    }
}
func matchesBefore(_ matches: [Match], _ round: Int) -> [Match] { matches.filter { $0.round < round } }
func loadSeason() throws -> ([Team], [Match], Settings) {
    func lines(_ name: String) throws -> [String] { try String(contentsOfFile: "input/" + name, encoding: .utf8).split(separator: "\n").map(String.init) }
    let teams = try lines("teams.csv").dropFirst().map { line -> Team in let words = line.split(separator: ",").map(String.init); return Team(code: words[0], name: words[1]) }
    let indices = Dictionary(uniqueKeysWithValues: teams.enumerated().map { ($0.element.code, $0.offset) })
    let matches = try lines("matches.csv").dropFirst().enumerated().map { index, line -> Match in
        let words = line.split(separator: ",").map(String.init)
        return Match(round: Int(words[0])!, home: indices[words[1]]!, away: indices[words[2]]!, homeScore: Int(words[3])!, awayScore: Int(words[4])!, fileOrder: index)
    }.sorted { $0.round == $1.round ? $0.fileOrder < $1.fileOrder : $0.round < $1.round }
    return (teams, matches, Settings(try lines("params.txt")))
}
