import Foundation

struct EventSums {
    let s0: Double
    let s1: [Double]
    let events: Int
}

struct CoxEvaluation {
    let logLikelihood: Double
    let score: [Double]
    let information: Matrix
    let predictors: [Double]
    let eventSums: [Int: EventSums]
}

struct CoxIteration {
    let number: Int
    let likelihood: Double
    let beta: [Double]
}

struct CoxFit {
    let beta: [Double]
    let null: CoxEvaluation
    let finalEvaluation: CoxEvaluation
    let iterations: [CoxIteration]
}

func evaluateCox(_ subjects: [Subject], _ vectors: [[Int]], _ beta: [Double]) -> CoxEvaluation {
    let size = beta.count
    let predictors = vectors.map { vector in total(beta.indices.map { beta[$0] * Double(vector[$0]) }) }
    let risks = predictors.map(exp)
    let order = subjects.indices.sorted {
        subjects[$0].time == subjects[$1].time ? subjects[$0].id < subjects[$1].id : subjects[$0].time > subjects[$1].time
    }
    var s0 = 0.0
    var s1 = Array(repeating: 0.0, count: size)
    var s2 = Array(repeating: s1, count: size)
    var likelihood = 0.0
    var score = s1
    var information = s2
    var eventSums: [Int: EventSums] = [:]
    var first = 0
    while first < order.count {
        let time = subjects[order[first]].time
        var last = first + 1
        while last < order.count && subjects[order[last]].time == time { last += 1 }
        let atTime = order[first..<last]
        for index in atTime {
            let risk = risks[index]
            let vector = vectors[index]
            s0 += risk
            for c in 0..<size {
                s1[c] += risk * Double(vector[c])
                for d in 0..<size { s2[c][d] += risk * Double(vector[c]) * Double(vector[d]) }
            }
        }
        let events = atTime.filter { subjects[$0].event == 1 }
        if !events.isEmpty {
            let count = Double(events.count)
            likelihood += total(events.map { predictors[$0] }) - count * log(s0)
            for c in 0..<size {
                let observed = events.reduce(0) { $0 + vectors[$1][c] }
                score[c] += Double(observed) - count * s1[c] / s0
                for d in 0..<size { information[c][d] += count * (s2[c][d] / s0 - (s1[c] / s0) * (s1[d] / s0)) }
            }
            eventSums[time] = EventSums(s0: s0, s1: s1, events: events.count)
        }
        first = last
    }
    return CoxEvaluation(logLikelihood: likelihood, score: score, information: information, predictors: predictors, eventSums: eventSums)
}

func fitCox(_ subjects: [Subject], _ vectors: [[Int]]) -> CoxFit {
    var beta = Array(repeating: 0.0, count: vectors[0].count)
    let null = evaluateCox(subjects, vectors, beta)
    var current = null
    var iterations: [CoxIteration] = []
    for iteration in 1...25 {
        let change = solve(current.information, current.score)
        beta = beta.indices.map { beta[$0] + change[$0] }
        iterations.append(CoxIteration(number: iteration, likelihood: current.logLikelihood, beta: beta))
        current = evaluateCox(subjects, vectors, beta)
    }
    return CoxFit(beta: beta, null: null, finalEvaluation: current, iterations: iterations)
}
