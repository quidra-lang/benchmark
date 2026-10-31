import Foundation

func vectorLength(_ values: [Double]) -> Double {
    var total = 0.0
    for value in values { total += value * value }
    return sqrt(total)
}
struct Rocchio {
    let idf: [Double]
    let centroids: [[Double]]
    let lengths: [Double]
    init(_ sequences: [[Int]], _ labels: [Int], _ classCount: Int, _ frequencies: [Int]) {
        let idf = frequencies.map { log(Double(sequences.count) / Double($0)) }
        var sums = Array(repeating: Array(repeating: 0.0, count: frequencies.count), count: classCount)
        var documents = Array(repeating: 0, count: classCount)
        for (sequence, label) in zip(sequences, labels) {
            documents[label] += 1
            let vector = Rocchio.vector(sequence, idf), length = vectorLength(vector)
            if length > 0 { for term in vector.indices { sums[label][term] += vector[term] / length } }
        }
        var centroids = sums
        for label in 0..<classCount { for term in frequencies.indices { centroids[label][term] /= Double(documents[label]) } }
        self.idf = idf; self.centroids = centroids; lengths = centroids.map(vectorLength)
    }
    private static func vector(_ sequence: [Int], _ idf: [Double]) -> [Double] {
        var frequencies = Array(repeating: 0, count: idf.count)
        for term in sequence { frequencies[term] += 1 }
        return idf.indices.map { Double(frequencies[$0]) * idf[$0] }
    }
    func predict(_ sequence: [Int]) -> Prediction {
        let vector = Rocchio.vector(sequence, idf), length = vectorLength(vector)
        var similarities: [Double] = []
        for label in centroids.indices {
            if length > 0 && lengths[label] > 0 {
                var product = 0.0
                for term in vector.indices { product += vector[term] * centroids[label][term] }
                similarities.append(product / (length * lengths[label]))
            } else { similarities.append(0) }
        }
        let ranking = similarities.indices.sorted { similarities[$0] == similarities[$1] ? $0 < $1 : similarities[$0] > similarities[$1] }
        let label = ranking[0]
        return Prediction(label: label, score: similarities[label], ranking: ranking, scores: similarities, probabilities: [], normalizer: 0, margin: 0)
    }
}
