import Foundation

struct Covariance {
    let a: Double
    let b: Double
    let c: Double
    var determinant: Double { a * c - b * b }
    func mahalanobis(_ point: Vector2, _ mean: Vector2) -> Double {
        let dx = point.x - mean.x, dy = point.y - mean.y
        return (c * dx * dx - 2 * b * dx * dy + a * dy * dy) / determinant
    }
}
struct Ellipse {
    let leading: Double
    let trailing: Double
    let direction: Vector2
    let angle: Double
    let major: Double
    let minor: Double
    let area: Double
    let correlation: Double
}
func weightedLogDensity(_ point: Vector2, _ weight: Double, _ mean: Vector2, _ covariance: Covariance) -> Double {
    log(weight) - log(2 * Double.pi) - log(covariance.determinant) / 2 - covariance.mahalanobis(point, mean) / 2
}
func ellipse(_ covariance: Covariance) -> Ellipse {
    let a = covariance.a, b = covariance.b, c = covariance.c, half = (a + c) / 2, difference = (a - c) / 2
    let spread = sqrt(difference * difference + b * b), leading = half + spread, trailing = half - spread
    let direction: Vector2
    if b == 0 { direction = a >= c ? Vector2(x: 1, y: 0) : Vector2(x: 0, y: 1) }
    else {
        let vx = a >= c ? leading - c : b, vy = a >= c ? b : leading - a, length = sqrt(vx * vx + vy * vy), sign = vx < 0 ? -1.0 : 1.0
        direction = Vector2(x: sign * vx / length, y: sign * vy / length)
    }
    return Ellipse(leading: leading, trailing: trailing, direction: direction, angle: atan2(direction.y, direction.x) * 180 / Double.pi, major: sqrt(leading), minor: sqrt(trailing), area: Double.pi * sqrt(leading * trailing), correlation: b / sqrt(a * c))
}
func bhattacharyya(_ firstMean: Vector2, _ first: Covariance, _ secondMean: Vector2, _ second: Covariance) -> Double {
    let average = Covariance(a: (first.a + second.a) / 2, b: (first.b + second.b) / 2, c: (first.c + second.c) / 2)
    return average.mahalanobis(secondMean, firstMean) / 8 + log(average.determinant / sqrt(first.determinant * second.determinant)) / 2
}
