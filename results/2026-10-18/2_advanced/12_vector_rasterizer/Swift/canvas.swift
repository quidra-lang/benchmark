struct Point: Hashable { let x: Int; let y: Int }
struct Rectangle {
    let x0: Int; let y0: Int; let x1: Int; let y1: Int
    var isEmpty: Bool { x0 > x1 || y0 > y1 }
    func contains(_ point: Point) -> Bool { x0 <= point.x && point.x <= x1 && y0 <= point.y && point.y <= y1 }
    func intersection(_ other: Rectangle) -> Rectangle { Rectangle(x0: max(x0, other.x0), y0: max(y0, other.y0), x1: min(x1, other.x1), y1: min(y1, other.y1)) }
    var pixels: Set<Point> { if isEmpty { return [] }; return Set((y0...y1).flatMap { y in (x0...x1).map { Point(x: $0, y: y) } }) }
}
struct Color: Hashable {
    let red: Int; let green: Int; let blue: Int; let alpha: Int
    init(_ values: [Int]) { red = values[0]; green = values[1]; blue = values[2]; alpha = values.count == 4 ? values[3] : 255 }
    var channels: [Int] { [red, green, blue, alpha] }
    var rgbText: String { "\(red) \(green) \(blue)" }
    var text: String { rgbText + " \(alpha)" }
}
func floorDivide(_ numerator: Int, _ denominator: Int) -> Int { let quotient = numerator / denominator; return numerator % denominator < 0 ? quotient - 1 : quotient }
func roundRatio(_ numerator: Int, _ denominator: Int) -> Int { let n = denominator < 0 ? -numerator : numerator, d = abs(denominator); return floorDivide(2 * n + d, 2 * d) }
func effectiveAlpha(_ alpha: Int, _ opacity: Int) -> Int { roundRatio(alpha * opacity, 255) }
final class Layer {
    let width: Int; let height: Int; let opacity: Int; let mode: String
    var colors: [Color?]
    var lines: [Int]
    init(_ width: Int, _ height: Int, _ opacity: Int, _ mode: String) { self.width = width; self.height = height; self.opacity = opacity; self.mode = mode; colors = Array(repeating: nil, count: width * height); lines = Array(repeating: 0, count: width * height) }
    func index(_ point: Point) -> Int { point.y * width + point.x }
    func paint(_ point: Point, _ color: Color, _ line: Int) { let index = index(point); colors[index] = color; lines[index] = line }
    func erase(_ point: Point) -> Bool { let index = index(point), painted = colors[index] != nil; colors[index] = nil; return painted }
    func colorAt(_ point: Point) -> Color? { colors[index(point)] }
    func alphaAt(_ point: Point) -> Int { colorAt(point).map { effectiveAlpha($0.alpha, opacity) } ?? 0 }
    func blend(_ point: Point, _ current: Color) -> Color {
        guard let color = colorAt(point) else { return current }
        let alpha = effectiveAlpha(color.alpha, opacity)
        let values = zip(color.channels.prefix(3), current.channels.prefix(3)).map { source, value -> Int in
            let blended = mode == "multiply" ? roundRatio(source * value, 255) : mode == "screen" ? 255 - roundRatio((255 - source) * (255 - value), 255) : source
            return roundRatio(alpha * blended + (255 - alpha) * value, 255)
        }
        return Color(values)
    }
}
func composite(_ layers: [Layer], _ background: Color, _ width: Int, _ height: Int) -> [Color] { (0..<(width * height)).map { index in layers.reduce(background) { $1.blend(Point(x: index % width, y: index / width), $0) } } }
