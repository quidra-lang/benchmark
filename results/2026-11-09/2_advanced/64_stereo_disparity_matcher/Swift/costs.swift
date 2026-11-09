import Foundation

func clamped(_ image: [Int], _ width: Int, _ height: Int, _ x: Int, _ y: Int) -> Int { image[min(max(y, 0), height - 1) * width + min(max(x, 0), width - 1)] }
func boxSum(_ image: [Int], _ width: Int, _ height: Int, _ window: Int) -> [Int] {
    let radius = window / 2, paddedWidth = width + 2 * radius, paddedHeight = height + 2 * radius
    var integral = Array(repeating: Array(repeating: 0, count: paddedWidth + 1), count: paddedHeight + 1)
    for y in 0..<paddedHeight { var rowSum = 0; for x in 0..<paddedWidth { rowSum += clamped(image, width, height, x - radius, y - radius); integral[y + 1][x + 1] = integral[y][x + 1] + rowSum } }
    return (0..<height).flatMap { y in (0..<width).map { x in integral[y + window][x + window] - integral[y][x + window] - integral[y + window][x] + integral[y][x] } }
}
func census(_ image: [Int], _ width: Int, _ height: Int) -> [Int] {
    var result: [Int] = []
    for y in 0..<height { for x in 0..<width { var code = 0; let center = image[y * width + x]; for dy in -2...2 { for dx in -2...2 where dx != 0 || dy != 0 { code = (code << 1) | (clamped(image, width, height, x + dx, y + dy) < center ? 1 : 0) } }; result.append(code) } }
    return result
}
func texture(_ image: [Int], _ width: Int, _ height: Int, _ window: Int) -> [Int] { let gradient = (0..<height).flatMap { y in (0..<width).map { x in abs(clamped(image, width, height, x + 1, y) - clamped(image, width, height, x - 1, y)) } }; return boxSum(gradient, width, height, window) }
func costVolume(_ left: [Int], _ right: [Int], _ censusLeft: [Int], _ censusRight: [Int], _ width: Int, _ height: Int, _ kind: CostKind, _ window: Int, _ minimum: Int, _ maximum: Int) -> [[Int]] {
    var volume = Array(repeating: [Int](), count: left.count)
    for disparity in minimum...maximum { var pixels: [Int] = []; for y in 0..<height { for x in 0..<width { let p = y * width + x, q = y * width + max(x - disparity, 0); if kind == .census { pixels.append((censusLeft[p] ^ censusRight[q]).nonzeroBitCount) } else { let difference = left[p] - right[q]; pixels.append(kind == .sad ? abs(difference) : difference * difference) } } }; let sums = boxSum(pixels, width, height, window); for p in volume.indices { volume[p].append(sums[p]) } }
    return volume
}
