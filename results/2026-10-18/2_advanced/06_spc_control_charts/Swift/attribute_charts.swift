import Foundation

struct AttributeCenter {
    let chart: String
    let value: Double
    let fraction: Double
}
struct LotPoint {
    let lot: Lot
    let value: Double
    let lcl: Double
    let ucl: Double
    let z: Double
    let status: String
}
func attributeCenter(_ chart: String, _ lots: [Lot]) -> AttributeCenter {
    let defectives = lots.reduce(0) { $0 + $1.defectives }
    let defects = lots.reduce(0) { $0 + $1.defects }
    let inspected = lots.reduce(0) { $0 + $1.inspected }
    let fraction = Double(defectives) / Double(inspected)
    let center: Double
    switch chart {
    case "p": center = fraction
    case "np": center = Double(defectives) / Double(lots.count)
    case "c": center = Double(defects) / Double(lots.count)
    default: center = Double(defects) / Double(inspected)
    }
    return AttributeCenter(chart: chart, value: center, fraction: fraction)
}
func attributePoint(_ lot: Lot, _ center: AttributeCenter) -> LotPoint {
    let cl = center.value
    let value: Double
    let sigma: Double
    switch center.chart {
    case "p": value = Double(lot.defectives) / Double(lot.inspected); sigma = sqrt(cl * (1 - cl) / Double(lot.inspected))
    case "np": value = Double(lot.defectives); sigma = sqrt(cl * (1 - center.fraction))
    case "c": value = Double(lot.defects); sigma = sqrt(cl)
    default: value = Double(lot.defects) / Double(lot.inspected); sigma = sqrt(cl / Double(lot.inspected))
    }
    let lcl = max(0, cl - 3 * sigma)
    let ucl = cl + 3 * sigma
    let status = value > ucl ? "high" : value < lcl ? "low" : "ok"
    return LotPoint(lot: lot, value: value, lcl: lcl, ucl: ucl, z: (value - cl) / sigma, status: status)
}
