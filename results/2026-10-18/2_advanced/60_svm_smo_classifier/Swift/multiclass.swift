import Foundation

let classPairs = [(1, 2), (1, 3), (2, 3)]
struct Classification { let restValues: [Double]; let pairValues: [Double]; let rest: Int; let pair: Int; let votes: [Int]; let tied: Bool }
struct MulticlassModels {
    let kernel: Kernel
    let coefficient: Double
    let restModels: [Model]
    let pairModels: [Model]
    init(_ examples: [MulticlassExample], _ kernel: Kernel, _ coefficient: Double, _ settings: Settings) {
        let points = examples.map { $0.point }, classes = examples.map { $0.classNumber }, matrix = kernel.matrix(points)
        var rest: [Model] = [], pairs: [Model] = []
        for number in 1...3 { rest.append(train(points, classes.map { $0 == number ? 1 : -1 }, kernel, matrix, coefficient, settings)) }
        for (first, second) in classPairs { let indices = classes.indices.filter { classes[$0] == first || classes[$0] == second }; pairs.append(train(indices.map { points[$0] }, indices.map { classes[$0] == first ? 1 : -1 }, kernel, submatrix(matrix, indices), coefficient, settings)) }
        self.kernel = kernel; self.coefficient = coefficient; restModels = rest; pairModels = pairs
    }
    func classify(_ point: Point) -> Classification {
        let rest = restModels.map { $0.decision(point) }
        var restPrediction = 0, values: [Double] = [], votes = [0, 0, 0], scores = [0.0, 0, 0]
        for i in 1..<3 { if rest[i] > rest[restPrediction] { restPrediction = i } }
        for (i, pair) in classPairs.enumerated() { let value = pairModels[i].decision(point), winner = value > 0 ? pair.0 : pair.1; values.append(value); votes[winner - 1] += 1; scores[pair.0 - 1] += value; scores[pair.1 - 1] -= value }
        let maximum = votes.max()!, candidates = votes.indices.filter { votes[$0] == maximum }
        var prediction = candidates[0]
        for i in candidates.dropFirst() { if scores[i] > scores[prediction] { prediction = i } }
        return Classification(restValues: rest, pairValues: values, rest: restPrediction + 1, pair: prediction + 1, votes: votes, tied: candidates.count > 1)
    }
}
