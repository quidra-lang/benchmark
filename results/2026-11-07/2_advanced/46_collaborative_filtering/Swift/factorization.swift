import Foundation

struct RandomGenerator {
    var state: Int64
    mutating func draw() -> Int64 { state = 48271 * state % 2147483647; return state }
    mutating func factor() -> Double { Double(draw() % 2001 - 1000) / 10000 }
}

func dot(_ left: [Double], _ right: [Double]) -> Double { sequentialSum(zip(left, right).map { $0 * $1 }) }

struct TrainingEntry {
    let method: String
    let epoch: Int
    let error: Double
}

struct FactorModel {
    let mean: Double
    var users: [Int: [Double]]
    var items: [Int: [Double]]
    var userBias: [Int: Double]
    var itemBias: [Int: Double]

    func predict(_ user: Int, _ item: Int) -> Double { ((mean + userBias[user]!) + itemBias[item]!) + dot(users[user]!, items[item]!) }
}

func trainSVD(_ data: Ratings) -> (model: FactorModel, log: [TrainingEntry]) {
    let params = data.params
    var random = RandomGenerator(state: params.seed)
    let users = Dictionary(uniqueKeysWithValues: data.users.map { ($0, (0..<params.factors).map { _ in random.factor() }) })
    let items = Dictionary(uniqueKeysWithValues: data.items.map { ($0, (0..<params.factors).map { _ in random.factor() }) })
    var model = FactorModel(mean: data.mean, users: users, items: items,
                            userBias: Dictionary(uniqueKeysWithValues: data.users.map { ($0, 0) }), itemBias: Dictionary(uniqueKeysWithValues: data.items.map { ($0, 0) }))
    var order = Array(data.training.indices), log: [TrainingEntry] = []
    let rate = params.learningRate, regularization = params.regularization
    for epoch in 1...params.epochs {
        for position in (1..<order.count).reversed() { order.swapAt(position, Int(random.draw() % Int64(position + 1))) }
        for position in order {
            let row = data.training[position], u = row.user, i = row.item
            let error = Double(row.rating) - model.predict(u, i)
            model.userBias[u] = model.userBias[u]! + rate * (error - regularization * model.userBias[u]!)
            model.itemBias[i] = model.itemBias[i]! + rate * (error - regularization * model.itemBias[i]!)
            var p = model.users[u]!, q = model.items[i]!
            for f in 0..<params.factors {
                let a = p[f], b = q[f]
                p[f] = a + rate * (error * b - regularization * a)
                q[f] = b + rate * (error * a - regularization * b)
            }
            model.users[u] = p
            model.items[i] = q
        }
        log.append(TrainingEntry(method: "SVD", epoch: epoch, error: trainingRMSE(data.training, model.predict)))
    }
    return (model, log)
}

func choleskySolve(_ matrix: [[Double]], _ target: [Double]) -> [Double] {
    let size = target.count
    var lower = Array(repeating: Array(repeating: 0.0, count: size), count: size)
    for row in 0..<size {
        for column in 0...row {
            let total = sequentialSum((0..<column).map { lower[row][$0] * lower[column][$0] })
            let remainder = matrix[row][column] - total
            lower[row][column] = row == column ? sqrt(remainder) : remainder / lower[column][column]
        }
    }
    var intermediate = Array(repeating: 0.0, count: size), solution = Array(repeating: 0.0, count: size)
    for row in 0..<size {
        let total = sequentialSum((0..<row).map { lower[row][$0] * intermediate[$0] })
        intermediate[row] = (target[row] - total) / lower[row][row]
    }
    for row in (0..<size).reversed() {
        let total = sequentialSum(((row + 1)..<size).map { lower[$0][row] * solution[$0] })
        solution[row] = (intermediate[row] - total) / lower[row][row]
    }
    return solution
}

func fitVector(_ observations: [(vector: [Double], residual: Double)], _ factors: Int, _ regularization: Double) -> [Double] {
    var matrix = Array(repeating: Array(repeating: 0.0, count: factors), count: factors)
    var target = Array(repeating: 0.0, count: factors)
    for observation in observations {
        for row in 0..<factors {
            target[row] = target[row] + observation.residual * observation.vector[row]
            for column in 0..<factors { matrix[row][column] = matrix[row][column] + observation.vector[row] * observation.vector[column] }
        }
    }
    for row in 0..<factors { matrix[row][row] = matrix[row][row] + regularization * Double(observations.count) }
    return choleskySolve(matrix, target)
}

func trainALS(_ data: Ratings, _ userBias: [Int: Double], _ itemBias: [Int: Double]) -> (model: FactorModel, log: [TrainingEntry]) {
    let params = data.params
    var random = RandomGenerator(state: params.seed)
    let items = Dictionary(uniqueKeysWithValues: data.items.map { ($0, (0..<params.factors).map { _ in random.factor() }) })
    var model = FactorModel(mean: data.mean, users: [:], items: items, userBias: userBias, itemBias: itemBias)
    var log: [TrainingEntry] = []
    for iteration in 1...params.alsIterations {
        for u in data.users {
            let observations = data.userItems[u]!.map { i in
                (vector: model.items[i]!, residual: Double(data.byUser[u]![i]!) - ((data.mean + userBias[u]!) + itemBias[i]!))
            }
            model.users[u] = fitVector(observations, params.factors, params.alsRegularization)
        }
        for i in data.items {
            let observations = data.itemUsers[i]!.map { u in
                (vector: model.users[u]!, residual: Double(data.byItem[i]![u]!) - ((data.mean + userBias[u]!) + itemBias[i]!))
            }
            model.items[i] = fitVector(observations, params.factors, params.alsRegularization)
        }
        log.append(TrainingEntry(method: "ALS", epoch: iteration, error: trainingRMSE(data.training, model.predict)))
    }
    return (model, log)
}
