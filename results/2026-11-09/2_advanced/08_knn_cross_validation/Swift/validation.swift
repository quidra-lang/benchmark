import Foundation

struct Model {
    let k: Int
    let metric: String
    let weighting: String
    let scaling: String
    func notation() -> String { "k=\(k) metric=\(metric) weighting=\(weighting) scaling=\(scaling)" }
}
struct Prediction {
    let nearest: [Neighbor]
    let vote: Vote
    let estimate: Double
    var label: String { vote.label }
    var share: Double { vote.share }
    var runner: String? { vote.runner }
    var runnerShare: Double { vote.runnerShare }
}
func stratifiedFolds(_ rows: [Row], _ count: Int) -> [[Int]] {
    var folds = Array(repeating: [Int](), count: count)
    let ordered = rows.indices.sorted { rows[$0].label! == rows[$1].label! ? rows[$0].id < rows[$1].id : rows[$0].label! < rows[$1].label! }
    for (position, index) in ordered.enumerated() { folds[position % count].append(index) }
    return folds.map { $0.sorted() }
}
func foldTraining(_ rows: [Row], _ fold: [Int]) -> [Row] { let excluded = Set(fold); return rows.enumerated().filter { !excluded.contains($0.offset) }.map(\.element) }
func neighborOrders(_ training: [Row], _ queries: [Row], _ method: String, _ metric: String, _ features: [Int]) -> [[Neighbor]] {
    let scaling = computeScaling(training, method)
    let references = training.map { (scaling.transform($0.values, features), $0) }
    return queries.map { neighborOrder(scaling.transform($0.values, features), references, metric) }
}
func predictionFromOrder(_ order: [Neighbor], _ k: Int, _ weighting: String) -> Prediction {
    let nearest = Array(order.prefix(k))
    return Prediction(nearest: nearest, vote: vote(nearest, weighting), estimate: estimate(nearest, weighting))
}
func predictRows(_ model: Model, _ training: [Row], _ queries: [Row], _ features: [Int]) -> [Prediction] { neighborOrders(training, queries, model.scaling, model.metric, features).map { predictionFromOrder($0, model.k, model.weighting) } }
func rmse(_ errors: [Double]) -> Double { var total = 0.0; for error in errors { total += error * error }; return sqrt(total / Double(errors.count)) }
func mae(_ errors: [Double]) -> Double { var total = 0.0; for error in errors { total += abs(error) }; return total / Double(errors.count) }
func rSquared(_ errors: [Double], _ targets: [Double]) -> Double {
    var total = 0.0
    for target in targets { total += target }
    let mean = total / Double(targets.count)
    var residual = 0.0
    var spread = 0.0
    for error in errors { residual += error * error }
    for target in targets { spread += (target - mean) * (target - mean) }
    return 1 - residual / spread
}
