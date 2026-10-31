import Foundation

func columnMeans(_ rows: Matrix) -> [Double] {
    rows[0].indices.map { j in sequentialSum(rows.map { $0[j] }) / Double(rows.count) }
}

func covarianceMatrix(_ rows: Matrix, _ means: [Double]) -> Matrix {
    var covariance = Array(repeating: Array(repeating: 0.0, count: means.count), count: means.count)
    let deviations = rows.map { row in means.indices.map { row[$0] - means[$0] } }
    for j in means.indices {
        for k in j..<means.count {
            let value = sequentialSum(deviations.map { $0[j] * $0[k] }) / Double(rows.count - 1)
            covariance[j][k] = value
            covariance[k][j] = value
        }
    }
    return covariance
}

func standardDeviations(_ covariance: Matrix) -> [Double] { covariance.indices.map { sqrt(covariance[$0][$0]) } }

func correlationMatrix(_ covariance: Matrix, _ deviations: [Double]) -> Matrix {
    covariance.indices.map { j in covariance.indices.map { k in j == k ? 1 : covariance[j][k] / (deviations[j] * deviations[k]) } }
}

func standardize(_ values: [Double?], _ means: [Double], _ scales: [Double]) -> [Double] {
    values.indices.map { j in values[j].map { ($0 - means[j]) / scales[j] } ?? 0 }
}

func componentScores(_ z: [Double], _ vectors: Matrix) -> [Double] { vectors.map { dot(z, $0) } }

func residuals(_ z: [Double], _ scores: [Double], _ vectors: Matrix, _ count: Int) -> [Double] {
    z.indices.map { j in z[j] - sequentialSum((0..<count).map { scores[$0] * vectors[$0][j] }) }
}

func hotellingT2(_ scores: [Double], _ eigenvalues: [Double], _ count: Int) -> Double {
    sequentialSum((0..<count).map { scores[$0] * scores[$0] / eigenvalues[$0] })
}
