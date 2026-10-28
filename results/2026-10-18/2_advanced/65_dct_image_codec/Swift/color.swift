import Foundation

struct RGB: Equatable { let red: Int; let green: Int; let blue: Int }
typealias RGBImage = [[RGB]]
func clamp(_ value: Int) -> Int { min(max(value, 0), 255) }
func toYCbCr(_ pixel: RGB) -> [Int] { let r = pixel.red, g = pixel.green, b = pixel.blue; return [floorDivide(19595 * r + 38470 * g + 7471 * b + 32768, 65536), floorDivide(-11059 * r - 21709 * g + 32768 * b + 8421375, 65536), floorDivide(32768 * r - 27439 * g - 5329 * b + 8421375, 65536)] }
func toRGB(_ y: Int, _ cb: Int, _ cr: Int) -> RGB { RGB(red: clamp(y + floorDivide(91881 * (cr - 128) + 32768, 65536)), green: clamp(y + floorDivide(-22554 * (cb - 128) - 46802 * (cr - 128) + 32768, 65536)), blue: clamp(y + floorDivide(116130 * (cb - 128) + 32768, 65536))) }
func splitPlanes(_ image: RGBImage) -> [Plane] { let height = image.count, width = image[0].count; var planes = Array(repeating: Array(repeating: Array(repeating: 0, count: width), count: height), count: 3); for y in 0..<height { for x in 0..<width { let values = toYCbCr(image[y][x]); for component in 0..<3 { planes[component][y][x] = values[component] } } }; return planes }
func componentPlanes(_ planes: [Plane], _ factors: [(Int, Int)], _ mcuColumns: Int, _ mcuRows: Int) -> [Plane] {
    let width = planes[0][0].count, height = planes[0].count, hmax = factors.map { $0.0 }.max()!, vmax = factors.map { $0.1 }.max()!
    var result: [Plane] = []
    for (component, factor) in factors.enumerated() { let fx = hmax / factor.0, fy = vmax / factor.1; var plane: Plane = []; for y in 0..<(8 * factor.1 * mcuRows) { var row: [Int] = []; for x in 0..<(8 * factor.0 * mcuColumns) { var sum = 0; for j in 0..<fy { for i in 0..<fx { sum += planes[component][min(fy * y + j, height - 1)][min(fx * x + i, width - 1)] } }; row.append(sum / (fx * fy)) }; plane.append(row) }; result.append(plane) }
    return result
}
func upsample(_ planes: [Plane], _ factors: [(Int, Int)], _ width: Int, _ height: Int) -> [Plane] { let hmax = factors.map { $0.0 }.max()!, vmax = factors.map { $0.1 }.max()!; return factors.enumerated().map { component, factor in (0..<height).map { y in (0..<width).map { x in planes[component][y * factor.1 / vmax][x * factor.0 / hmax] } } } }
func combineRGB(_ planes: [Plane]) -> RGBImage { planes[0].indices.map { y in planes[0][y].indices.map { x in toRGB(planes[0][y][x], planes[1][y][x], planes[2][y][x]) } } }
