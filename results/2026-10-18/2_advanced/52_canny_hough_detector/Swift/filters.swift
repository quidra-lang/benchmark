import Foundation

func clamped(_ image: Image, _ x: Int, _ y: Int) -> Int { image[min(max(y, 0), image.count - 1)][min(max(x, 0), image[0].count - 1)] }

func smoothing(_ image: Image, _ params: Parameters) -> Image {
    let size = params.gaussSize, half = size / 2
    return image.indices.map { y in image[0].indices.map { x in
        var total = 0
        for j in 0..<size { for i in 0..<size { total += params.gaussKernel[j * size + i] * clamped(image, x + i - half, y + j - half) } }
        return total / params.gaussDivisor
    } }
}

struct Gradient { let x: Image; let y: Image; let magnitude: Image }

func gradient(_ image: Image) -> Gradient {
    let height = image.count, width = image[0].count
    var gx = Array(repeating: Array(repeating: 0, count: width), count: height), gy = gx, magnitude = gx
    for y in 0..<height {
        for x in 0..<width {
            let q1 = clamped(image, x - 1, y - 1), q2 = clamped(image, x, y - 1), q3 = clamped(image, x + 1, y - 1)
            let q4 = clamped(image, x - 1, y), q6 = clamped(image, x + 1, y)
            let q7 = clamped(image, x - 1, y + 1), q8 = clamped(image, x, y + 1), q9 = clamped(image, x + 1, y + 1)
            gx[y][x] = (q3 + 2 * q6 + q9) - (q1 + 2 * q4 + q7)
            gy[y][x] = (q7 + 2 * q8 + q9) - (q1 + 2 * q2 + q3)
            magnitude[y][x] = abs(gx[y][x]) + abs(gy[y][x])
        }
    }
    return Gradient(x: gx, y: gy, magnitude: magnitude)
}
