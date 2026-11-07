import Foundation

struct Scaling {
    let centers: [Double]
    let scales: [Double]
    func transform(_ values: [Double], _ features: [Int]) -> [Double] { features.map { scales[$0] > 0 ? (values[$0] - centers[$0]) / scales[$0] : 0 } }
}
func computeScaling(_ rows: [Row], _ method: String) -> Scaling {
    var centers: [Double] = []
    var scales: [Double] = []
    for feature in rows[0].values.indices {
        let column = rows.map { $0.values[feature] }
        if method == "minmax" { centers.append(column.min()!); scales.append(column.max()! - column.min()!) }
        else {
            var total = 0.0
            for value in column { total += value }
            let center = total / Double(rows.count)
            var squares = 0.0
            for value in column { squares += (value - center) * (value - center) }
            centers.append(center)
            scales.append(rows.count == 1 ? 0 : sqrt(squares / Double(rows.count - 1)))
        }
    }
    return Scaling(centers: centers, scales: scales)
}
