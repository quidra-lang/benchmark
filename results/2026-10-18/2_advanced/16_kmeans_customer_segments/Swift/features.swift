import Foundation

let featureNames = ["recency", "frequency", "monetary", "basket", "categories", "tenure"]
let sqrtFeatures = [false, true, true, true, false, false]
typealias Point = [Double]

struct Customer {
    let id: String
    let orders: [Order]
    let recency: Int
    let frequency: Int
    let spend: Int64
    let basket: Double
    let categorySpend: [String: Int64]
    let categories: Int
    let tenure: Int

    init(_ id: String, _ orders: [Order], _ day: Int) {
        self.id = id
        self.orders = orders
        recency = day - orders.map(\.day).max()!
        tenure = day - orders.map(\.day).min()!
        frequency = orders.count
        let totalSpend = orders.reduce(Int64(0)) { $0 + $1.net }
        spend = totalSpend
        basket = (Double(totalSpend) / 100) / Double(orders.count)
        var amounts: [String: Int64] = [:]
        for order in orders { for row in order.rows { amounts[row.category, default: 0] += row.amount } }
        categorySpend = amounts
        categories = amounts.values.filter { $0 > 0 }.count
    }

    var values: Point {
        [Double(recency), Double(frequency), Double(spend) / 100, basket, Double(categories), Double(tenure)]
    }

    var transformed: Point {
        values.enumerated().map { index, value in sqrtFeatures[index] ? sqrt(value) : value }
    }
}

func eligibleCustomers(_ orders: [Order], _ day: Int) -> [Customer] {
    let grouped = ordersByCustomer(orders.filter { $0.net > 0 })
    return grouped.keys.sorted(by: asciiLess).map { Customer($0, grouped[$0]!, day) }
}

func orderedSum(_ values: [Double]) -> Double {
    var total = 0.0
    for value in values { total += value }
    return total
}

func mean(_ values: [Double]) -> Double { orderedSum(values) / Double(values.count) }

func sampleSD(_ values: [Double]) -> Double {
    let average = mean(values)
    var total = 0.0
    for value in values {
        let difference = value - average
        total += difference * difference
    }
    return sqrt(total / Double(values.count - 1))
}

func standardization(_ rows: [Point]) -> (means: Point, sds: Point) {
    let columns = featureNames.indices.map { feature in rows.map { $0[feature] } }
    return (columns.map(mean), columns.map(sampleSD))
}

func standardize(_ values: [Double], _ means: [Double], _ sds: [Double]) -> Point {
    values.indices.map { sds[$0] == 0 ? 0 : (values[$0] - means[$0]) / sds[$0] }
}

func correlation(_ points: [Point], _ first: Int, _ second: Int) -> Double {
    var total = 0.0
    for point in points { total += point[first] * point[second] }
    return total / Double(points.count - 1)
}
